import Foundation

public enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// 全局配置。CLI 与 App 共用，UserDefaults 持久化（App 修改，CLI 读取）。
public struct AppSettings: Sendable {
    public static let defaultTranslationFontSize = 13.0
    public static let minimumTranslationFontSize = 12.0
    public static let maximumTranslationFontSize = 18.0

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
    /// 模型下载走国内源（ModelScope）。国内网络 HF 的 Xet CDN 不可达、hf-mirror 已失效。
    /// key 与 iOS 共享 defaults 的同名开关一致（ModelStore.sourceKey / ContentView @AppStorage）。
    public var useCNSource: Bool
    /// 活跃模型选择。nil 表示尚未由用户选择；非 nil 必须是 ModelCatalog 条目 id。
    public var selectedModelID: String?
    /// macOS 外观：默认跟随系统；CLI/iOS 可忽略该字段。
    public var appearance: AppAppearance
    /// macOS 翻译浮窗译文字号；其他平台可忽略该字段。
    public var translationFontSize: Double

    public static let suiteName = "com.gemmatrans.app"

    public init(
        port: UInt16 = 8765,
        targetForChinese: String = "en",
        targetDefault: String = "zh-Hans",
        maxInputChars: Int = 1500,
        autoTuning: Bool = true,
        manualMaxTokens: Int = 2048,
        apiEnabled: Bool = true,
        useCNSource: Bool = false,
        selectedModelID: String? = nil,
        appearance: AppAppearance = .system,
        translationFontSize: Double = Self.defaultTranslationFontSize
    ) {
        self.port = port
        self.targetForChinese = targetForChinese
        self.targetDefault = targetDefault
        self.maxInputChars = maxInputChars
        self.autoTuning = autoTuning
        self.manualMaxTokens = manualMaxTokens
        self.apiEnabled = apiEnabled
        self.useCNSource = useCNSource
        self.selectedModelID = selectedModelID
        self.appearance = appearance
        self.translationFontSize = Self.normalizedTranslationFontSize(translationFontSize)
    }

    /// 从 UserDefaults 读取（缺省值兜底）。iOS 传 App Group suite 实现主 app/扩展共享。
    public static func load(suiteName: String = Self.suiteName) -> AppSettings {
        guard let d = UserDefaults(suiteName: suiteName) else { return AppSettings() }
        var s = AppSettings()
        if d.integer(forKey: "port") > 0 { s.port = UInt16(d.integer(forKey: "port")) }
        if let v = d.string(forKey: "targetForChinese"), !v.isEmpty { s.targetForChinese = v }
        if let v = d.string(forKey: "targetDefault"), !v.isEmpty { s.targetDefault = v }
        if d.object(forKey: "autoTuning") != nil { s.autoTuning = d.bool(forKey: "autoTuning") }
        if d.integer(forKey: "manualMaxTokens") > 0 { s.manualMaxTokens = d.integer(forKey: "manualMaxTokens") }
        if d.integer(forKey: "maxInputChars") > 0 { s.maxInputChars = d.integer(forKey: "maxInputChars") }
        if d.object(forKey: "apiEnabled") != nil { s.apiEnabled = d.bool(forKey: "apiEnabled") }
        if d.object(forKey: "useCNSource") != nil { s.useCNSource = d.bool(forKey: "useCNSource") }
        // `auto` 是旧版值。升级后把它和其他未知值视为未选择，避免启动时隐式下载。
        if let v = d.string(forKey: "selectedModelID"), ModelCatalog.entry(id: v) != nil {
            s.selectedModelID = v
        }
        if let v = d.string(forKey: "appearance"), let appearance = AppAppearance(rawValue: v) {
            s.appearance = appearance
        }
        if d.object(forKey: "translationFontSize") != nil {
            s.translationFontSize = Self.normalizedTranslationFontSize(
                d.double(forKey: "translationFontSize")
            )
        }
        return s
    }

    public func save(suiteName: String = Self.suiteName) {
        guard let d = UserDefaults(suiteName: suiteName) else { return }
        d.set(Int(port), forKey: "port")
        d.set(targetForChinese, forKey: "targetForChinese")
        d.set(targetDefault, forKey: "targetDefault")
        d.set(autoTuning, forKey: "autoTuning")
        d.set(manualMaxTokens, forKey: "manualMaxTokens")
        d.set(maxInputChars, forKey: "maxInputChars")
        d.set(apiEnabled, forKey: "apiEnabled")
        d.set(useCNSource, forKey: "useCNSource")
        if let selectedModelID {
            d.set(selectedModelID, forKey: "selectedModelID")
        } else {
            d.removeObject(forKey: "selectedModelID")
        }
        d.set(appearance.rawValue, forKey: "appearance")
        d.set(Self.normalizedTranslationFontSize(translationFontSize),
              forKey: "translationFontSize")
    }

    public static func normalizedTranslationFontSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTranslationFontSize }
        return min(max(value, minimumTranslationFontSize), maximumTranslationFontSize)
    }
}
