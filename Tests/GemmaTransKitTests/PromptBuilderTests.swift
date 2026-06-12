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

    // MARK: - Process path

    @Test func processSystemPromptContainsEngine() {
        let s = PromptBuilder.processSystemPrompt
        #expect(s.contains("text processing engine"))
    }

    @Test func processSystemPromptRequiresFollowInstruction() {
        let s = PromptBuilder.processSystemPrompt
        #expect(s.contains("Follow the instruction exactly"))
    }

    @Test func processSystemPromptOutputOnlyResult() {
        let s = PromptBuilder.processSystemPrompt
        #expect(s.contains("Output only the result"))
    }

    @Test func processUserPromptContainsInstructionAndText() {
        let p = PromptBuilder.processUserPrompt(text: "取件码8821", instruction: "提取取件信息")
        #expect(p.contains("提取取件信息"))
        #expect(p.contains("取件码8821"))
    }

    @Test func processUserPromptOrderIsInstructionThenText() {
        let p = PromptBuilder.processUserPrompt(text: "正文", instruction: "指令")
        let instrRange = p.range(of: "指令")!
        let textRange = p.range(of: "正文")!
        #expect(instrRange.lowerBound < textRange.lowerBound)
    }

    @Test func processUserPromptSeparatedByBlankLine() {
        let p = PromptBuilder.processUserPrompt(text: "文本", instruction: "指令")
        // format: "<instruction>\n\n<text>"
        #expect(p.contains("\n\n"))
    }
}
