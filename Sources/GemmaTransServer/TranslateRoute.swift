import Foundation
import FlyingFox
import GemmaTransKit

struct TranslateRequest: Decodable {
    let text: String
    let target: String?
    let stream: Bool?
}

/// 排队/整体超时（spec：30 秒未完成排队产出 → 503）。测试注入小值。
func withQueueTimeout<T: Sendable>(
    _ seconds: Double, _ op: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TranslationError.queueTimeout
        }
        guard let first = try await group.next() else { throw TranslationError.queueTimeout }
        group.cancelAll()
        return first
    }
}

func registerTranslateRoute(
    server: HTTPServer, translator: any TranslationService, queueTimeout: Double = 30
) async {
    await server.appendRoute("POST /translate") { request in
        let body = try await request.bodyData
        guard let req = try? JSONDecoder().decode(TranslateRequest.self, from: body) else {
            return try .json(["error": "invalid JSON, expect {\"text\": ...}"], statusCode: .badRequest)
        }
        do {
            let result = try await translator.translate(req.text, target: req.target)
            // 流式分支 Task 7 实现；本任务先全部走非流式
            let text = try await withQueueTimeout(queueTimeout) { try await result.fullText() }
            return try .json([
                "translation": text,
                "detected": result.detected,
                "target": result.target,
                "truncated": result.truncated,
            ])
        } catch TranslationError.emptyInput {
            return try .json(["error": "text is empty"], statusCode: .badRequest)
        } catch TranslationError.modelNotLoaded {
            return try .json(["error": "model not loaded"], statusCode: .serviceUnavailable)
        } catch TranslationError.queueTimeout {
            return try .json(["error": "engine busy, timed out"], statusCode: .serviceUnavailable)
        }
    }
}
