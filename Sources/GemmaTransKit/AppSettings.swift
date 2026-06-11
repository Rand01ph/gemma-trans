import Foundation

/// 全局配置。CLI 与 App 共用，UserDefaults 持久化（App 修改，CLI 读取）。
public struct AppSettings: Sendable {
    public var port: UInt16
    /// 检测为中文时的目标语言
    public var targetForChinese: String
    /// 其他语言的目标语言
    public var targetDefault: String
    /// 手动模式输入上限（自动调优时由 EngineTuning 决定）
    public var maxInputChars: Int
    /// 按机器内存自动推导引擎参数（EngineTuning）；关闭后用 manualMaxTokens + maxInputChars
    public var autoTuning: Bool
    public var manualMaxTokens: Int
    /// 本地 HTTP API（PopClip 等外部工具用）；划词翻译是进程内调用，不受此开关影响
    public var apiEnabled: Bool

    public static let suiteName = "com.gemmatrans.app"

    public init(
        port: UInt16 = 8765,
        targetForChinese: String = "en",
        targetDefault: String = "zh-Hans",
        maxInputChars: Int = 1500,
        autoTuning: Bool = true,
        manualMaxTokens: Int = 2048,
        apiEnabled: Bool = true
    ) {
        self.port = port
        self.targetForChinese = targetForChinese
        self.targetDefault = targetDefault
        self.maxInputChars = maxInputChars
        self.autoTuning = autoTuning
        self.manualMaxTokens = manualMaxTokens
        self.apiEnabled = apiEnabled
    }

    /// 从 UserDefaults 读取（缺省值兜底）
    public static func load() -> AppSettings {
        guard let d = UserDefaults(suiteName: suiteName) else { return AppSettings() }
        var s = AppSettings()
        if d.integer(forKey: "port") > 0 { s.port = UInt16(d.integer(forKey: "port")) }
        if let v = d.string(forKey: "targetForChinese"), !v.isEmpty { s.targetForChinese = v }
        if let v = d.string(forKey: "targetDefault"), !v.isEmpty { s.targetDefault = v }
        if d.object(forKey: "autoTuning") != nil { s.autoTuning = d.bool(forKey: "autoTuning") }
        if d.integer(forKey: "manualMaxTokens") > 0 { s.manualMaxTokens = d.integer(forKey: "manualMaxTokens") }
        if d.integer(forKey: "maxInputChars") > 0 { s.maxInputChars = d.integer(forKey: "maxInputChars") }
        if d.object(forKey: "apiEnabled") != nil { s.apiEnabled = d.bool(forKey: "apiEnabled") }
        return s
    }

    public func save() {
        guard let d = UserDefaults(suiteName: Self.suiteName) else { return }
        d.set(Int(port), forKey: "port")
        d.set(targetForChinese, forKey: "targetForChinese")
        d.set(targetDefault, forKey: "targetDefault")
        d.set(autoTuning, forKey: "autoTuning")
        d.set(manualMaxTokens, forKey: "manualMaxTokens")
        d.set(maxInputChars, forKey: "maxInputChars")
        d.set(apiEnabled, forKey: "apiEnabled")
    }
}
