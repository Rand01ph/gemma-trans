# LlamaRuntime

GemmaTrans 2.1.0 uses a curated, CPU-only `llama.cpp` runtime for exactly two Hy-MT2 v2 GGUF files. The app does not expose arbitrary GGUF loading.

The runtime is reconstructed from the fixed STQ PR head recorded in `upstream.json`, then `patches/combined.patch` ports the fixed Q2_0C/KleidiAI PR and applies GemmaTrans's type-number, old-STQ-layout, EOG, and per-model KleidiAI compatibility changes. No long-lived fork is required.

The XCFramework includes only the audited `llama-common` object closure required by chat-template/Jinja formatting. The build fails if download/HTTP symbols are present; tools, server, CURL, subprocess helpers, telemetry and Metal are not part of the runtime surface.

Build the static macOS arm64 XCFramework and deterministic ZIP with:

```sh
Runtime/LlamaRuntime/build-xcframework.sh
```

The script targets macOS 15.0 or later, prints the ZIP SHA-256 and SwiftPM checksum, and rejects archive members with a newer minimum OS. Release assets are immutable and use the tag `runtime-llama-2.2.0-r1`.

Published asset URL:

```text
https://github.com/Rand01ph/gemma-trans/releases/download/runtime-llama-2.2.0-r1/LlamaRuntime-2.2.0-r1.zip
```

The expected asset and composition-patch digests are recorded in `CHECKSUMS.txt`.

Version 2.2.0-r1 adds `gt_llama_validate_prompt`: it tokenizes the complete chat template and
reserves output capacity without modifying KV state. Generation repeats this check before
decoding. The Swift bridge maps capacity rejection to `TranslationError.promptTooLong`.

Run `Tests/RuntimeGate.cpp` against the two pinned model files before publishing the asset. The gate loads 1.25-bit, translates 20 times, completely unloads it, loads 2-bit and translates 20 times, then unloads and switches back to 1.25-bit.
