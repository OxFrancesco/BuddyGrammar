# Local text-polishing options for BuddyGrammar

Date: 2026-07-17

## Why polishing feels slow today

BuddyGrammar currently performs text polishing as a serial cloud step after speech-to-text. The iOS app waits for transcription to finish, then sends the complete transcript to `/v1/correct`, and only marks the result ready after the correction response returns. A synthetic production request using the current default model (`openai/gpt-5.6-luna`) took about 2.8 seconds for polishing alone. Added to a typical 2–3 second final transcription, that produces roughly 5–6 seconds of perceived latency even when both services are healthy.

The iOS correction request permits 20 seconds and the Worker permits 25 seconds, so a slow provider route can make the wait substantially longer. The existing connection warm-up is used by the keyboard path, but not by the main iOS dictation path; warming the connection can remove DNS/TLS setup time, but not the model's generation latency.

## Apple Foundation Models

Apple's Foundation Models framework exposes the on-device Apple Intelligence model and explicitly supports text-refinement tasks. It is available starting with iOS 26, runs privately on-device, requires no model bundled with the app, and exposes runtime availability reasons including `deviceNotEligible`, `appleIntelligenceNotEnabled`, and `modelNotReady`. Apps should therefore retain a fallback even when they require iOS 26.

Apple lists Apple Intelligence support for iPhone 15 Pro models and iPhone 16 models or later. The test phone is a regular iPhone 15 (`iPhone15,4`), so `SystemLanguageModel` is not available on that device.

For eligible hardware, this is the preferred local provider: use `LanguageModelSession`, a narrowly scoped editing instruction, `Guardrails.permissiveContentTransformations` where appropriate, and `prewarm(promptPrefix:)`. Gate it with both `#available(iOS 26.0, *)` and `SystemLanguageModel.default.availability`, then fall back to the cloud path.

Sources: [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [generating and refining text](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models), [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession), [WWDC25: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/), [Apple Intelligence device requirements](https://support.apple.com/en-euro/121115).

## Gemma through MLX Swift

MLX Swift supports iOS and its model registry includes small Gemma variants such as Gemma 3 1B QAT 4-bit. Google positions Gemma 3/3n for mobile and edge devices. A 1-billion-parameter model quantized to four bits has a theoretical weights-only floor near 0.5 GB, with additional storage and memory needed for the tokenizer, runtime, activations, and KV cache. Cold loading and first-token time must be measured on the physical iPhone 15 before making any product claim.

The decisive problem is BuddyGrammar's current lifecycle: the user returns to Telegram or another host app while BuddyGrammar continues STT and polishing in the background. MLX uses Metal, and Apple documents that iOS prevents applications from committing new Metal work after moving to the background. A Gemma/MLX polisher is therefore not a reliable default for the current Dynamic Island workflow. It can be prototyped as an optional downloaded provider when BuddyGrammar remains foreground, but it needs model-download UX, storage and memory management, thermal testing, cancellation, and a cloud fallback.

Sources: [MLX Swift](https://github.com/ml-explore/mlx-swift), [Gemma 3n overview](https://ai.google.dev/gemma/docs/gemma-3n), [Gemma 3n model card](https://ai.google.dev/gemma/docs/gemma-3n/model_card), [Preparing a Metal app to run in the background](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background), [Extending background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time).

## Recommended architecture

Introduce a `TextPolisher` provider boundary:

1. Use Apple Foundation Models on iOS 26 when the system model reports `.available`.
2. Use a fast cloud copyediting provider as the universal fallback and as the default on the regular iPhone 15.
3. Keep Gemma/MLX as an experimental, explicitly downloaded, foreground-only provider until real-device benchmarks and background lifecycle tests prove otherwise.

For the immediate latency fix, optimize the cloud path: benchmark a smaller low-latency model, shorten the prompt, cap output tokens based on input length, warm the correction connection when recording starts, and use a short correction deadline with an immediate raw-transcript fallback. If the insertion workflow permits it, return the raw transcript first and replace it with the polished result asynchronously.
