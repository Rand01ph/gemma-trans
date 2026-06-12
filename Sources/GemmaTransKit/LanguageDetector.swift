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
        var detected = recognizer.dominantLanguage?.rawValue ?? "und"
        let topConfidence = recognizer.dominantLanguage
            .map { recognizer.languageHypotheses(withMaximum: 1)[$0] ?? 0 } ?? 0
        // NLLanguageRecognizer 对夹杂较多英文术语的中文句子常误判为 en；
        // 汉字占比足够高时强制按中文处理（0.3：技术讨论里术语过半也能纠正，纯英文偶带词不误伤）。
        // 含假名则视为日语，不覆盖——日语句子必有假名，汉字再多也轮不到这条规则。
        if !detected.hasPrefix("zh"), !containsKana(text), hanRatio(of: text) >= 0.3 {
            detected = "zh-Hans"
        } else if detected != "und", !detected.hasPrefix("zh"), !containsKana(text),
                  text.trimmingCharacters(in: .whitespacesAndNewlines).count < 12 || topConfidence < 0.45 {
            // 短文本/低置信的拉丁文本误判纠偏：NLLanguageRecognizer 对孤立英文词（如 "Dust"）
            // 置信度低，常判成荷兰语/德语，给出刺眼的错误语向标签。产品以中英双向为主，
            // 这类文本统一归 en——target 本就一致（非中文→targetDefault），只是标签不再出错。
            detected = "en"
        }
        if let target { return LanguagePlan(detected: detected, target: target) }
        let isChinese = detected.hasPrefix("zh")
        return LanguagePlan(
            detected: detected,
            target: isChinese ? settings.targetForChinese : settings.targetDefault
        )
    }

    private func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    private func hanRatio(of text: String) -> Double {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return 0 }
        let han = scalars.count { $0.properties.isIdeographic }
        return Double(han) / Double(scalars.count)
    }
}
