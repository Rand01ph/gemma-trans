import Foundation

/// Local channels are fixed identities, independent of branch names and version numbers.
public enum AppChannel: String, Sendable, CaseIterable {
    case production, qa, dev, uitest

    public static var current: AppChannel {
        AppChannel(rawValue: Bundle.main.object(forInfoDictionaryKey: "GTChannel") as? String ?? "") ?? .production
    }
    public var displayName: String {
        switch self {
        case .production: "GemmaTrans"
        case .qa: "GemmaTrans QA"
        case .dev: "GemmaTrans Dev"
        case .uitest: "GemmaTrans UITest"
        }
    }
    public var settingsSuite: String {
        self == .production ? "com.gemmatrans.app" : "com.gemmatrans.app.\(rawValue)"
    }
    public var defaultPort: UInt16 {
        switch self {
        case .production: 8765
        case .qa: 18765
        case .dev: 28765
        case .uitest: 38765
        }
    }
}
