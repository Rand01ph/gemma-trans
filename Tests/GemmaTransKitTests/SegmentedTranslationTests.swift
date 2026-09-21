import Foundation
import Testing
@testable import GemmaTransKit

private final class OutputLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.withLock { values.append(value) } }
    var text: String { lock.withLock { values.joined() } }
}

@Suite struct SegmentedTranslationTests {
    @Test func articleParagraphsNeverMergeIntoOneGeneration() {
        #expect(TextChunker.translationSegments("First.\n\nSecond.\n\nThird.", limit: 1500)
            == ["First.", "Second.", "Third."])
    }

    @Test(arguments: ["abcdef", String(repeating: "一段中文👩🏽‍💻。\n\nNext paragraph! ", count: 100)])
    func preservesAllContentAndOrder(_ input: String) async throws {
        let log = OutputLog()
        let metrics = try await SegmentedTranslation.run(text: input, limit: 23, generate: { text in
            TranslationSegment(text: text, metrics: .init(generatedTokens: text.count, generationSeconds: Double(text.count) / 20))
        }, progress: { _ in }, emit: { log.append($0) })
        #expect(log.text.filter { !$0.isWhitespace } == input.filter { !$0.isWhitespace })
        #expect(abs((metrics.tokensPerSecond ?? 0) - 20) < 0.001)
    }

    @Test func retriesOnlyUncommittedSegments() async throws {
        let log = OutputLog()
        _ = try await SegmentedTranslation.run(text: "AAAABBBBCCCC", limit: 4, generate: { text in
            if text.count > 2 { throw SegmentLimit.output }
            return TranslationSegment(text: text, metrics: .init(generatedTokens: 2, generationSeconds: 1))
        }, progress: { _ in }, emit: { log.append($0) })
        #expect(log.text.replacingOccurrences(of: "\n", with: "") == "AAAABBBBCCCC")
    }

    @Test func contextLimitSplitsAndSingleCharacterFailureTerminates() async throws {
        let log = OutputLog()
        await #expect(throws: TranslationError.self) {
            _ = try await SegmentedTranslation.run(text: "ABC", limit: 3, generate: { _ in
                throw SegmentLimit.context
            }, progress: { _ in }, emit: { log.append($0) })
        }
        #expect(log.text.isEmpty)
    }

    @Test func failureRetainsPreviousSegments() async throws {
        let log = OutputLog()
        await #expect(throws: TranslationError.self) {
            _ = try await SegmentedTranslation.run(text: "ABCDEF", limit: 3, generate: { text in
                if text == "DEF" { throw TranslationError.modelNotLoaded }
                return TranslationSegment(text: text, metrics: .init(generatedTokens: 3, generationSeconds: 1))
            }, progress: { _ in }, emit: { log.append($0) })
        }
        #expect(log.text == "ABC")
    }

    @Test func cancellationNeverCommitsCurrentSegment() async throws {
        let log = OutputLog()
        let task = Task {
            try await SegmentedTranslation.run(text: "ABCD", limit: 2, generate: { _ in
                try await Task.sleep(for: .seconds(60))
                return TranslationSegment(text: "unexpected", metrics: .init(generatedTokens: 1, generationSeconds: 1))
            }, progress: { _ in }, emit: { log.append($0) })
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.text.isEmpty)
    }

    @Test func requestMetricsAreIndependentAndRejectInvalidRates() async {
        let first = TranslationStatistics(), second = TranslationStatistics()
        await first.finish(.init(generatedTokens: 10, generationSeconds: 2))
        await second.finish(.init(generatedTokens: 100, generationSeconds: 1))
        #expect(await first.metrics?.tokensPerSecond == 5)
        #expect(await second.metrics?.tokensPerSecond == 100)
        #expect(TranslationMetrics(generatedTokens: 0, generationSeconds: 1).tokensPerSecond == nil)
        #expect(TranslationMetrics(generatedTokens: 1, generationSeconds: .nan).tokensPerSecond == nil)
    }
}
