import Foundation

public struct TranslationStreamResult: Sendable {
    public let detected: String
    public let target: String
    public let truncated: Bool
    public let chunks: AsyncThrowingStream<String, Error>

    public init(detected: String, target: String, truncated: Bool, chunks: AsyncThrowingStream<String, Error>) {
        self.detected = detected
        self.target = target
        self.truncated = truncated
        self.chunks = chunks
    }

    /// 聚合为完整译文（非流式调用方用）
    public func fullText() async throws -> String {
        var out = ""
        for try await c in chunks { out += c }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol TranslationService: Sendable {
    /// target 为 nil 时按智能双向规则自动决定
    func translate(_ text: String, target: String?) async throws -> TranslationStreamResult
    var isReady: Bool { get async }
}

public enum TranslationError: Error, Sendable {
    case modelNotLoaded
    case emptyInput
    case queueTimeout
}
