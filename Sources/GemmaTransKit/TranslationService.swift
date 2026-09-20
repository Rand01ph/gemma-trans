import Foundation

public struct TranslationStreamResult: Sendable {
    public let detected: String
    public let target: String
    public let truncated: Bool
    public let statistics: TranslationStatistics
    public let progress: AsyncStream<TranslationProgress>
    public let chunks: AsyncThrowingStream<String, Error>

    public init(detected: String, target: String, truncated: Bool, chunks: AsyncThrowingStream<String, Error>,
                statistics: TranslationStatistics = TranslationStatistics(),
                progress: AsyncStream<TranslationProgress> = AsyncStream { $0.finish() }) {
        self.detected = detected
        self.target = target
        self.truncated = truncated
        self.chunks = chunks
        self.statistics = statistics
        self.progress = progress
    }

    /// 聚合为完整译文（非流式调用方用）
    public func fullText() async throws -> String {
        var out = ""
        for try await c in chunks { out += c }
        try Task.checkCancellation()
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol TranslationService: Sendable {
    /// target 为 nil 时按智能双向规则自动决定
    func translate(_ text: String, target: String?) async throws -> TranslationStreamResult
    var isReady: Bool { get async }
}

public enum TranslationError: Error, Sendable, LocalizedError {
    case incompleteTranslation(String)
    case modelNotLoaded
    case emptyInput
    case queueTimeout
    /// family 对应的加载器尚未实现；msg 为展示给调用方的中文说明。
    case modelNotSupported(String)
}

extension TranslationError {
    public var errorDescription: String? {
        switch self {
        case .incompleteTranslation(let message): return "翻译未完成：" + message
        case .modelNotLoaded: return "模型尚未就绪"
        case .emptyInput: return "没有可翻译的文本"
        case .queueTimeout: return "翻译等待超时"
        case .modelNotSupported(let message): return message
        }
    }
}
