import Foundation
import FlyingFox
import GemmaTransKit

struct ChatMessage: Decodable {
    let role: String
    let content: String
}

struct ChatRequest: Decodable {
    let messages: [ChatMessage]
    let stream: Bool?
}

/// OpenAI 兼容层：把最后一条 user 消息按"智能双向"翻译。
/// 忽略客户端 system 消息与 model 字段——本服务是翻译器，不是通用聊天。
func registerChatCompletionsRoute(server: HTTPServer, translator: any TranslationService) async {
    await server.appendRoute("POST /v1/chat/completions") { request in
        let body = try await request.bodyData
        guard let req = try? JSONDecoder().decode(ChatRequest.self, from: body),
              let userText = req.messages.last(where: { $0.role == "user" })?.content,
              !userText.isEmpty else {
            return try .json(["error": ["message": "no user message"]], statusCode: .badRequest)
        }
        do {
            let result = try await translator.translate(userText, target: nil)
            if req.stream == true {
                let (dataStream, cont) = AsyncStream.makeStream(of: Data.self)
                Task {
                    do {
                        for try await chunk in result.chunks {
                            cont.yield(SSE.event(chatChunk(content: chunk, finish: nil)))
                        }
                    } catch {
                        // 流中途出错：直接收尾，客户端按 stop 处理
                    }
                    cont.yield(SSE.event(chatChunk(content: nil, finish: "stop")))
                    cont.yield(SSE.done)
                    cont.finish()
                }
                return HTTPResponse(
                    statusCode: .ok, headers: SSE.headers,
                    body: HTTPBodySequence(from: SSEBody(stream: dataStream), suggestedBufferSize: 1024)
                )
            }
            let text = try await result.fullText()
            return try .json([
                "id": "chatcmpl-gemmatrans",
                "object": "chat.completion",
                "model": "gemma-4-e4b-local",
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": text],
                    "finish_reason": "stop",
                ]],
                "usage": ["prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0],
            ])
        } catch TranslationError.modelNotLoaded {
            return try .json(["error": ["message": "model not loaded"]], statusCode: .serviceUnavailable)
        } catch {
            GTLog.error("chat/completions failed: \(error)")
            return try .json(["error": ["message": "\(error)"]], statusCode: .internalServerError)
        }
    }
}

private func chatChunk(content: String?, finish: String?) -> [String: Any] {
    var delta: [String: Any] = [:]
    if let content { delta["content"] = content }
    return [
        "id": "chatcmpl-gemmatrans",
        "object": "chat.completion.chunk",
        "model": "gemma-4-e4b-local",
        "choices": [["index": 0, "delta": delta, "finish_reason": finish as Any]],
    ]
}
