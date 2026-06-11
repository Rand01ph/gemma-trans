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

    /// 幂等：并发/重复调用只触发一次加载；失败后可再调重试
    func ensureLoaded() {
        guard loadTask == nil else { return }
        status = ModelStore.modelDownloaded ? .loading : .downloading(0)
        let settings = AppSettings.load(suiteName: ModelStore.settingsSuite)
        let engine = TranslationEngine(settings: settings)
        loadTask = Task {
            do {
                // spec 决策：iOS 固定 E2B-4bit 档，不走 autoTuning——16GB 的 M 系 iPad 上
                // EngineTuning.recommended 会选 E4B，与 ModelStore 硬编码的 e2b 目录名错位，
                // 扩展会永久误报「模型未下载」。该 variant 与 ModelStore.modelDownloaded 的
                // 目录名/标记构成一对不变量：改其一必改其二。
                try await engine.load(
                    cacheDirectory: ModelStore.cacheDirectory,
                    tuningOverride: EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700)
                ) { fraction in
                    Task { @MainActor in
                        let pct = Int(fraction * 100)
                        EngineHolder.shared.status = pct < 100 ? .downloading(pct) : .loading
                    }
                }
                self.engine = engine
                // 引擎加载成功 ⇒ 模型文件确认完整，落盘标记供扩展判定「已下载」
                ModelStore.markModelComplete()
                self.status = .ready
                GTLog.info("iOS engine ready")
            } catch {
                self.status = .failed("\(error)")
                self.loadTask = nil
                GTLog.error("iOS engine load failed: \(error)")
            }
        }
    }
}
