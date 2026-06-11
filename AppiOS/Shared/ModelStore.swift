import Foundation

/// 主 app 与翻译扩展共享的存储约定（App Group）
enum ModelStore {
    static let appGroupID = "group.com.gemmatrans"
    /// 共享 UserDefaults suite（设置同步）
    static let settingsSuite = appGroupID

    /// 模型缓存目录（传给引擎 cacheDirectory），两进程同读
    static var cacheDirectory: URL {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("App Group \(appGroupID) 未配置")  // entitlements 缺失属构建配置错误，fail fast
        }
        return container.appendingPathComponent("models", isDirectory: true)
    }

    /// 下载完成标记文件。目录存在 ≠ 下载完整：主 app 下载中途被杀时
    /// HubCache 的 models--… 目录已在盘上，仅凭目录判断会把半成品当成可加载。
    /// 标记由引擎加载成功后落盘（EngineHolder 成功路径调 markModelComplete）。
    /// 文件名含 e2b——与 EngineHolder 固定的 E2B variant 构成一对不变量，改其一必改其二。
    static var completionMarker: URL {
        cacheDirectory.appendingPathComponent(".e2b-download-complete")
    }

    /// 引擎加载成功后调用：模型确认完整才落标记
    static func markModelComplete() {
        try? Data().write(to: completionMarker)
    }

    /// 模型是否已下载完成（判完成标记，而非目录是否存在）。
    /// 扩展据此决定「直接加载」还是提示「先打开主 app 下载」——
    /// 「扩展内绝不触发 1.4GB 下载」的不变量靠这个标记保证。
    static var modelDownloaded: Bool {
        FileManager.default.fileExists(atPath: completionMarker.path)
    }
}
