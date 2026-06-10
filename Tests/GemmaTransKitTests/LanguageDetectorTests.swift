import Testing
@testable import GemmaTransKit

@Suite struct LanguageDetectorTests {
    let settings = AppSettings()  // targetForChinese=en, targetDefault=zh-Hans
    let detector = LanguageDetector()

    @Test func englishGoesToChinese() {
        let r = detector.plan(for: "The quick brown fox jumps over the lazy dog.", settings: settings)
        #expect(r.detected == "en")
        #expect(r.target == "zh-Hans")
    }

    @Test func chineseGoesToEnglish() {
        let r = detector.plan(for: "今天天气真不错，我们去公园散步吧。", settings: settings)
        #expect(r.detected.hasPrefix("zh"))
        #expect(r.target == "en")
    }

    @Test func japaneseGoesToChinese() {
        let r = detector.plan(for: "今日はいい天気ですね。公園へ散歩に行きましょう。", settings: settings)
        #expect(r.detected == "ja")
        #expect(r.target == "zh-Hans")
    }

    @Test func explicitTargetWins() {
        let r = detector.plan(for: "Hello world, nice to meet you.", target: "fr", settings: settings)
        #expect(r.target == "fr")
    }

    @Test func emptyTextFallsBackToDefault() {
        let r = detector.plan(for: "", settings: settings)
        #expect(r.detected == "und")
        #expect(r.target == "zh-Hans")
    }
}
