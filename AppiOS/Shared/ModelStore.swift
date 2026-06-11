import Foundation
import GemmaTransKit

/// 主 app 与翻译扩展共享的存储约定（App Group）
enum ModelStore {
    static let appGroupID = "group.com.gemmatrans"
    /// 共享 UserDefaults suite（设置同步）
    static let settingsSuite = appGroupID

    /// iOS 固定下载 E2B 仓库——与 EngineHolder 固定的 E2B variant 构成一对不变量
    /// （variant↔repo 名），改其一必改其二。
    static let repo = "mlx-community/gemma-4-e2b-it-4bit"

    /// 模型缓存目录（传给引擎 cacheDirectory），两进程同读
    static var cacheDirectory: URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) 未配置")  // entitlements 缺失属构建配置错误，fail fast
        }
        return container.appendingPathComponent("models", isDirectory: true)
    }

    /// 模型是否已下载完成。判定交给 ModelDownloader 的完成标记（含逐文件字节数校验）：
    /// 目录存在 ≠ 下载完整——主 app 下载中途被杀的半成品没有标记，字节数被外力破坏也判不完整。
    /// 扩展据此决定「直接加载」还是提示「先打开主 app 下载」——
    /// 「扩展内绝不触发 3.6GB 下载」的不变量靠这个标记保证。
    static var modelDownloaded: Bool {
        ModelDownloader.isComplete(
            ModelDownloader.snapshotDirectory(in: cacheDirectory, repo: repo))
    }

    /// 国内源开关（共享 defaults，主 app 写、引擎加载读）。
    /// HF Xet CDN 国内不可达、hf-mirror.com 已失效，国内网络走 ModelScope（魔搭）。
    static let sourceKey = "useCNSource"
    static var modelSource: ModelSource {
        UserDefaults(suiteName: settingsSuite)?.bool(forKey: sourceKey) == true
            ? .modelScope : .huggingFace
    }
}
