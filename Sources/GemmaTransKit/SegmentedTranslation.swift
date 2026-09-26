import Foundation

public struct TranslationProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public var status: String { "翻译中 \(min(completed + 1, total))/\(total)" }
}

public struct TranslationMetrics: Sendable, Equatable {
    public let generatedTokens: Int
    public let generationSeconds: Double
    public var tokensPerSecond: Double? {
        guard generatedTokens > 0, generationSeconds > 0, generationSeconds.isFinite else { return nil }
        let rate = Double(generatedTokens) / generationSeconds
        return rate.isFinite ? rate : nil
    }
}

/// One store per request; finishing another request cannot overwrite these metrics.
public actor TranslationStatistics {
    public init() {}
    public private(set) var metrics: TranslationMetrics?
    func finish(_ metrics: TranslationMetrics) { self.metrics = metrics }
}

/// Retry only resource limits, never arbitrary backend failures.
enum SegmentLimit: Error, Sendable { case output, context }

struct TranslationSegment: Sendable {
    let text: String
    let metrics: TranslationMetrics
}

/// Backend-independent orchestration. A segment is committed only after normal completion.
enum SegmentedTranslation {
    static func run(
        text: String, limit: Int,
        generate: @Sendable (String) async throws -> TranslationSegment,
        progress: @Sendable (TranslationProgress) -> Void,
        emit: @Sendable (String) -> Void
    ) async throws -> TranslationMetrics {
        var pending = TextChunker.translationSegments(text, limit: max(1, limit))
        var index = 0
        var tokens = 0
        var seconds = 0.0
        while index < pending.count {
            try Task.checkCancellation()
            progress(TranslationProgress(completed: index, total: pending.count))
            let input = pending[index]
            do {
                let result = try await generate(input)
                try Task.checkCancellation()
                let output = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { throw TranslationError.incompleteTranslation("模型返回空译文") }
                emit((index == 0 ? "" : "\n\n") + output)
                tokens += result.metrics.generatedTokens
                seconds += result.metrics.generationSeconds
                index += 1
            } catch is SegmentLimit {
                guard input.count > 1 else {
                    throw TranslationError.incompleteTranslation("单段仍超过模型容量，请调整模型或生成参数后重试")
                }
                let pieces = TextChunker.split(input, limit: max(1, input.count / 2))
                guard pieces.count > 1 else {
                    throw TranslationError.incompleteTranslation("无法继续拆分输入")
                }
                pending.replaceSubrange(index...index, with: pieces)
            }
        }
        progress(TranslationProgress(completed: index, total: pending.count))
        return TranslationMetrics(generatedTokens: tokens, generationSeconds: seconds)
    }
}
