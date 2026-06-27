import Testing
import Foundation
@testable import GemmaTransKit

@Suite struct ActiveModelResolverTests {
    // Auto：按内存选 Gemma，entry 与 recommended 的 variant 对应
    @Test func auto_picksGemmaByRAM_highMem() {
        let r = ActiveModelResolver.resolve(selectedID: "auto",
            physicalMemory: 64 << 30, availableMemory: 60 << 30)
        #expect(r.entry.id == "gemma-e4b-4bit")
        #expect(r.tuning.maxTokens == 4096) // 48GB+ 档
    }

    @Test func auto_lowMem_picksE2B() {
        let r = ActiveModelResolver.resolve(selectedID: "auto",
            physicalMemory: 8 << 30, availableMemory: 4 << 30)
        #expect(r.entry.id == "gemma-e2b-4bit")
    }

    // 显式选择：直接采用该 entry；tuning 用其默认参数
    @Test func explicit_usesEntryDefaults() {
        let r = ActiveModelResolver.resolve(selectedID: "hymt2-8bit",
            physicalMemory: 16 << 30, availableMemory: 10 << 30)
        #expect(r.entry.id == "hymt2-8bit")
        #expect(r.tuning.variant == .gemma4E2B4bit) // 见实现说明
        #expect(r.tuning.maxTokens == 1024)
        #expect(r.tuning.maxInputChars == 1500)
    }

    // 未知 id 回退 auto（防 settings 脏数据）
    @Test func unknownID_fallsBackToAuto() {
        let r = ActiveModelResolver.resolve(selectedID: "garbage",
            physicalMemory: 64 << 30, availableMemory: 60 << 30)
        #expect(r.entry.family == .gemma)
    }
}
