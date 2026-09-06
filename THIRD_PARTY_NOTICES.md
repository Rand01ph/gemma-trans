# Third-party notices

GemmaTrans's original source code and accompanying documentation are licensed under the [MIT License](LICENSE), except where otherwise stated. That license does not replace the licenses or copyright notices of third-party dependencies, upstream runtime code (including third-party material in patches), or model weights.

GemmaTrans 2.1.0 contains a statically linked, CPU-only runtime used only for the two curated Hy-MT2 v2 GGUF model files listed in `ModelCatalog`.

## Runtime source composition

- `llama.cpp` STQ baseline: PR #22836, fixed head `1e411d8f5a1e23525fa3265dfb4bd76265465397`.
- `Q2_0C` / KleidiAI source: PR #19357, fixed head `2af64dd00a6689a7bfaf69b4768a944d0ec6bade`.
- Historical contiguous STQ layout reference: `08ff527fd5c35e69395ee063fb722fe393e36122`.
- Complete machine-readable source manifest: `Runtime/LlamaRuntime/upstream.json`.
- Reproducible composition patch: `Runtime/LlamaRuntime/patches/combined.patch`.
- Deterministic build entry point: `Runtime/LlamaRuntime/build-xcframework.sh`.
- Published immutable artifact: `runtime-llama-2.2.0-r1`, verified by the SwiftPM checksum recorded in [Runtime/LlamaRuntime/CHECKSUMS.txt](Runtime/LlamaRuntime/CHECKSUMS.txt).

## Runtime licenses

- llama.cpp: [MIT License](Runtime/LlamaRuntime/LICENSES/llama.cpp-MIT.txt).
- Arm KleidiAI: [Apache License 2.0](Runtime/LlamaRuntime/LICENSES/KleidiAI-Apache-2.0.txt) and [BSD 3-Clause notices](Runtime/LlamaRuntime/LICENSES/KleidiAI-BSD-3-Clause.txt).

The binary does not include llama.cpp tools, examples, tests, server, CURL, subprocess helpers, telemetry, MTMD, Metal, or an arbitrary GGUF loader exposed to users. Model licenses remain those published with each selected model repository and are not replaced by the runtime licenses above.

## Other software dependencies

Swift package dependencies are declared in [Package.swift](Package.swift), with resolved versions in [Package.resolved](Package.resolved). Each dependency retains its own license and notices. When redistributing a build, retain the licenses and notices required by the components included in that build; this index is not a replacement for those license texts.

## Downloaded models

Model weights are not bundled with the App or this source repository. They are downloaded separately from the upstream repositories selected in [ModelCatalog.swift](Sources/GemmaTransKit/ModelCatalog.swift), using Hugging Face or the ModelScope fallback. Separate downloading does not remove the obligations under the applicable model licenses.

Tencent publishes Hy-MT2 under [Apache License 2.0](https://github.com/Tencent-Hunyuan/Hy-MT2/blob/main/LICENSE.txt). The two curated GGUF distributions provide their own license files at the exact Hugging Face revisions used by GemmaTrans 2.1.0:

| Distribution | Upstream license file |
| --- | --- |
| Hy-MT2 1.8B 1.25-bit v2 | [AngelSlim / revision 0989912](https://huggingface.co/AngelSlim/Hy-MT2-1.8B-1.25Bit-GGUF/blob/0989912c0cc2d3edeeecd76171d1c7d94ee17255/LICENSE.txt) |
| Hy-MT2 1.8B 2-bit v2 | [AngelSlim / revision 2245b9e](https://huggingface.co/AngelSlim/Hy-MT2-1.8B-2Bit-GGUF/blob/2245b9ea2bdd68a67b21b44db9564e7d32fc3bc6/LICENSE.txt) |

The other model distributions are [Gemma 4 E4B 4-bit](https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit), [Gemma 4 E2B 4-bit](https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit), [Hy-MT2 1.8B 4-bit](https://huggingface.co/mlx-community/Hy-MT2-1.8B-4bit), and [Hy-MT2 1.8B 8-bit](https://huggingface.co/mlx-community/Hy-MT2-1.8B-8bit). Consult the license files and model cards accompanying the downloaded revision, together with the original model's terms. These model weights are not relicensed under GemmaTrans's MIT License.

If you redistribute model weights, a runtime, or a modified third-party component, comply with its own redistribution conditions, including any required license copies, attribution, notices, and modification statements.
