import Foundation
import FlyingFox
import GemmaTransKit

public struct APIServer: Sendable {
    let translator: any TranslationService
    let server: HTTPServer
    let queueTimeout: Double

    public init(translator: any TranslationService, port: UInt16, queueTimeout: Double = 30) {
        self.translator = translator
        // 显式 IPv4 回环：FlyingFox 的 .loopback 是 ::1，curl/PopClip 等默认走 127.0.0.1
        self.server = HTTPServer(address: try! .inet(ip4: "127.0.0.1", port: port))
        self.queueTimeout = queueTimeout
    }

    public func run() async throws {
        await registerRoutes()
        try await server.run()
    }

    /// 等待监听就绪并返回实际端口（port 0 时由系统分配，测试用）
    public func waitForPort() async throws -> UInt16 {
        try await server.waitUntilListening()
        guard let addr = await server.listeningAddress, case let .ip4(_, port) = addr else {
            throw URLError(.cannotConnectToHost)
        }
        return port
    }

    func registerRoutes() async {
        let t = translator
        await server.appendRoute("GET /health") { _ in
            let ready = await t.isReady
            return try .json(["status": ready ? "ready" : "loading"], statusCode: ready ? .ok : .serviceUnavailable)
        }
        await registerTranslateRoute(server: server, translator: t, queueTimeout: queueTimeout)
        // Task 8 在此追加 chat/completions 路由
    }
}

extension HTTPResponse {
    static func json(_ object: Any, statusCode: HTTPStatusCode = .ok) throws -> HTTPResponse {
        let data = try JSONSerialization.data(withJSONObject: object)
        return HTTPResponse(statusCode: statusCode, headers: [.contentType: "application/json"], body: data)
    }
}
