//
//  HunyuanSpike.swift
//  GemmaTransKit
//
//  Plan A 决策门用：注册混元类型 → 从本地目录加载 Hy-MT2 → 跑一次生成。
//  仅 spike 验证用，不进正式翻译流程（正式接入见后续 Plan C）。
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// 加载本地 Hy-MT2 快照并对 `text` 生成一次回复，流式打印同时返回全文。
/// - Parameter modelDir: 含 config.json / *.safetensors / tokenizer* 的本地目录。
public func hunyuanSpikeTranslate(
    modelDir: URL, text: String, maxTokens: Int = 256
) async throws -> String {
    await registerHunyuanIfNeeded()
    let container = try await loadModelContainer(
        from: modelDir, using: #huggingFaceTokenizerLoader())
    let session = ChatSession(
        container,
        generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.1))
    var out = ""
    for try await chunk in session.streamResponse(to: text) {
        out += chunk
        print(chunk, terminator: "")
    }
    print("")
    return out
}
