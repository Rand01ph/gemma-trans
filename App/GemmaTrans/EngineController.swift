import Foundation
import Observation
import GemmaTransKit
import GemmaTransServer

@MainActor @Observable
final class EngineController {
    /// loading 携带阶段文案（「正在准备…」「网络异常，8s 后第 2/5 次重试…」），
    /// 消灭真机现场的哑状态：清单请求挂死/静默退避时菜单永远只见「模型加载中…」
    enum EngineStatus: Equatable {
        case needsModel(String)
        case loading(String)
        case downloading(DownloadProgress)
        case ready
        case failed(String)
    }
    enum APIStatus: Equatable { case disabled, running(UInt16), failed(String) }

    static let shared = EngineController()

    var engineStatus: EngineStatus = .loading("正在准备…")  // 下载进度闭包需写入，放开 setter（仅 App 内部使用）
    private(set) var apiStatus: APIStatus = .disabled
    private(set) var engine: TranslationEngine?
    private var serverTask: Task<Void, Error>?
    private(set) var settings: AppSettings
    /// 在飞加载任务 + 代际号：reload 取消旧任务后，旧任务的迟到回调（进度/重试/失败）
    /// 凭代际号被丢弃，不会覆盖新任务刚置的状态
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    /// 当前选中的模型 ID（镜像 AppSettings.selectedModelID，供 Task 8 UI 绑定）
    private(set) var selectedModelID: String?

    private init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.selectedModelID = loaded.selectedModelID
    }

    func start() {
        engineStatus = .loading("正在准备…")
        // 重读设置：模型、参数和 API 偏好可能已在设置页修改。
        settings = AppSettings.load()
        // 镜像选中模型 ID：start() 是切换/重载后重新解析模型的统一入口，镜像在此对齐
        selectedModelID = settings.selectedModelID
        loadGeneration += 1
        let generation = loadGeneration
        guard let selectedID = settings.selectedModelID,
              let resolved = ActiveModelResolver.resolve(
                selectedID: selectedID, parameterSettings: settings) else {
            engine = nil
            loadTask = nil
            engineStatus = .needsModel("请在“设置 > 模型”中下载一个模型，再选择使用它。")
            GTLog.info("engine startup waiting for user model selection")
            return
        }
        guard InstalledModels.isInstalled(
            id: selectedID,
            base: TranslationEngine.defaultModelBase(),
            legacyHuggingFaceHub: InstalledModels.defaultLegacyHuggingFaceHub
        ) else {
            engine = nil
            loadTask = nil
            engineStatus = .needsModel("\(resolved.entry.displayName) 尚未下载，请先完成下载。")
            GTLog.info("engine startup waiting for explicit download: \(selectedID)")
            return
        }
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
            // start() 已确认快照完整；这里的进度状态只处理下载完成与加载之间的兼容回调。
            let progressHandler: @Sendable (DownloadProgress) -> Void = { progress in
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
                    try await engine.load(resolved: resolved, progress: progressHandler)
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
        if case .needsModel = engineStatus { return }
        GTLog.info("engine reload requested by user")
        loadTask?.cancel()
        start()
    }

    /// 设置页「切换模型」入口：守卫不过返回原因且不切；过则卸旧载新。
    /// async 以便直接 await actor 的 isGenerating，避免镜像竞态。
    /// 未下载模型在这里直接阻断，下载只能由设置页的显式“下载”按钮触发。
    func switchModel(to id: String) async -> SwitchBlock? {
        guard ActiveModelResolver.resolve(selectedID: id) != nil,
              InstalledModels.isInstalled(
                id: id,
                base: TranslationEngine.defaultModelBase(),
                legacyHuggingFaceHub: InstalledModels.defaultLegacyHuggingFaceHub
              ) else {
            return .notInstalled
        }
        let loadingNow: Bool = {
            if case .loading = engineStatus { return true }
            if case .downloading = engineStatus { return true }
            return false
        }()
        // 切换会先停 API，再由 unload 取消并等待当前生成；不把“正在翻译”当成永久阻断条件。
        if let block = ModelSwitchGuard.blockReason(
            isGenerating: false, isLoading: loadingNow, apiRunning: false) {
            GTLog.info("model switch blocked: \(block)")
            return block
        }
        settings = AppSettings.update { $0.selectedModelID = id }
        self.selectedModelID = id
        GTLog.info("switching model to \(id)")
        // 停掉指向旧引擎的 API server；start() 会在新引擎就绪后按 apiEnabled 重启（指向新引擎）。
        // 不停的话 startServer 的 serverTask==nil 守卫会让 API 继续服务旧模型（潜在 bug）。
        if serverTask != nil {
            serverTask?.cancel()
            serverTask = nil
            apiStatus = .disabled
        }
        loadTask?.cancel()  // 先取消在飞加载，防止旧任务在 unload 后写入 self.engine
        await engine?.unload()
        start()             // start() 重读 settings 并按新 selectedModelID 解析（R1）
        return nil
    }

    /// 设置页「删除模型」入口：活跃中的模型禁删（避免删掉正在用的权重）。
    func deleteModel(id: String) {
        guard id != settings.selectedModelID else {
            GTLog.info("delete refused: \(id) is the active model")
            return
        }
        try? InstalledModels.delete(
            id: id,
            base: TranslationEngine.defaultModelBase(),
            legacyHuggingFaceHub: InstalledModels.defaultLegacyHuggingFaceHub
        )
        GTLog.info("deleted model \(id)")
    }

    /// 设置页展示用：扫描默认目录下已完整安装的 catalog 模型（带磁盘体积）。
    func installedModels() -> [InstalledModel] {
        InstalledModels.scan(
            base: TranslationEngine.defaultModelBase(),
            legacyHuggingFaceHub: InstalledModels.defaultLegacyHuggingFaceHub
        )
    }

    // MARK: - 后台下载（只下不切，与正在用的模型并存）

    private var downloadTask: Task<Void, Never>?
    /// 正在后台下载的模型 id；nil 表示当前无后台下载。供设置页显示进度/禁用其他下载。
    private(set) var downloadingModelID: String?
    private(set) var downloadProgress: DownloadProgress?
    private(set) var modelDownloadErrors: [String: String] = [:]

    /// 设置页「下载」入口：把某 catalog 模型下到磁盘，**不切换当前活跃引擎**。
    /// 与 switchModel 的区别：纯磁盘拉取，不动引擎，故可边用当前模型边下新模型。
    /// 一次只下一个（downloadTask 非空时忽略）；Hugging Face 不可用时自动回退 ModelScope。
    func downloadModel(id: String) {
        guard downloadTask == nil, let entry = ModelCatalog.entry(id: id) else { return }
        modelDownloadErrors[id] = nil
        downloadingModelID = id
        downloadProgress = DownloadProgress(fraction: 0)
        let base = TranslationEngine.defaultModelBase()
        GTLog.info("background download started: \(id)")
        downloadTask = Task {
            do {
                _ = try await ModelDownloader.download(entry: entry, into: base) { p in
                    Task { @MainActor in EngineController.shared.downloadProgress = p }
                }
                GTLog.info("background download done: \(id)")
                if self.selectedModelID == id {
                    self.start()
                }
            } catch {
                GTLog.error("background download failed \(id): \(error)")
                if let downloadError = error as? ModelDownloadError {
                    switch downloadError {
                    case .checksumMismatch, .sizeMismatch:
                        self.modelDownloadErrors[id] = "模型文件校验失败，请重试"
                    default:
                        self.modelDownloadErrors[id] = "模型下载失败，请重试"
                    }
                } else if !(error is CancellationError) {
                    self.modelDownloadErrors[id] = "模型下载失败，请重试"
                }
            }
            self.downloadingModelID = nil
            self.downloadProgress = nil
            self.downloadTask = nil
        }
    }

    /// 各模型最近一次翻译的速度（tok/s），按活跃模型 id 分别记录——不同模型速度不同，不能共用一个值。
    /// 由翻译完成的 ViewModel 通过 recordTokensPerSecond 回填，设置页按行读取。
    var lastTokensPerSecond: [String: Double] = [:]

    /// 把一次翻译的速度记到当前活跃模型名下。
    func recordTokensPerSecond(_ tps: Double?) {
        guard let tps, let selectedModelID else { return }
        lastTokensPerSecond[selectedModelID] = tps
    }

    /// 当前活跃模型的展示名。
    var activeModelName: String {
        if let selectedModelID, let entry = ModelCatalog.entry(id: selectedModelID) {
            return entry.displayName
        }
        return "未选择模型"
    }

    /// 菜单/设置开关入口：即时生效并持久化
    func setAPIEnabled(_ enabled: Bool) {
        settings = AppSettings.update { $0.apiEnabled = enabled }
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
