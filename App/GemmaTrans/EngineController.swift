import Foundation
import Observation
import GemmaTransKit
import GemmaTransServer

@MainActor @Observable
final class EngineController {
    /// loading 携带阶段文案（「正在准备…」「网络异常，8s 后第 2/5 次重试…」），
    /// 消灭真机现场的哑状态：清单请求挂死/静默退避时菜单永远只见「模型加载中…」
    enum EngineStatus: Equatable { case loading(String), downloading(DownloadProgress), ready, failed(String) }
    enum APIStatus: Equatable { case disabled, running(UInt16), failed(String) }

    static let shared = EngineController()

    var engineStatus: EngineStatus = .loading("正在准备…")  // 下载进度闭包需写入，放开 setter（仅 App 内部使用）
    private(set) var apiStatus: APIStatus = .disabled
    private(set) var engine: TranslationEngine?
    private var serverTask: Task<Void, Error>?
    private(set) var settings = AppSettings.load()
    /// 在飞加载任务 + 代际号：reload 取消旧任务后，旧任务的迟到回调（进度/重试/失败）
    /// 凭代际号被丢弃，不会覆盖新任务刚置的状态
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    func start() {
        engineStatus = .loading("正在准备…")
        // 重读设置：重试前用户可能在设置页切了国内源开关，「下次下载生效」靠这里兑现
        // （apiEnabled 由 setAPIEnabled 即时落盘，重读不会回退用户操作）
        settings = AppSettings.load()
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task {
            // 单实例守卫（验明正身）：仅真正的 GemmaTrans 实例才放弃启动，防双模型加载；
            // 无关 HTTP 服务占用端口不影响引擎，仅 API 启动时自然失败
            if await Self.isGemmaTransServing(settings.port) {
                guard generation == loadGeneration else { return }
                engineStatus = .failed("端口 \(settings.port) 已有 GemmaTrans 实例在运行")
                GTLog.error("startup aborted: another GemmaTrans on \(settings.port)")
                return
            }
            let engine = TranslationEngine(settings: settings)
            let source: ModelSource = settings.useCNSource ? .modelScope : .huggingFace
            do {
                // 网络错误退避重试 + 断点续传（共享实现见 Kit EngineLoadSupport.swift）：
                // 此前下载断线即变砖，整 app 只能重启；onRetry 把静默退避亮给菜单
                try await withNetworkRetry(onRetry: { attempt, maxRetries, delaySeconds in
                    Task { @MainActor in
                        let shared = EngineController.shared
                        guard generation == shared.loadGeneration else { return }
                        shared.engineStatus =
                            .loading("网络异常，\(delaySeconds)s 后第 \(attempt)/\(maxRetries) 次重试…")
                    }
                }) {
                    try await engine.load(modelSource: source) { progress in
                        Task { @MainActor in
                            let shared = EngineController.shared
                            guard generation == shared.loadGeneration else { return }
                            if progress.fraction < 1.0 {
                                shared.engineStatus = .downloading(progress)
                            } else {
                                // 下载完到就绪之间还有权重进显存 + 预热（冷启可超 30s），
                                // 别让菜单停在临近 100% 的下载态装死
                                shared.engineStatus = .loading("正在加载模型…")
                            }
                        }
                    }
                }
                guard generation == loadGeneration else { return }
                self.engine = engine
                engineStatus = .ready
                GTLog.info("engine ready")
                if settings.apiEnabled { startServer() }
            } catch is CancellationError {
                // reload() 取消旧任务：新任务已接管状态展示，旧任务静默退出
                GTLog.info("engine load cancelled (superseded by reload)")
            } catch {
                guard generation == loadGeneration else { return }
                // UI 只放短句人话（共享映射），完整错误进日志；菜单提供「重新加载引擎」
                engineStatus = .failed(engineLoadFailureMessage(for: error))
                GTLog.error("engine load failed: \(error)")
            }
        }
    }

    /// 菜单「重新加载引擎」入口：非就绪态全程可用（加载中/下载中/重试退避/失败）。
    /// 真机现场：清单请求挂死时旧版只有「永远加载中」无任何出口。
    /// 防重入：先取消在飞任务（Task 取消协作传导到 URLSession，断当前网络等待）再重新
    /// start()；旧任务的迟到回调由 loadGeneration 隔离。就绪态直接忽略（菜单也不展示按钮）。
    func reload() {
        guard engineStatus != .ready else { return }
        GTLog.info("engine reload requested by user")
        loadTask?.cancel()
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
