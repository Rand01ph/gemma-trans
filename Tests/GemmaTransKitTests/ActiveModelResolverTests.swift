import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct ActiveModelResolverTests {
    // 显式选择：直接采用该 entry；tuning 用其默认参数
    @Test func explicit_usesEntryDefaults() {
        let r = ActiveModelResolver.resolve(selectedID: "hymt2-8bit")
        #expect(r?.entry.id == "hymt2-8bit")
        #expect(r?.tuning.variant == .gemma4E2B4bit) // 见实现说明
        #expect(r?.tuning.maxTokens == 1024)
        #expect(r?.tuning.maxInputChars == 1500)
    }

    @Test func autoAndUnknownIDsDoNotResolve() {
        #expect(ActiveModelResolver.resolve(selectedID: "auto") == nil)
        #expect(ActiveModelResolver.resolve(selectedID: "garbage") == nil)
    }

    @Test func manualParameterLimitsDoNotChangeSelectedModel() {
        var settings = AppSettings()
        settings.autoTuning = false
        settings.manualMaxTokens = 333
        settings.maxInputChars = 444

        let resolved = ActiveModelResolver.resolve(
            selectedID: "gemma-e2b-4bit", parameterSettings: settings)
        #expect(resolved?.entry.id == "gemma-e2b-4bit")
        #expect(resolved?.tuning.maxTokens == 333)
        #expect(resolved?.tuning.maxInputChars == 444)
    }
}
