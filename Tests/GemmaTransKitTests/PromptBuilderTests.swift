import Testing
@testable import GemmaTransKit

@Suite struct PromptBuilderTests {
    @Test func promptContainsTextAndTargetName() {
        let p = PromptBuilder.userPrompt(text: "Hello world", target: "zh-Hans")
        #expect(p.contains("Hello world"))
        #expect(p.contains("Simplified Chinese"))
    }

    @Test func systemPromptForbidsExplanation() {
        let s = PromptBuilder.systemPrompt
        #expect(s.contains("only"))
    }

    @Test func unknownBCP47FallsBackToRawCode() {
        let p = PromptBuilder.userPrompt(text: "Hi", target: "xx-weird")
        #expect(p.contains("xx-weird"))
    }
}
