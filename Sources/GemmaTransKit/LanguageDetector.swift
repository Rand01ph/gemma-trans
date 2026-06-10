import Foundation
import NaturalLanguage

public struct LanguagePlan: Sendable, Equatable {
    public let detected: String  // BCP-47，无法识别为 "und"
    public let target: String
}

public struct LanguageDetector: Sendable {
    public init() {}

    /// target 显式给定时优先；否则中文→targetForChinese，其余→targetDefault
    public func plan(for text: String, target: String? = nil, settings: AppSettings) -> LanguagePlan {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let detected = recognizer.dominantLanguage?.rawValue ?? "und"
        if let target { return LanguagePlan(detected: detected, target: target) }
        let isChinese = detected.hasPrefix("zh")
        return LanguagePlan(
            detected: detected,
            target: isChinese ? settings.targetForChinese : settings.targetDefault
        )
    }
}
