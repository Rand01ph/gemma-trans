# App extensions and distribution composition

The public MIT repository remains a complete, independently buildable free app. It contains no
purchase checks, private repository URLs, private credentials or paid customization implementation.
The standalone CLI always constructs `TranslationEngine` with its default initializer.

## Prompt extension

`TranslationEngine(settings:promptProvider:)` accepts an optional, thread-safe
`TranslationPromptProvider`. Existing callers are source compatible. `nil` from the provider uses
the existing byte-for-byte default prompt. `TranslationPromptRequest` contains the input after
existing trimming/character limits, the detected and target languages, and the model family.
Its `defaultPrompt` is also available to implementations that add guidance.

The provider executes synchronously before the engine suspends or queues generation. It must take
an immutable snapshot and must not read mutable UI state later. Changing an extension's state
affects subsequent requests without loading/unloading the model. A Gemma request supports the
system instruction; Hy-MT2 remains user-only. `process(_:instruction:)` is unchanged and does not
use translation extensions.

The complete chat template is tokenized with the active model's tokenizer before accepting a
translation. Input plus the existing output budget must fit the model context. This adds no silent
source truncation. Both HTTP routes return status 400 with `error: "prompt_too_long"` before opening
an SSE response. Existing request fields and `TranslationService` stay unchanged.

## Shared app composition

`App/shared-targets.yml` is the XcodeGen build template. The free project combines
`App/GemmaTrans` and `App/Composition/FreeAppComposition.swift` with it. A downstream distribution
can include the shared sources, supply exactly one `AppComposition.makeFeatures()` implementation,
and override its version, signing, resources and entitlements.

`AppFeatures` exposes a prompt provider, optional settings page, scene selector and menu content.
The public implementation supplies empty views and no provider. All app entry points reuse the
same `EngineController` and injected provider, including the optional local HTTP server.

App Store distribution beginning with 2.2 is assembled in the separately maintained private
distribution repository. This repository's MAS target remains buildable for sandbox regression
checks; it is not the App Store publishing entry point. GitHub releases continue to ship this
repository's free app. Public fixes are merged first, then the distribution's pinned public commit
is updated through a separate PR and verified before release.

## Validation

Run `swift test`, generate the public project with `(cd App && xcodegen generate)`, and build both
public schemes. `TranslationPromptTests` protects default prompts and budget boundaries;
`TranslateRouteTests` checks the 400 response for streaming and non-streaming requests on both
routes. `Runtime/LlamaRuntime/Tests/RuntimeGate.cpp` additionally exercises real GGUF tokenization,
oversize rejection, repeated generation and model switching. Model-backed tests are opt-in; a
normal unit-test pass does not assert translation quality on downloaded models.
