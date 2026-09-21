# Third-party notices

GemmaTrans 2.1.0 contains a statically linked, CPU-only runtime used only for the two curated Hy-MT2 v2 GGUF model files listed in `ModelCatalog`.

## Runtime source composition

- `llama.cpp` STQ baseline: PR #22836, fixed head `1e411d8f5a1e23525fa3265dfb4bd76265465397`.
- `Q2_0C` / KleidiAI source: PR #19357, fixed head `2af64dd00a6689a7bfaf69b4768a944d0ec6bade`.
- Historical contiguous STQ layout reference: `08ff527fd5c35e69395ee063fb722fe393e36122`.
- Complete machine-readable source manifest: `Runtime/LlamaRuntime/upstream.json`.
- Reproducible composition patch: `Runtime/LlamaRuntime/patches/combined.patch`.
- Deterministic build entry point: `Runtime/LlamaRuntime/build-xcframework.sh`.
- Published immutable artifact: `runtime-llama-2.1.0-r1`, verified by the SwiftPM checksum recorded in `Runtime/LlamaRuntime/CHECKSUMS.txt`.

## Licenses

- llama.cpp: MIT License — `Runtime/LlamaRuntime/Licenses/llama.cpp-MIT.txt`.
- Arm KleidiAI: Apache License 2.0 and BSD 3-Clause notices — `Runtime/LlamaRuntime/Licenses/KleidiAI-Apache-2.0.txt` and `Runtime/LlamaRuntime/Licenses/KleidiAI-BSD-3-Clause.txt`.

The binary does not include llama.cpp tools, examples, tests, server, CURL, subprocess helpers, telemetry, MTMD, Metal, or an arbitrary GGUF loader exposed to users. Model licenses remain those published with each selected model repository and are not replaced by the runtime licenses above.
