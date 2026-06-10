import Foundation

/// 全局配置。CLI 与 App 共用，UserDefaults 持久化（App 修改，CLI 读取）。
public struct AppSettings: Sendable {
    public var modelPath: String
    public var port: UInt16
    /// 检测为中文时的目标语言
    public var targetForChinese: String
    /// 其他语言的目标语言
    public var targetDefault: String
    public var maxInputChars: Int

    public static let defaultModelDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GemmaTrans/models", isDirectory: true)

    public static let suiteName = "com.gemmatrans.app"

    public init(
        modelPath: String = defaultModelDirectory.appendingPathComponent("gemma-4-E4B-it.litertlm").path,
        port: UInt16 = 8765,
        targetForChinese: String = "en",
        targetDefault: String = "zh-Hans",
        maxInputChars: Int = 4000
    ) {
        self.modelPath = modelPath
        self.port = port
        self.targetForChinese = targetForChinese
        self.targetDefault = targetDefault
        self.maxInputChars = maxInputChars
    }

    /// 从 UserDefaults 读取（缺省值兜底）
    public static func load() -> AppSettings {
        guard let d = UserDefaults(suiteName: suiteName) else { return AppSettings() }
        var s = AppSettings()
        if let v = d.string(forKey: "modelPath"), !v.isEmpty { s.modelPath = v }
        if d.integer(forKey: "port") > 0 { s.port = UInt16(d.integer(forKey: "port")) }
        if let v = d.string(forKey: "targetForChinese"), !v.isEmpty { s.targetForChinese = v }
        if let v = d.string(forKey: "targetDefault"), !v.isEmpty { s.targetDefault = v }
        return s
    }

    public func save() {
        guard let d = UserDefaults(suiteName: Self.suiteName) else { return }
        d.set(modelPath, forKey: "modelPath")
        d.set(Int(port), forKey: "port")
        d.set(targetForChinese, forKey: "targetForChinese")
        d.set(targetDefault, forKey: "targetDefault")
    }
}
