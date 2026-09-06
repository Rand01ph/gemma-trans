# Hy-MT2 first-token language regression

Hy-MT2's Swift adapter now follows the reference Python generation path: fill the
KV cache with all but the last prompt token, then use a single-token decoding step
to choose the first output token. This applies to both MLX quantizations, without
changing prompt text, sampling settings, model weights, Gemma or the GGUF runtime.

On an M5 Pro / macOS 27 host, the previous all-at-once short-prompt path could
produce Japanese or Russian fragments in Chinese/English translations. A controlled
comparison used the same weights and exact token IDs with Python mlx-lm 0.30.7 /
MLX 0.31.1, matching the Swift runtime's MLX version. Python's full-prompt forward
pass reproduced the wrong first token as well; Python's normal generation loop
prefilled all but the final token and produced the correct language. The Swift
adapter produces the correct language with that same preparation sequence.

This isolates a reproducible prefill-dependent failure on the tested backend. It
does not establish the underlying Metal/kernel numerical cause, or claim that all
possible multilingual output is eliminated. No output replacements or extra
language instructions are used to hide the failure.

| Source and target | Before | After, both 4-bit and 8-bit |
| --- | --- | --- |
| `Open the workspace.` → Chinese | Russian/Chinese or unnatural `翻开工作区。` | `打开工作区。` |
| `这个工作区采用云计算来处理数据。` → English | `この workspace…` | `This workspace uses cloud computing to process data.` |

The follow-up also covered the production engine's six bilingual style/glossary
samples in default/customized modes and its real HTTP adapter. These fixed samples
are a regression check, not a general translation-quality guarantee.

`HunyuanPrefillTests` exercises real tiny model caches: one-token input, short
prompts, chunk boundaries, invalid chunk sizes and an absent-cache fallback. The
remaining token and each layer's cache position are checked before and after the
first decoding step. Run with the Xcode `HunyuanModelTests` scheme; plain
`swift test` skips this suite because it cannot build MLX's Metal library. CI runs
the Xcode suite explicitly, without downloading model weights.

Reference: [mlx-lm 0.30.7 generation loop](https://github.com/ml-explore/mlx-lm/blob/v0.30.7/mlx_lm/generate.py).
