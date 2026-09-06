import Testing
@testable import GemmaTransKit

struct TranslationPromptTests {
    @Test func defaultProviderKeepsTheExistingModelTemplates() {
        for family in [ModelFamily.gemma, .hunyuanMT2] {
            let request = TranslationPromptRequest(text: "Hello", detected: "en", target: "zh-Hans", family: family)
            #expect(request.defaultPrompt.user == PromptBuilder.userPrompt(text: "Hello", target: "zh-Hans"))
            #expect(request.defaultPrompt.system == (family == .gemma ? PromptBuilder.systemPrompt : nil))
        }
    }
    @Test func contextBudgetIncludesOutputAndAcceptsExactBoundary() throws {
        try TranslationPromptBudget.validate(inputTokens: 3072, outputTokens: 1024, contextTokens: 4096)
        #expect(throws: TranslationError.self) {
            try TranslationPromptBudget.validate(inputTokens: 3073, outputTokens: 1024, contextTokens: 4096)
        }
        #expect(throws: TranslationError.self) {
            try TranslationPromptBudget.validate(inputTokens: Int.max, outputTokens: 1024, contextTokens: 4096)
        }
    }
}
