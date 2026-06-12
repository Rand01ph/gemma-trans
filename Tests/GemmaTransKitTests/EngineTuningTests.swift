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
        // 16GB 物理但仅 3GB 可用 < e4b 4.9GB + 2GB 余量 → 降到 e2b 档（真机现场的触发条件）
        let t = EngineTuning.recommended(physicalMemory: 16 * GB, availableMemory: 3 * GB)
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

    /// iOS 设备档位：A17 Pro+ iPhone 为 8GB RAM，必须命中 E2B/1024/700（iOS spec 依赖此行为）
    @Test func iPhone8GBHitsE2BTier() {
        let t = EngineTuning.recommended(physicalMemory: 8 << 30, availableMemory: nil)
        #expect(t.variant == .gemma4E2B4bit)
        #expect(t.maxTokens == 1024)
        #expect(t.maxInputChars == 700)
    }

    /// recommendedByRAM：纯静态档（不看可用内存），「本地优先」纠偏据此判断本该选哪档
    @Test func recommendedByRAMTiers() {
        #expect(EngineTuning.recommendedByRAM(physicalMemory: 48 * GB)
            == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 4096, maxInputChars: 6000))
        #expect(EngineTuning.recommendedByRAM(physicalMemory: 32 * GB)
            == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 3000))
        #expect(EngineTuning.recommendedByRAM(physicalMemory: 16 * GB)
            == EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 1500))
        #expect(EngineTuning.recommendedByRAM(physicalMemory: 8 * GB)
            == EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700))
    }

    /// 可用内存充足时 recommended 与 recommendedByRAM 等价：压力降档是静态档上的唯一偏移
    @Test func recommendedByRAMMatchesRecommendedWithPlentyAvailable() {
        for ram in [8 * GB, 16 * GB, 32 * GB, 48 * GB] {
            #expect(EngineTuning.recommendedByRAM(physicalMemory: ram)
                == EngineTuning.recommended(physicalMemory: ram, availableMemory: plenty))
        }
    }
}
