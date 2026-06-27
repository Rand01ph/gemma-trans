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

    // MARK: - 翻译面板接力（扩展写、主 app 读）

    /// 扩展把选中文字写入共享 defaults（文本 + 时间戳），主 app 启动/前台即消费。
    /// deep link 之外的冗余通道：扩展进程不能保证 deep link 必达，App Group 是兜底。
    static let handoffTextKey = "pendingHandoffText"
    static let handoffDateKey = "pendingHandoffDate"

    /// 扩展侧：写入待翻译文本与当前时间戳
    static func writeHandoff(_ text: String) {
        guard let d = UserDefaults(suiteName: settingsSuite) else { return }
        d.set(text, forKey: handoffTextKey)
        d.set(Date().timeIntervalSince1970, forKey: handoffDateKey)
    }

    /// 主 app 侧：取出并清除接力文本；超过 maxAge（默认 60s）的陈旧文本丢弃返回 nil
    static func consumeHandoff(maxAge: TimeInterval = 60) -> String? {
        guard let d = UserDefaults(suiteName: settingsSuite),
              let text = d.string(forKey: handoffTextKey), !text.isEmpty else { return nil }
        let ts = d.double(forKey: handoffDateKey)
        d.removeObject(forKey: handoffTextKey)
        d.removeObject(forKey: handoffDateKey)
        guard ts > 0, Date().timeIntervalSince1970 - ts <= maxAge else { return nil }
        return text
    }
}
