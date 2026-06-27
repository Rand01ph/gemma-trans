import Testing
@testable import GemmaTransKit

@Suite struct ProcessPresetsTests {

    // MARK: - 表完整性

    @Test func allContainsTwoBuiltins() {
        #expect(ProcessPresets.all.count == 2)
    }

    @Test func allContainsCourierPickup() {
        #expect(ProcessPresets.all.contains(ProcessPresets.courierPickup))
    }

    @Test func allContainsSummarize() {
        #expect(ProcessPresets.all.contains(ProcessPresets.summarize))
    }

    // MARK: - id 稳定

    @Test func courierPickupIdIsStable() {
        #expect(ProcessPresets.courierPickup.id == "builtin.courier")
    }

    @Test func summarizeIdIsStable() {
        #expect(ProcessPresets.summarize.id == "builtin.summarize")
    }

    @Test func allIdsAreUnique() {
        let ids = ProcessPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - courierPickup 指令含输出契约关键词

    @Test func courierPickupInstructionContainsFormat() {
        let instr = ProcessPresets.courierPickup.instruction
        // 输出契约关键词：取件、地点、取件码、时限
        #expect(instr.contains("取件"))
        #expect(instr.contains("取件码"))
        #expect(instr.contains("时限"))
    }

    @Test func courierPickupInstructionContainsNonCourierFallback() {
        // 非快递短信输出「无」
        let instr = ProcessPresets.courierPickup.instruction
        #expect(instr.contains("无"))
    }

    @Test func courierPickupInstructionMentionsSkipMissingFields() {
        // 缺项跳过
        let instr = ProcessPresets.courierPickup.instruction
        #expect(instr.contains("跳过"))
    }

    @Test func courierPickupInstructionOutputSingleLine() {
        // 单行输出约定
        let instr = ProcessPresets.courierPickup.instruction
        #expect(instr.contains("单行") || instr.contains("一行"))
    }

    // MARK: - summarize 指令含输出契约关键词

    @Test func summarizeInstructionContainsThreeSentences() {
        let instr = ProcessPresets.summarize.instruction
        #expect(instr.contains("三句"))
    }

    @Test func summarizeInstructionNoPrefixRequirement() {
        // 无前缀要求
        let instr = ProcessPresets.summarize.instruction
        #expect(instr.contains("前缀") || instr.contains("编号") || instr.contains("引号"))
    }

    // MARK: - 名称非空

    @Test func allPresetsHaveNonEmptyName() {
        for preset in ProcessPresets.all {
            #expect(!preset.name.isEmpty)
        }
    }

    @Test func allPresetsHaveNonEmptyInstruction() {
        for preset in ProcessPresets.all {
            #expect(!preset.instruction.isEmpty)
        }
    }
}
