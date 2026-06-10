import Foundation

/// 按机器内存推导的引擎参数。纯函数，便于全表单测。
public struct EngineTuning: Sendable, Equatable {
    public let maxNumTokens: Int
    public let maxInputChars: Int

    public init(maxNumTokens: Int, maxInputChars: Int) {
        self.maxNumTokens = maxNumTokens
        self.maxInputChars = maxInputChars
    }

    /// 档位表：物理内存下限（含）→ 参数。顺序从高到低，降档即取下一行。
    static let tiers: [(minRAM: UInt64, tuning: EngineTuning)] = [
        (48 << 30, EngineTuning(maxNumTokens: 8192, maxInputChars: 6000)),
        (32 << 30, EngineTuning(maxNumTokens: 4096, maxInputChars: 3000)),
        (16 << 30, EngineTuning(maxNumTokens: 2048, maxInputChars: 1500)),
        (0,        EngineTuning(maxNumTokens: 1024, maxInputChars: 700)),
    ]

    /// 模型之外的工作余量（KV cache、激活、GPU 缓冲、其他 app）
    static let workspaceBytes: UInt64 = 4 << 30

    /// - Parameter availableMemory: 当前可用内存；nil 表示读取失败，不降档（退化为纯静态分档）
    public static func recommended(
        physicalMemory: UInt64, availableMemory: UInt64?, modelFileSize: UInt64
    ) -> EngineTuning {
        var index = tiers.firstIndex { physicalMemory >= $0.minRAM } ?? tiers.count - 1
        if let available = availableMemory, available < modelFileSize + workspaceBytes {
            index = min(index + 1, tiers.count - 1)
        }
        return tiers[index].tuning
    }
}
