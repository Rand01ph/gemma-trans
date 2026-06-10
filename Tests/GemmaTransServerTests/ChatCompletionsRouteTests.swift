import Testing
import Foundation
import FlyingFox
@testable import GemmaTransServer
import GemmaTransKit

@Suite struct ChatCompletionsRouteTests {
    func startServer() async throws -> (URL, Task<Void, Error>) {
        let api = APIServer(translator: MockTranslator(), port: 0)
        let task = Task { try await api.run() }
        let port = try await api.waitForPort()
        return (URL(string: "http://127.0.0.1:\(port)")!, task)
    }

    func post(_ base: URL, _ body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, resp as! HTTPURLResponse)
    }

    @Test func nonStreamCompletion() async throws {
        let (base, task) = try await startServer()
        defer { task.cancel() }
        let (data, resp) = try await post(base, [
            "model": "whatever",
            "messages": [["role": "user", "content": "Hello, world"]],
        ])
        #expect(resp.statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choices = json["choices"] as! [[String: Any]]
        let message = choices[0]["message"] as! [String: Any]
        #expect(message["content"] as? String == "你好，世界")
        #expect(json["object"] as? String == "chat.completion")
    }

    @Test func streamCompletionSendsDeltas() async throws {
        let (base, task) = try await startServer()
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": "Hello"]], "stream": true,
        ])
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        #expect((resp as! HTTPURLResponse).value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true)
        var deltas: [String] = []
        var sawDone = false
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { sawDone = true; break }
            let json = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: Any]
            #expect(json["object"] as? String == "chat.completion.chunk")
            let delta = ((json["choices"] as! [[String: Any]])[0]["delta"] as! [String: Any])
            if let c = delta["content"] as? String { deltas.append(c) }
        }
        #expect(deltas.joined() == "你好，世界")
        #expect(sawDone)
    }

    @Test func noUserMessageReturns400() async throws {
        let (base, task) = try await startServer()
        defer { task.cancel() }
        let (_, resp) = try await post(base, ["messages": [[String: Any]]()])
        #expect(resp.statusCode == 400)
    }
}
