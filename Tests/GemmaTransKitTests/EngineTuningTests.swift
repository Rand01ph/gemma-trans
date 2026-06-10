import Testing
@testable import GemmaTransKit

@Suite struct EngineTuningTests {
    let GB: UInt64 = 1 << 30
    let model: UInt64 = 4 << 30  // 4GB 模型
    let plenty: UInt64 = 100 << 30

    @Test func tier48GB() {
        let t = EngineTuning.recommended(physicalMemory: 48 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 8192, maxInputChars: 6000))
    }

    @Test func tier32GB() {
        let t = EngineTuning.recommended(physicalMemory: 32 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 4096, maxInputChars: 3000))
    }

    @Test func tierJustBelow32GBFallsTo16Tier() {
        let t = EngineTuning.recommended(physicalMemory: 31 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 2048, maxInputChars: 1500))
    }

    @Test func tier16GB() {
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 2048, maxInputChars: 1500))
    }

    @Test func tierBelow16GB() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: plenty, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 1024, maxInputChars: 700))
    }

    @Test func pressureDowngradesOneTier() {
        // 16GB 物理但只剩 2GB 可用 < 4GB 模型 + 4GB 余量 → 降到最低档
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: 2 * GB, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 1024, maxInputChars: 700))
    }

    @Test func pressureDowngradeStopsAtFloor() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: 1 * GB, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 1024, maxInputChars: 700))
    }

    @Test func unknownAvailableMemoryDoesNotDowngrade() {
        // 读取失败（nil）→ 退化为纯静态分档
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: nil, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 2048, maxInputChars: 1500))
    }

    @Test func bigMachineUnderPressureDropsOneTierOnly() {
        let t = EngineTuning.recommended(physicalMemory: 64 * GB, availableMemory: 2 * GB, modelFileSize: model)
        #expect(t == EngineTuning(maxNumTokens: 4096, maxInputChars: 3000))
    }
}
