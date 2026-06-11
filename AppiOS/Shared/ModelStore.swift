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

    /// 模型是否已下载完成。目录布局由 swift-huggingface HubCache 决定：
    /// <cacheDirectory>/models--mlx-community--gemma-4-e2b-it-4bit/
    /// 扩展据此决定「直接加载」还是提示「先打开主 app 下载」——扩展内绝不触发 1.4GB 下载。
    static var modelDownloaded: Bool {
        let dir = cacheDirectory.appendingPathComponent("models--mlx-community--gemma-4-e2b-it-4bit")
        return FileManager.default.fileExists(atPath: dir.path)
    }
}
