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
                try await engine.load(cacheDirectory: ModelStore.cacheDirectory) { fraction in
                    Task { @MainActor in
                        let pct = Int(fraction * 100)
                        EngineHolder.shared.status = pct < 100 ? .downloading(pct) : .loading
                    }
                }
                self.engine = engine
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
