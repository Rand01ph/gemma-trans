import Foundation
import Observation
import GemmaTransKit
import GemmaTransServer

@MainActor @Observable
final class EngineController {
    enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let shared = EngineController()

    private(set) var status: Status = .loading
    private(set) var engine: TranslationEngine?
    private var serverTask: Task<Void, Error>?
    let settings = AppSettings.load()

    func start() {
        status = .loading
        Task {
            // 单实例守卫：端口上已有活的 GemmaTrans（app 或 CLI serve）就不再加载第二份模型
            if await Self.isPortServing(settings.port) {
                self.status = .failed("端口 \(settings.port) 已有 GemmaTrans 实例在运行")
                GTLog.error("startup aborted: port \(settings.port) already serving")
                return
            }
            let engine = TranslationEngine(settings: settings)
            do {
                try await engine.load()
                self.engine = engine
                let port = settings.port
                self.serverTask = Task.detached {
                    try await APIServer(translator: engine, port: port).run()
                }
                self.watchServerTask()
                self.status = .ready
                GTLog.info("engine ready, serving on \(port)")
            } catch {
                self.status = .failed("\(error)")
                GTLog.error("engine load failed: \(error)")
            }
        }
    }

    /// server 挂掉（如端口被抢）时把状态打出来，而不是无声失败
    private func watchServerTask() {
        guard let task = serverTask else { return }
        Task {
            do {
                try await task.value
            } catch {
                self.status = .failed("API server: \(error)")
                GTLog.error("API server died: \(error)")
            }
        }
    }

    private static func isPortServing(_ port: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        return (try? await URLSession.shared.data(for: req)) != nil
    }
}
