import Foundation
import Testing
import MLX
import MLXLMCommon
@testable import GemmaTransKit

// MLX initializes its Metal library even with a scoped CPU device. Run this suite
// in the Xcode test scheme, which builds that library; plain SwiftPM tests skip it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GEMMATRANS_HYMT_PREFILL_TEST"] == "1"))
struct HunyuanPrefillTests {
    private func model() throws -> HunyuanModel {
        let data = Data(#"{"hidden_size":8,"num_hidden_layers":2,"intermediate_size":16,"num_attention_heads":2,"num_key_value_heads":1,"rms_norm_eps":0.00001,"vocab_size":32,"head_dim":4,"tie_word_embeddings":true}"#.utf8)
        return HunyuanModel(try JSONDecoder().decode(HunyuanConfiguration.self, from: data))
    }

    @Test(arguments: [(1, 512), (2, 512), (11, 3), (8, 0), (8, -1)])
    func prefillPreservesLastTokenAndCachePosition(length: Int, window: Int) throws {
        try Device.withDefaultDevice(.cpu) {
            let model = try model()
            let cache = model.newCache(parameters: nil)
            let ids = Array(0..<length)
            let prepared = try model.prepare(LMInput(tokens: MLXArray(ids)), cache: cache, windowSize: window)
            guard case .tokens(let last) = prepared else { Issue.record("Expected the final prompt token"); return }
            #expect(last.tokens.asArray(Int.self) == [ids.last!])
            #expect(cache.allSatisfy { $0.offset == length - 1 })
            let logits = model(last.tokens[.newAxis], cache: cache)
            eval(logits)
            #expect(logits.shape == [1, 1, 32])
            #expect(cache.allSatisfy { $0.offset == length })
        }
    }

    @Test func absentCacheDoesNotDiscardPrompt() throws {
        try Device.withDefaultDevice(.cpu) {
            let model = try model()
            let ids = [1, 2, 3]
            let prepared = try model.prepare(LMInput(tokens: MLXArray(ids)), cache: [], windowSize: 1)
            guard case .tokens(let remaining) = prepared else { Issue.record("Expected the original prompt"); return }
            #expect(remaining.tokens.asArray(Int.self) == ids)
        }
    }
}
