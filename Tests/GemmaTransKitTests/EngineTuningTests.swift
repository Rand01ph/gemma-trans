import Testing
@testable import GemmaTransKit

@Suite struct EngineTuningTests {
    let GB: UInt64 = 1 << 30
    let plenty: UInt64 = 100 << 30

    @Test func bigMachineGetsE4BLongInput() {
        let t = EngineTuning.recommended(physicalMemory: 48 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 4096, maxInputChars: 6000))
    }

    @Test func tier32GB() {
        let t = EngineTuning.recommended(physicalMemory: 32 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 3000))
    }

    @Test func tier16GB() {
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 1500))
    }

    @Test func smallMachineGetsE2B() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: plenty)
        #expect(t == EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700))
    }

    @Test func pressureDowngradesOneTier() {
        // 16GB 物理但仅 2GB 可用 < e4b 2.4GB + 2GB 余量 → 降到 e2b 档
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: 2 * GB)
        #expect(t.variant == .gemma4E2B4bit)
    }

    @Test func pressureDowngradeStopsAtFloor() {
        let t = EngineTuning.recommended(physicalMemory: 8 * GB, availableMemory: 1 * GB)
        #expect(t == EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700))
    }

    @Test func unknownAvailableMemoryDoesNotDowngrade() {
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: nil)
        #expect(t.variant == .gemma4E4B4bit)
    }
}
