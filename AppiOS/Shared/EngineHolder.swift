import Foundation
import Observation
import GemmaTransKit

/// 进程级引擎单例：主 app 与扩展进程各自持有一份（进程隔离互不可见）。
/// 扩展进程存活期间复用热引擎——连续取词免冷载。
@MainActor @Observable
final class EngineHolder {
    enum Status: Equatable {
        case idle
        case downloading(Int)   // 百分比
        case loading            // 权重进显存 + 1-token 预热
        case ready
        case failed(String)
    }

    static let shared = EngineHolder()

    private(set) var status: Status = .idle
    private(set) var engine: TranslationEngine?
    private var loadTask: Task<Void, Never>?

    /// 启动路径：模型已下载才加载，绝不触发下载（真机反馈：启动即自动下 3.6GB 太粗暴）。
    /// 未下载时置 .idle，由 UI 呈现「下载模型」按钮等用户显式触发 download()。
    func loadIfDownloaded() {
        guard ModelStore.modelDownloaded else {
            if loadTask == nil { status = .idle }
            return
        }
        startLoad()
    }

    /// 用户显式触发：允许下载（首次会拉约 3.6GB 权重）
    func download() {
        startLoad()
    }

    /// 幂等：并发/重复调用只触发一次加载；失败后可再调重试
    private func startLoad() {
        guard loadTask == nil else { return }
        status = ModelStore.modelDownloaded ? .loading : .downloading(0)
        let settings = AppSettings.load(suiteName: ModelStore.settingsSuite)
        let engine = TranslationEngine(settings: settings)
        loadTask = Task {
            do {
                try await loadWithRetry(engine)
                self.engine = engine
                // 完成标记由 ModelDownloader 在全部文件校验通过后自行落盘，这里无需再标
                self.status = .ready
                GTLog.info("iOS engine ready")
            } catch {
                // 非网络错误或重试耗尽：UI 只放短句人话，完整错误进日志
                self.status = .failed(Self.failureMessage(for: error))
                self.loadTask = nil
                GTLog.error("iOS engine load failed: \(error)")
            }
        }
    }

    /// 网络类错误自动重试（真机现象：3.6GB 下载途中 NSURLError -1005「连接断开」）。
    /// ModelDownloader 以 .part 文件 + Range 头断点续传：重调 load 即从断点
    /// 继续，字节级进度回调含已落盘部分——故重试期间 status 保持原值，续传自会推进进度。
    private func loadWithRetry(_ engine: TranslationEngine) async throws {
        let backoffSeconds: [UInt64] = [2, 4, 8, 15, 15]  // 最多重试 5 次，退避 min 封顶 15s
        var attempt = 0
        while true {
            do {
                // spec 决策：iOS 固定 E2B-4bit 档，不走 autoTuning——16GB 的 M 系 iPad 上
                // EngineTuning.recommended 会选 E4B，与 ModelStore 固定的 E2B repo 名错位，
                // 扩展会永久误报「模型未下载」。该 variant 与 ModelStore.repo
                // 构成一对不变量（variant↔repo 名）：改其一必改其二。
                try await engine.load(
                    cacheDirectory: ModelStore.cacheDirectory,
                    modelSource: ModelStore.modelSource,
                    tuningOverride: EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700)
                ) { fraction in
                    Task { @MainActor in
                        let pct = Int(fraction * 100)
                        EngineHolder.shared.status = pct < 100 ? .downloading(pct) : .loading
                    }
                }
                return
            } catch {
                let nsError = error as NSError
                guard nsError.domain == NSURLErrorDomain, attempt < backoffSeconds.count else {
                    throw error
                }
                let delay = backoffSeconds[attempt]
                attempt += 1
                GTLog.info("iOS engine load network error (code \(nsError.code)), retry \(attempt)/\(backoffSeconds.count) in \(delay)s")
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }

    /// 失败信息人性化：网络错误给可行动的短句（保留 code 便于排查），其他错误截断防刷屏
    private static func failureMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络中断（已下载部分已保留，点重试继续）[\(nsError.code)]"
        }
        return String("加载失败：\(error)".prefix(120))
    }
}
