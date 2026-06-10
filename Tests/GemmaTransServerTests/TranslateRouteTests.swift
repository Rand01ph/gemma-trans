import Testing
import Foundation
import FlyingFox
@testable import GemmaTransServer
import GemmaTransKit

@Suite struct TranslateRouteTests {
    func startServer(
        _ translator: some TranslationService, queueTimeout: Double = 30
    ) async throws -> (URL, Task<Void, Error>) {
        let api = APIServer(translator: translator, port: 0, queueTimeout: queueTimeout)
        let task = Task { try await api.run() }
        let port = try await api.waitForPort()
        return (URL(string: "http://127.0.0.1:\(port)")!, task)
    }

    @Test func healthReturnsReady() async throws {
        let (base, task) = try await startServer(MockTranslator())
        defer { task.cancel() }
        let (data, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("health"))
        #expect((resp as! HTTPURLResponse).statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["status"] as? String == "ready")
    }

    @Test func translateReturnsTranslation() async throws {
        let (base, task) = try await startServer(MockTranslator())
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "Hello, world"])
        let (data, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as! HTTPURLResponse).statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["translation"] as? String == "你好，世界")
        #expect(json["detected"] as? String == "en")
        #expect(json["target"] as? String == "zh-Hans")
    }

    @Test func emptyTextReturns400() async throws {
        let (base, task) = try await startServer(MockTranslator())
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": ""])
        let (_, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as! HTTPURLResponse).statusCode == 400)
    }

    @Test func engineNotReadyReturns503() async throws {
        let (base, task) = try await startServer(MockTranslator(ready: false))
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "hi"])
        let (_, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as! HTTPURLResponse).statusCode == 503)
    }

    @Test func busyEngineTimesOutWith503() async throws {
        let (base, task) = try await startServer(StuckTranslator(), queueTimeout: 0.2)
        defer { task.cancel() }
        var req = URLRequest(url: base.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": "hi"])
        let (_, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as! HTTPURLResponse).statusCode == 503)
    }
}
