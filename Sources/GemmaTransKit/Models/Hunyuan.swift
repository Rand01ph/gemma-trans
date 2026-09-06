//
//  Hunyuan.swift
//  GemmaTransKit
//
//  腾讯混元 dense 架构（model_type = hunyuan_v1_dense）的 Swift MLX 移植。
//  蓝本：Python mlx-lm 的 mlx_lm/models/hunyuan_v1_dense.py。
//
//  与标准 Llama/Qwen 的差异仅两处：
//  1. QK-norm：对 q/k 做带权重的 RMSNorm（query_layernorm / key_layernorm），
//     且顺序是 **RoPE 之后** 再 norm（区别于 Qwen3 的 norm 在前）。
//  2. 自定义 RoPE：DynamicNTKAlpha——把 rope_scaling.alpha 烤进 base 频率后预算 freqs，
//     喂给 MLXFast.RoPE(base: nil, freqs:)。
//
//  本模型（Hy-MT2-1.8B）config 里 use_cla=false，故无跨层 KV 共享（CLA）；dense_list/MoE 也不涉及。
//  量化（4bit/affine）由加载工厂按 config.quantization 自动施加，模型文件只声明普通 Linear。
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

// MARK: - RoPE（DynamicNTKAlpha：预算 freqs）

private final class HunyuanRoPE: Module, OffsetLayer, ArrayOffsetLayer {
    let dimensions: Int
    /// 只存标量：ln(adjustedBase)。不在 Module 上存任何 MLXArray，否则会被 update(verify: .all)
    /// 当成待加载参数（rope.freqs）而权重里没有 → keyNotFound。freqs 在调用时现算（64 元素，极廉价）。
    private let logAdjustedBase: Float

    /// - Parameters:
    ///   - dimensions: head_dim
    ///   - base: rope_theta
    ///   - scalingAlpha: rope_scaling.alpha（无则 1.0）
    init(dimensions: Int, base: Float, scalingAlpha: Float) {
        self.dimensions = dimensions
        // base = base * scalingAlpha ** (dims / (dims - 2))
        let adjustedBase = Double(base) * pow(Double(scalingAlpha), Double(dimensions) / Double(dimensions - 2))
        self.logAdjustedBase = Float(log(adjustedBase))
        super.init()
    }

    /// _freqs = adjustedBase ** (arange(0, dims, 2) / dims)，等价 exp(exponents * ln(adjustedBase))
    private func makeFreqs() -> MLXArray {
        let idx = MLXArray(stride(from: 0, to: dimensions, by: 2).map { $0 }).asType(.float32)
        return MLX.exp((idx / Float(dimensions)) * logAdjustedBase)
    }

    func callAsFunction(_ x: MLXArray, offset: Int) -> MLXArray {
        MLXFast.RoPE(
            x, dimensions: dimensions, traditional: false, base: nil, scale: 1.0,
            offset: offset, freqs: makeFreqs())
    }

    func callAsFunction(_ x: MLXArray, offset: MLXArray) -> MLXArray {
        MLXFast.RoPE(
            x, dimensions: dimensions, traditional: false, base: nil, scale: 1.0,
            offset: offset, freqs: makeFreqs())
    }
}

// MARK: - Attention

private class HunyuanAttention: Module {
    let nHeads: Int
    let nKVHeads: Int
    let headDim: Int
    let scale: Float
    let useQKNorm: Bool

    @ModuleInfo(key: "q_proj") var wq: Linear
    @ModuleInfo(key: "k_proj") var wk: Linear
    @ModuleInfo(key: "v_proj") var wv: Linear
    @ModuleInfo(key: "o_proj") var wo: Linear

    @ModuleInfo(key: "query_layernorm") var queryLayernorm: RMSNorm?
    @ModuleInfo(key: "key_layernorm") var keyLayernorm: RMSNorm?

    let rope: HunyuanRoPE

    init(_ args: HunyuanConfiguration) {
        let dim = args.hiddenSize
        self.nHeads = args.attentionHeads
        self.nKVHeads = args.kvHeads
        self.headDim = args.resolvedHeadDim
        self.scale = pow(Float(headDim), -0.5)
        self.useQKNorm = args.useQKNorm

        _wq.wrappedValue = Linear(dim, nHeads * headDim, bias: args.attentionBias)
        _wk.wrappedValue = Linear(dim, nKVHeads * headDim, bias: args.attentionBias)
        _wv.wrappedValue = Linear(dim, nKVHeads * headDim, bias: args.attentionBias)
        _wo.wrappedValue = Linear(nHeads * headDim, dim, bias: args.attentionBias)

        if args.useQKNorm {
            _queryLayernorm.wrappedValue = RMSNorm(dimensions: headDim, eps: args.rmsNormEps)
            _keyLayernorm.wrappedValue = RMSNorm(dimensions: headDim, eps: args.rmsNormEps)
        }

        self.rope = HunyuanRoPE(
            dimensions: headDim, base: args.ropeTheta, scalingAlpha: args.ropeScalingAlpha)
    }

    func callAsFunction(
        _ x: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache?
    ) -> MLXArray {
        let (B, L) = (x.dim(0), x.dim(1))

        var queries = wq(x).reshaped(B, L, nHeads, -1).transposed(0, 2, 1, 3)
        var keys = wk(x).reshaped(B, L, nKVHeads, -1).transposed(0, 2, 1, 3)
        let values = wv(x).reshaped(B, L, nKVHeads, -1).transposed(0, 2, 1, 3)

        // 顺序按混元：先 RoPE，再 QK-norm（带权重），再入 cache + 注意力。
        queries = applyRotaryPosition(rope, to: queries, cache: cache)
        keys = applyRotaryPosition(rope, to: keys, cache: cache)

        if useQKNorm, let queryLayernorm, let keyLayernorm {
            queries = queryLayernorm(queries)
            keys = keyLayernorm(keys)
        }

        let output = attentionWithCacheUpdate(
            queries: queries, keys: keys, values: values,
            cache: cache, scale: scale, mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(B, L, -1)

        return wo(output)
    }
}

// MARK: - MLP（SwiGLU）

private class HunyuanMLP: Module, UnaryLayer {
    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "down_proj") var down: Linear
    @ModuleInfo(key: "up_proj") var up: Linear

    init(dimensions: Int, hiddenDimensions: Int) {
        _gate.wrappedValue = Linear(dimensions, hiddenDimensions, bias: false)
        _down.wrappedValue = Linear(hiddenDimensions, dimensions, bias: false)
        _up.wrappedValue = Linear(dimensions, hiddenDimensions, bias: false)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        down(silu(gate(x)) * up(x))
    }
}

// MARK: - Transformer Block

private class HunyuanTransformerBlock: Module {
    @ModuleInfo(key: "self_attn") var attention: HunyuanAttention
    let mlp: HunyuanMLP

    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm

    init(_ args: HunyuanConfiguration) {
        _attention.wrappedValue = HunyuanAttention(args)
        self.mlp = HunyuanMLP(
            dimensions: args.hiddenSize, hiddenDimensions: args.intermediateSize)
        _inputLayerNorm.wrappedValue = RMSNorm(dimensions: args.hiddenSize, eps: args.rmsNormEps)
        _postAttentionLayerNorm.wrappedValue = RMSNorm(
            dimensions: args.hiddenSize, eps: args.rmsNormEps)
    }

    func callAsFunction(
        _ x: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache?
    ) -> MLXArray {
        var r = attention(inputLayerNorm(x), mask: mask, cache: cache)
        let h = x + r
        r = mlp(postAttentionLayerNorm(h))
        return h + r
    }
}

// MARK: - Inner Model

private class HunyuanModelInner: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding

    fileprivate let layers: [HunyuanTransformerBlock]
    let norm: RMSNorm

    init(_ args: HunyuanConfiguration) {
        precondition(args.vocabularySize > 0)
        _embedTokens.wrappedValue = Embedding(
            embeddingCount: args.vocabularySize, dimensions: args.hiddenSize)
        self.layers = (0 ..< args.hiddenLayers).map { _ in HunyuanTransformerBlock(args) }
        self.norm = RMSNorm(dimensions: args.hiddenSize, eps: args.rmsNormEps)
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]? = nil) -> MLXArray {
        var h = embedTokens(inputs)
        let mask = createAttentionMask(h: h, cache: cache?.first)
        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[i])
        }
        return norm(h)
    }
}

// MARK: - Top-level Model

public class HunyuanModel: Module, LLMModel, KVCacheDimensionProvider {
    public let vocabularySize: Int
    public let kvHeads: [Int]

    fileprivate let model: HunyuanModelInner
    let configuration: HunyuanConfiguration

    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    public init(_ args: HunyuanConfiguration) {
        self.configuration = args
        self.vocabularySize = args.vocabularySize
        self.kvHeads = (0 ..< args.hiddenLayers).map { _ in args.kvHeads }
        self.model = HunyuanModelInner(args)
        if !args.tieWordEmbeddings {
            _lmHead.wrappedValue = Linear(args.hiddenSize, args.vocabularySize, bias: false)
        }
    }

    /// Match mlx-lm's prefill: populate the cache, then leave one token for decoding.
    /// The default Swift LLM path evaluates a short prompt in one batch. On Hy-MT2
    /// this can choose a different first output language than single-token decoding.
    /// Keep the prompt and sampling parameters intact while using the reference path.
    public func prepare(_ input: LMInput, cache: [KVCache], windowSize: Int?) throws -> PrepareResult {
        guard !cache.isEmpty else { return .tokens(input.text) }
        let chunkSize = max(1, windowSize ?? 512)
        var remaining = input.text
        try withPreparedCache(cache, lengths: remaining.sequenceLengths) {
            while remaining.tokens.size > 1 {
                try Task.checkCancellation()
                let count = min(chunkSize, remaining.tokens.size - 1)
                _ = self(remaining[.newAxis, ..<count], cache: cache, state: nil)
                eval(cache)
                remaining = remaining[count...]
            }
        }
        return .tokens(remaining)
    }

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        let out = model(inputs, cache: cache)
        if let lmHead {
            return lmHead(out)
        }
        return model.embedTokens.asLinear(out)
    }

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var weights = weights
        if configuration.tieWordEmbeddings {
            weights["lm_head.weight"] = nil
        }
        return weights
    }
}

// MARK: - Configuration

public struct HunyuanConfiguration: Codable, Sendable {
    var hiddenSize: Int
    var hiddenLayers: Int
    var intermediateSize: Int
    var attentionHeads: Int
    var kvHeads: Int
    var rmsNormEps: Float
    var vocabularySize: Int
    var ropeTheta: Float = 10000
    var headDim: Int?
    var ropeScaling: [String: StringOrNumber]? = nil
    var tieWordEmbeddings = false
    var useQKNorm = true
    var attentionBias = false
    var maxPositionEmbeddings: Int = 32768

    /// head_dim 缺省时由 hidden/heads 推导
    var resolvedHeadDim: Int { headDim ?? (hiddenSize / attentionHeads) }

    /// rope_scaling.alpha（DynamicNTKAlpha 用）；缺省 1.0
    var ropeScalingAlpha: Float {
        guard let alpha = ropeScaling?["alpha"]?.asFloat() else { return 1.0 }
        return alpha
    }

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case hiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case attentionHeads = "num_attention_heads"
        case kvHeads = "num_key_value_heads"
        case rmsNormEps = "rms_norm_eps"
        case vocabularySize = "vocab_size"
        case ropeTheta = "rope_theta"
        case headDim = "head_dim"
        case ropeScaling = "rope_scaling"
        case tieWordEmbeddings = "tie_word_embeddings"
        case useQKNorm = "use_qk_norm"
        case attentionBias = "attention_bias"
        case maxPositionEmbeddings = "max_position_embeddings"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hiddenSize = try c.decode(Int.self, forKey: .hiddenSize)
        self.hiddenLayers = try c.decode(Int.self, forKey: .hiddenLayers)
        self.intermediateSize = try c.decode(Int.self, forKey: .intermediateSize)
        self.attentionHeads = try c.decode(Int.self, forKey: .attentionHeads)
        self.kvHeads = try c.decode(Int.self, forKey: .kvHeads)
        self.rmsNormEps = try c.decode(Float.self, forKey: .rmsNormEps)
        self.vocabularySize = try c.decode(Int.self, forKey: .vocabularySize)
        self.ropeTheta = try c.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 10000
        self.headDim = try c.decodeIfPresent(Int.self, forKey: .headDim)
        self.ropeScaling = try c.decodeIfPresent([String: StringOrNumber].self, forKey: .ropeScaling)
        self.tieWordEmbeddings = try c.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? false
        self.useQKNorm = try c.decodeIfPresent(Bool.self, forKey: .useQKNorm) ?? true
        self.attentionBias = try c.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        self.maxPositionEmbeddings =
            try c.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings) ?? 32768
    }
}

// MARK: - LoRA

extension HunyuanModel: LoRAModel {
    public var loraLayers: [Module] {
        model.layers
    }
}
