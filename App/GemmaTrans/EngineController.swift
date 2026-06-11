import Foundation
import Observation
import GemmaTransKit
import GemmaTransServer

@MainActor @Observable
final class EngineController {
    enum EngineStatus: Equatable { case loading, downloading(DownloadProgress), ready, failed(String) }
    enum APIStatus: Equatable { case disabled, running(UInt16), failed(String) }

    static let shared = EngineController()

    var engineStatus: EngineStatus = .loading  // 下载进度闭包需写入，放开 setter（仅 App 内部使用）
    private(set) var apiStatus: APIStatus = .disabled
    private(set) var engine: TranslationEngine?
    private var serverTask: Task<Void, Error>?
    private(set) var settings = AppSettings.load()

    func start() {
        engineStatus = .loading
        // 重读设置：重试前用户可能在设置页切了国内源开关，「下次下载生效」靠这里兑现
        // （apiEnabled 由 setAPIEnabled 即时落盘，重读不会回退用户操作）
        settings = AppSettings.load()
        Task {
            // 单实例守卫（验明正身）：仅真正的 GemmaTrans 实例才放弃启动，防双模型加载；
            // 无关 HTTP 服务占用端口不影响引擎，仅 API 启动时自然失败
            if await Self.isGemmaTransServing(settings.port) {
                engineStatus = .failed("端口 \(settings.port) 已有 GemmaTrans 实例在运行")
                GTLog.error("startup aborted: another GemmaTrans on \(settings.port)")
                return
            }
            let engine = TranslationEngine(settings: settings)
            let source: ModelSource = settings.useCNSource ? .modelScope : .huggingFace
            do {
                // 网络错误退避重试 + 断点续传（共享实现见 Kit EngineLoadSupport.swift）：
                // 此前下载断线即变砖，整 app 只能重启
                try await withNetworkRetry {
                    try await engine.load(modelSource: source) { progress in
                        Task { @MainActor in
                            if progress.fraction < 1.0 {
                                EngineController.shared.engineStatus = .downloading(progress)
                            }
                        }
                    }
                }
                self.engine = engine
                engineStatus = .ready
                GTLog.info("engine ready")
                if settings.apiEnabled { startServer() }
            } catch {
                // UI 只放短句人话（共享映射），完整错误进日志；菜单提供「重试加载引擎」
                engineStatus = .failed(engineLoadFailureMessage(for: error))
                GTLog.error("engine load failed: \(error)")
            }
        }
    }

    /// 菜单「重试加载引擎」入口：仅失败态可重入（加载中/就绪时误触不重启流程），
    /// start() 内的端口单实例守卫照常生效
    func retry() {
        guard case .failed = engineStatus else { return }
        GTLog.info("engine retry requested by user")
        start()
    }

    /// 菜单/设置开关入口：即时生效并持久化
    func setAPIEnabled(_ enabled: Bool) {
        settings.apiEnabled = enabled
        settings.save()
        if enabled {
            if engineStatus == .ready { startServer() }
            // 引擎未就绪时由 start() 的 apiEnabled 分支接管
        } else {
            serverTask?.cancel()
            serverTask = nil
            apiStatus = .disabled
            GTLog.info("API disabled by user")
        }
    }

    private func startServer() {
        guard let engine, serverTask == nil else { return }
        let port = settings.port
        let task: Task<Void, Error> = Task.detached {
            try await APIServer(translator: engine, port: port).run()
        }
        serverTask = task
        apiStatus = .running(port)
        GTLog.info("API serving on \(port)")
        Task {
            do { try await task.value }
            catch is CancellationError { /* 用户关闭，状态已在 setAPIEnabled 置 disabled */ }
            catch {
                // 仅在仍处运行态时标记失败（避免覆盖用户主动关闭后的状态）
                if case .running = self.apiStatus {
                    self.apiStatus = .failed("端口 \(port) 不可用")
                    self.serverTask = nil
                    GTLog.error("API server died: \(error)")
                }
            }
        }
    }

    private static func isGemmaTransServing(_ port: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["service"] as? String == "gemmatrans"
    }
}
