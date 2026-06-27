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
    private(set) var settings: AppSettings
    /// 在飞加载任务 + 代际号：reload 取消旧任务后，旧任务的迟到回调（进度/重试/失败）
    /// 凭代际号被丢弃，不会覆盖新任务刚置的状态
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    /// 当前选中的模型 ID（镜像 AppSettings.selectedModelID，供 Task 8 UI 绑定）
    private(set) var selectedModelID: String

    private init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.selectedModelID = loaded.selectedModelID
    }

    func start() {
        engineStatus = .loading("正在准备…")
        // 重读设置：重试前用户可能在设置页切了国内源开关，「下次下载生效」靠这里兑现
        // （apiEnabled 由 setAPIEnabled 即时落盘，重读不会回退用户操作）
        settings = AppSettings.load()
        // 镜像选中模型 ID：start() 是切换/重载后重新解析模型的统一入口，镜像在此对齐
        selectedModelID = settings.selectedModelID
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
            // settings 是 @MainActor 隔离属性，不能在下面 withNetworkRetry 的 @Sendable 闭包里访问。
            // 在此（MainActor 上下文）先取出选中档并解析，闭包只捕获 Sendable 值（source/resolved）。
            let selectedID = settings.selectedModelID
            let resolved: ResolvedModel? = selectedID == ModelCatalog.autoID
                ? nil
                : ActiveModelResolver.resolve(
                    selectedID: selectedID,
                    physicalMemory: SystemMemory.physical(),
                    availableMemory: SystemMemory.available())
            // 进度回调脚手架两分支共用：仅 engine.load(...) 那一行因选中模型不同而分流
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
                    // auto 档保持既有 load(modelSource:) 完全不变——存量 macOS 用户的 Gemma
                    // 在 legacy HF 缓存里，仅旧路径会复用它，强切新路径会让他们白下 GB 级权重。
                    // 显式选档走 load(resolved:)：按 catalog 条目下载/加载新快照。
                    if let resolved {
                        try await engine.load(
                            resolved: resolved, modelSource: source, progress: progressHandler)
                    } else {
                        try await engine.load(modelSource: source, progress: progressHandler)
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

    /// 设置页「切换模型」入口：守卫不过返回原因且不切；过则卸旧载新（必要时下载）。
    /// async 以便直接 await actor 的 isGenerating，避免镜像竞态。
    /// 注意：load(resolved:) 会在快照不完整时自动下载——切到未下载的 catalog 档即触发拉取，
    /// 不另建「只下不切」后台路径（已延后）。
    func switchModel(to id: String) async -> SwitchBlock? {
        let generating = await engine?.isGenerating ?? false
        let loadingNow: Bool = {
            if case .loading = engineStatus { return true }
            if case .downloading = engineStatus { return true }
            return false
        }()
        // 仅「API 监听中」不再阻断切换——否则默认开 API 时页面整页置灰无法操作。
        // 在飞的 API 翻译仍由 isGenerating 守住；切换会重启 server 指向新引擎（见下）。
        if let block = ModelSwitchGuard.blockReason(
            isGenerating: generating, isLoading: loadingNow, apiRunning: false) {
            GTLog.info("model switch blocked: \(block)")
            return block
        }
        settings.selectedModelID = id
        settings.save()
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
        let activeID = ActiveModelResolver.resolve(
            selectedID: settings.selectedModelID,
            physicalMemory: SystemMemory.physical(),
            availableMemory: SystemMemory.available()).entry.id
        guard id != activeID else {
            GTLog.info("delete refused: \(id) is the active model")
            return
        }
        try? InstalledModels.delete(id: id, base: TranslationEngine.defaultModelBase())
        GTLog.info("deleted model \(id)")
    }

    /// 设置页展示用：扫描默认目录下已完整安装的 catalog 模型（带磁盘体积）。
    func installedModels() -> [InstalledModel] {
        InstalledModels.scan(base: TranslationEngine.defaultModelBase())
    }

    // MARK: - 后台下载（只下不切，与正在用的模型并存）

    private var downloadTask: Task<Void, Never>?
    /// 正在后台下载的模型 id；nil 表示当前无后台下载。供设置页显示进度/禁用其他下载。
    private(set) var downloadingModelID: String?
    private(set) var downloadProgress: DownloadProgress?

    /// 设置页「下载」入口：把某 catalog 模型下到磁盘，**不切换当前活跃引擎**。
    /// 与 switchModel 的区别：纯磁盘拉取，不动引擎，故可边用当前模型边下新模型。
    /// 一次只下一个（downloadTask 非空时忽略）；无自动重试，失败后按钮复现可重点。
    func downloadModel(id: String) {
        guard downloadTask == nil, let entry = ModelCatalog.entry(id: id) else { return }
        downloadingModelID = id
        downloadProgress = DownloadProgress(fraction: 0)
        let source: ModelSource = settings.useCNSource ? .modelScope : .huggingFace
        let base = TranslationEngine.defaultModelBase()
        GTLog.info("background download started: \(id)")
        downloadTask = Task {
            do {
                _ = try await ModelDownloader.download(repo: entry.repo, from: source, into: base) { p in
                    Task { @MainActor in EngineController.shared.downloadProgress = p }
                }
                GTLog.info("background download done: \(id)")
            } catch {
                GTLog.error("background download failed \(id): \(error)")
            }
            self.downloadingModelID = nil
            self.downloadProgress = nil
            self.downloadTask = nil
        }
    }

    /// 当前活跃模型的展示名（就绪状态展示用）；Auto 解析到具体 Gemma 档并加前缀。
    var activeModelName: String {
        if let entry = ModelCatalog.entry(id: selectedModelID) {
            return entry.displayName
        }
        let resolved = ActiveModelResolver.resolve(
            selectedID: ModelCatalog.autoID,
            physicalMemory: SystemMemory.physical(),
            availableMemory: SystemMemory.available())
        return "Auto · \(resolved.entry.displayName)"
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
