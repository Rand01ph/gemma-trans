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
    /// 按机器内存自动推导引擎参数（EngineTuning）；关闭后用 manualMaxNumTokens + maxInputChars
    public var autoTuning: Bool
    public var manualMaxNumTokens: Int
    /// 本地 HTTP API（PopClip 等外部工具用）；划词翻译是进程内调用，不受此开关影响
    public var apiEnabled: Bool
    /// 自选模型文件的 security-scoped bookmark（sandbox 下 NSOpenPanel 授权重启失效，靠它恢复）
    public var modelBookmark: Data?

    public static let defaultModelDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GemmaTrans/models", isDirectory: true)

    public static let suiteName = "com.gemmatrans.app"

    public init(
        modelPath: String = defaultModelDirectory.appendingPathComponent("gemma-4-E4B-it.litertlm").path,
        port: UInt16 = 8765,
        targetForChinese: String = "en",
        targetDefault: String = "zh-Hans",
        maxInputChars: Int = 1500,  // 手动模式用；1500 CJK 字符 ≈ 1000-1200 token，配 KV 2048 留足输出
        autoTuning: Bool = true,
        manualMaxNumTokens: Int = 2048,
        apiEnabled: Bool = true,
        modelBookmark: Data? = nil
    ) {
        self.modelPath = modelPath
        self.port = port
        self.targetForChinese = targetForChinese
        self.targetDefault = targetDefault
        self.maxInputChars = maxInputChars
        self.autoTuning = autoTuning
        self.manualMaxNumTokens = manualMaxNumTokens
        self.apiEnabled = apiEnabled
        self.modelBookmark = modelBookmark
    }

    /// 从 UserDefaults 读取（缺省值兜底）
    public static func load() -> AppSettings {
        guard let d = UserDefaults(suiteName: suiteName) else { return AppSettings() }
        var s = AppSettings()
        if let v = d.string(forKey: "modelPath"), !v.isEmpty { s.modelPath = v }
        if d.integer(forKey: "port") > 0 { s.port = UInt16(d.integer(forKey: "port")) }
        if let v = d.string(forKey: "targetForChinese"), !v.isEmpty { s.targetForChinese = v }
        if let v = d.string(forKey: "targetDefault"), !v.isEmpty { s.targetDefault = v }
        if d.object(forKey: "autoTuning") != nil { s.autoTuning = d.bool(forKey: "autoTuning") }
        if d.integer(forKey: "manualMaxNumTokens") > 0 { s.manualMaxNumTokens = d.integer(forKey: "manualMaxNumTokens") }
        if d.integer(forKey: "maxInputChars") > 0 { s.maxInputChars = d.integer(forKey: "maxInputChars") }
        if d.object(forKey: "apiEnabled") != nil { s.apiEnabled = d.bool(forKey: "apiEnabled") }
        s.modelBookmark = d.data(forKey: "modelBookmark")
        return s
    }

    public func save() {
        guard let d = UserDefaults(suiteName: Self.suiteName) else { return }
        d.set(modelPath, forKey: "modelPath")
        d.set(Int(port), forKey: "port")
        d.set(targetForChinese, forKey: "targetForChinese")
        d.set(targetDefault, forKey: "targetDefault")
        d.set(autoTuning, forKey: "autoTuning")
        d.set(manualMaxNumTokens, forKey: "manualMaxNumTokens")
        d.set(maxInputChars, forKey: "maxInputChars")
        d.set(apiEnabled, forKey: "apiEnabled")
        d.set(modelBookmark, forKey: "modelBookmark")
    }
}
