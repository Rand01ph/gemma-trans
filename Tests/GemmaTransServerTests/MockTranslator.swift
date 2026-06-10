import Foundation
import GemmaTransKit

struct MockTranslator: TranslationService {
    var ready = true
    var chunks: [String] = ["你好", "，", "世界"]
    var detected = "en"
    var target = "zh-Hans"

    var isReady: Bool { get async { ready } }

    func translate(_ text: String, target: String?) async throws -> TranslationStreamResult {
        guard !text.isEmpty else { throw TranslationError.emptyInput }
        guard ready else { throw TranslationError.modelNotLoaded }
        let (stream, cont) = AsyncThrowingStream.makeStream(of: String.self)
        let pieces = chunks
        Task {
            for p in pieces { cont.yield(p) }
            cont.finish()
        }
        return TranslationStreamResult(
            detected: detected, target: target ?? self.target, truncated: false, chunks: stream
        )
    }
}

/// 永不产出也不结束——用于排队超时测试
struct StuckTranslator: TranslationService {
    var isReady: Bool { get async { true } }
    func translate(_ text: String, target: String?) async throws -> TranslationStreamResult {
        let (stream, _) = AsyncThrowingStream.makeStream(of: String.self)
        return TranslationStreamResult(detected: "en", target: "zh-Hans", truncated: false, chunks: stream)
    }
}
