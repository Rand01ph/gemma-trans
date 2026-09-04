import Foundation
import FlyingFox
import GemmaTransKit

public struct APIServer: Sendable {
    /// FlyingFox 默认只给 handler 15 秒，不足以覆盖本地模型的首次生成。
    /// 显式留出 120 秒，让路由自身的 30 秒排队/生成超时能够返回可诊断的 503，
    /// 同时允许 SSE 路由完成响应握手后继续流式输出。
    static let requestTimeout: TimeInterval = 120

    let translator: any TranslationService
    let server: HTTPServer
    let queueTimeout: Double

    public init(translator: any TranslationService, port: UInt16, queueTimeout: Double = 30) {
        self.translator = translator
        // 显式 IPv4 回环：FlyingFox 的 .loopback 是 ::1，curl/PopClip 等默认走 127.0.0.1
        self.server = HTTPServer(
            address: try! .inet(ip4: "127.0.0.1", port: port),
            timeout: Self.requestTimeout
        )
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
            return try .json(
                ["status": ready ? "ready" : "loading", "service": "gemmatrans"],
                statusCode: ready ? .ok : .serviceUnavailable
            )
        }
        await registerTranslateRoute(server: server, translator: t, queueTimeout: queueTimeout)
        await registerChatCompletionsRoute(server: server, translator: t)
    }
}

extension HTTPResponse {
    static func json(_ object: Any, statusCode: HTTPStatusCode = .ok) throws -> HTTPResponse {
        let data = try JSONSerialization.data(withJSONObject: object)
        return HTTPResponse(statusCode: statusCode, headers: [.contentType: "application/json"], body: data)
    }
}
