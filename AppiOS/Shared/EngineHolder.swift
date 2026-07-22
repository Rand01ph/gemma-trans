import Foundation
import Observation
import GemmaTransKit

/// 进程级引擎单例：主 app 与扩展进程各自持有一份（进程隔离互不可见）。
/// 扩展进程存活期间复用热引擎——连续取词免冷载。
@MainActor @Observable
final class EngineHolder {
    enum FailureKind: Equatable {
        case download
        case load
    }

    enum Status: Equatable {
        case idle
        case downloading(DownloadProgress)  // 比例 + 已下/总字节（HF 宏路径字节为 nil）
        case loading            // 权重进显存 + 1-token 预热
        case ready
        case failed(String, FailureKind)
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

    /// 失败恢复：已下载完成时只重新加载模型，未完成时继续断点下载。
    func retry() {
        startLoad()
    }

    /// 幂等：并发/重复调用只触发一次加载；失败后可再调重试
    private func startLoad() {
        guard loadTask == nil else { return }
        status = ModelStore.modelDownloaded ? .loading : .downloading(DownloadProgress(fraction: 0))
        let settings = AppSettings.load(suiteName: ModelStore.settingsSuite)
        let engine = TranslationEngine(settings: settings)
        loadTask = Task {
            do {
                // 网络退避重试 + 断点续传：共享实现见 Kit EngineLoadSupport.swift
                try await withNetworkRetry {
                    // spec 决策：iOS 固定 E2B-4bit 档，不走 autoTuning——16GB 的 M 系 iPad 上
                    // EngineTuning.recommended 会选 E4B，与 ModelStore 固定的 E2B repo 名错位，
                    // 扩展会永久误报「模型未下载」。该 variant 与 ModelStore.repo
                    // 构成一对不变量（variant↔repo 名）：改其一必改其二。
                    try await engine.load(
                        cacheDirectory: ModelStore.cacheDirectory,
                        modelSource: ModelStore.modelSource,
                        tuningOverride: EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700)
                    ) { progress in
                        Task { @MainActor in
                            EngineHolder.shared.status =
                                progress.fraction < 1.0 ? .downloading(progress) : .loading
                        }
                    }
                }
                self.engine = engine
                // 完成标记由 ModelDownloader 在全部文件校验通过后自行落盘，这里无需再标
                self.status = .ready
                GTLog.info("iOS engine ready")
            } catch {
                // 非网络错误或重试耗尽：UI 只放短句人话（共享映射），完整错误进日志
                let failureKind: FailureKind = ModelStore.modelDownloaded ? .load : .download
                self.status = .failed(engineLoadFailureMessage(for: error), failureKind)
                self.loadTask = nil
                GTLog.error("iOS engine load failed: \(error)")
            }
        }
    }
}
