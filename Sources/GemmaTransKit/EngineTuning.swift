import Foundation

/// MLX 模型变体（注册表 id 在引擎层映射）
public enum ModelVariant: String, Sendable {
    case gemma4E4B4bit  // ≈4.9GB
    case gemma4E2B4bit  // ≈3.6GB

    /// 估算驻留内存（权重 + 激活），用于压力降档判断。
    /// 数值为真机/磁盘实测的权重落盘体积（E4B 4.9GB、E2B 3.6GB）；
    /// 旧估值 2.4G/1.5G 低估约一倍，导致内存压力判断过于乐观。
    var estimatedBytes: UInt64 {
        switch self {
        case .gemma4E4B4bit: return 4_900_000_000
        case .gemma4E2B4bit: return 3_600_000_000
        }
    }
}

/// 按机器内存推导的引擎参数。纯函数，便于全表单测。
public struct EngineTuning: Sendable, Equatable {
    public let variant: ModelVariant
    public let maxTokens: Int       // 单次生成上限
    public let maxInputChars: Int

    public init(variant: ModelVariant, maxTokens: Int, maxInputChars: Int) {
        self.variant = variant
        self.maxTokens = maxTokens
        self.maxInputChars = maxInputChars
    }

    /// 档位表：物理内存下限（含）→ 参数。顺序从高到低，降档即取下一行。
    static let tiers: [(minRAM: UInt64, tuning: EngineTuning)] = [
        (48 << 30, EngineTuning(variant: .gemma4E4B4bit, maxTokens: 4096, maxInputChars: 6000)),
        (32 << 30, EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 3000)),
        (16 << 30, EngineTuning(variant: .gemma4E4B4bit, maxTokens: 2048, maxInputChars: 1500)),
        (0,        EngineTuning(variant: .gemma4E2B4bit, maxTokens: 1024, maxInputChars: 700)),
    ]

    /// 模型之外的工作余量（KV cache、激活、其他 app）
    static let workspaceBytes: UInt64 = 2 << 30

    /// - Parameter availableMemory: 当前可用内存；nil 表示读取失败，不降档（退化为纯静态分档）
    public static func recommended(
        physicalMemory: UInt64, availableMemory: UInt64?
    ) -> EngineTuning {
        var index = tierIndex(physicalMemory: physicalMemory)
        if let available = availableMemory,
           available < tiers[index].tuning.variant.estimatedBytes + workspaceBytes {
            index = min(index + 1, tiers.count - 1)
        }
        return tiers[index].tuning
    }

    /// 纯静态档：只看物理内存，不做可用内存压力降档。
    /// 引擎「本地优先」纠偏用它判断按物理内存本该选哪一档（与 recommended 在
    /// 可用内存充足时等价；recommended 的压力降档是在此静态档上的唯一偏移）。
    public static func recommendedByRAM(physicalMemory: UInt64) -> EngineTuning {
        tiers[tierIndex(physicalMemory: physicalMemory)].tuning
    }

    private static func tierIndex(physicalMemory: UInt64) -> Int {
        tiers.firstIndex { physicalMemory >= $0.minRAM } ?? tiers.count - 1
    }
}
