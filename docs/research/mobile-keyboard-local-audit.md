# BuddyGrammar mobile-keyboard local audit

> Historical baseline: findings below describe the audited pre-implementation
> state. See [mobile-keyboard-implementation-status.md](mobile-keyboard-implementation-status.md)
> for the 2026-07-21 implementation and the remaining device-only release gates.

_Audit date: 2026-07-20. Scope: the current iOS keyboard extension, Android IME, shared intelligence layers, host-app handoffs, privacy declarations, and automated tests. The current working tree is the source of truth, including the uncommitted Android swipe-typing implementation. This is a read-only product/code audit; no product code was changed._

## Executive verdict

BuddyGrammar already has unusually ambitious keyboard intelligence on both platforms: anchored adaptive touch resolution, bounded whole-word beam decoding, gesture typing, local personal language models, explicit cloud correction with stale-context guards, handwriting, dictation, LaTeX, emoji, and adaptive practice. The core is not a prototype.

The product nevertheless has an inverted maturity profile. Its differentiated features are substantially further along than several interactions people exercise on every sentence:

- iOS does not reliably auto-capitalize after sentence punctuation and a following space.
- Android delete does not repeat; neither platform offers word delete.
- Neither spacebar supports cursor/trackpad movement.
- Neither platform implements key previews, long-press accents, or keyboard haptics.
- Both platforms silently apply local boundary autocorrection without the visible one-action revert that the repository's own research requires.
- Layout and language metadata are effectively English QWERTY even when language hints are used to scope learning or recognition.

There is also material parity drift. Android has better editor-action and sentence-capitalization behavior, while iOS has repeat delete, a much larger swipe vocabulary, and materially richer per-key spatial personalization. Android has the richer system emoji picker. The two implementations share concepts but not a conformance contract, common test corpus, or common vocabulary artifact.

The highest-risk finding is not cosmetic: dictionary suggestions and learning are disabled in structured fields, but the star correction action bypasses that policy on both platforms. An email, URL, or person-name field can therefore still send selected text or the current sentence to the cloud after consent. Separately, the shipping iOS microphone-ready/deep-link flow directly conflicts with this repository's existing Apple-platform research.

## 1. Current architecture

| Area | iOS | Android | Audit assessment |
|---|---|---|---|
| Keyboard shell | `UIInputViewController` embeds one SwiftUI `KeyboardRootView`; the controller owns document-proxy operations and the model owns behavior (`BuddyGrammarKeyboard/KeyboardViewController.swift:25-73`, `BuddyGrammarKeyboard/KeyboardRootView.swift:29-64`) | `InputMethodService` hosts a Compose `KeyboardScreen` (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:170-181`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:109-139`) | Sensible platform-native shells; most logic remains testable outside the view. |
| Modes | Letters, numbers, symbols, LaTeX, emoji, handwriting (`BuddyGrammarKeyboard/KeyboardModel.swift:12-19`) | The same plus an in-IME voice layer (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardState.kt:8-16`) | Feature breadth is strong. iOS dictation necessarily crosses into the containing app. |
| Tap intelligence | Per-key aggregate offsets and confusion counts, central literal anchors, context/lexicon priors (`BuddyGrammarKit/Sources/BuddyGrammarKit/TypingIntelligence.swift:158-178`, `BuddyGrammarKit/Sources/BuddyGrammarKit/TypingIntelligence.swift:273-403`) | One global mean X/Y calibration plus four hard-coded English prefix-prior entries (`android/app/src/main/java/com/francescooddo/buddygrammar/core/adaptive/TypingIntelligence.kt:65-187`, `android/app/src/main/java/com/francescooddo/buddygrammar/core/adaptive/TypingIntelligence.kt:268-282`) | Same product label, substantially different behavior and learning resolution. |
| Whole-word decoding | Bounded 32-tap, five-candidate, beam-48 decoder retaining literal/resolved paths (`BuddyGrammarKit/Sources/BuddyGrammarKit/TapWordDecoder.swift:83-105`, `BuddyGrammarKit/Sources/BuddyGrammarKit/TapWordDecoder.swift:131-220`) | Equivalent bounded tap lattice and correction thresholds are integrated at word boundaries (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:846-876`) | This is a real strength; keep it deterministic and benchmark it. |
| Personal language | On-device language-scoped unigram/bigram/trigram model with caps, decay, rejection, persistence, and reset (`BuddyGrammarKit/Sources/BuddyGrammarKit/PersonalLanguageModel.swift:3-9`, `BuddyGrammarKit/Sources/BuddyGrammarKit/PersonalLanguageModel.swift:267-415`) | On-device language-scoped unigram/bigram/trigram model with rejection, caps, decay, persistence, and reset (`android/app/src/main/java/com/francescooddo/buddygrammar/core/PersonalLanguageModel.kt:3-9`, `android/app/src/main/java/com/francescooddo/buddygrammar/core/PersonalLanguageModel.kt:36-215`) | Good privacy-preserving foundation. |
| Cloud correction | Extension captures a bounded selection/current sentence, sends it only after Full Access and consent, and applies only to an exact document snapshot (`BuddyGrammarKeyboard/KeyboardViewController.swift:224-306`, `BuddyGrammarKeyboard/KeyboardModel.swift:1066-1144`) | IME captures a bounded selection/current sentence, anchors the surrounding context, and rejects stale application (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:575-639`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:641-715`) | Snapshot and stale-context design is strong; field gating is incomplete. |

### iOS typing flow

The visible QWERTY key converts the physical touch into normalized key-space and sends it to `insertLetter` (`BuddyGrammarKeyboard/KeyboardRootView.swift:586-625`, `BuddyGrammarKeyboard/KeyboardRootView.swift:339-386`). The model then:

1. resolves the ambiguous touch through the adaptive spatial model;
2. records the small per-tap candidate lattice;
3. commits the selected character immediately;
4. decodes/corrects the whole word only when punctuation, space, or return closes it;
5. learns the committed word locally when the field policy permits it (`BuddyGrammarKeyboard/KeyboardModel.swift:369-420`, `BuddyGrammarKeyboard/KeyboardModel.swift:924-966`).

Accessibility activation intentionally bypasses ambiguous touch resolution and commits the named key literally (`BuddyGrammarKeyboard/KeyboardModel.swift:422-439`). That is exactly the right principle for VoiceOver.

### Android typing flow

Each Compose letter key captures either a tap or a swipe path while preserving a semantic click for accessibility (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:587-653`). The service resolves taps, accumulates lattice alternatives, commits characters, and performs local word correction at a boundary (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:332-417`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:846-876`). New editor sessions derive language, safety, learning, numeric-layer, shift, and return-action state from `EditorInfo` (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:186-211`).

## 2. What is already strong

### Local intelligence remains local

iOS limits the touch decoder's text context to 96 characters and persists only aggregate key offsets/confusions, not readable tap or sentence history (`BuddyGrammarKit/Sources/BuddyGrammarKit/TypingIntelligence.swift:28-39`, `BuddyGrammarKit/Sources/BuddyGrammarKit/TypingIntelligence.swift:158-178`). Android's persisted spatial profile is even smaller: observation count plus mean X/Y offset (`android/app/src/main/java/com/francescooddo/buddygrammar/core/adaptive/TypingIntelligence.kt:65-75`). Both personal language models are local and resettable.

The local suggestion seam on iOS combines personal vocabulary, the bundled frequency lexicon, UIKit spelling/completion sources, next-word prediction, the tap lattice, and emoji, then caps the visible strip at three candidates (`BuddyGrammarKit/Sources/BuddyGrammarKit/TextIntelligence.swift:21-115`, `BuddyGrammarKeyboard/KeyboardModel.swift:777-800`). Android similarly blends a local personal model, static completions/bigrams, correction, and emoji into three slots (`android/app/src/main/java/com/francescooddo/buddygrammar/core/SuggestionEngine.kt:164-182`, `android/app/src/main/java/com/francescooddo/buddygrammar/core/SuggestionEngine.kt:190-303`).

### Correction application is conservative

Both platforms minimize the explicit star request to selected text or the current sentence, then verify that the editor context has not changed before replacing anything. iOS includes document identity and a generation counter (`BuddyGrammarKeyboard/KeyboardViewController.swift:224-306`); Android uses exact before/after anchors (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:641-715`).

Star correction also has an exact-context undo and defers personal-language learning until the undo window closes on both platforms (`BuddyGrammarKeyboard/KeyboardModel.swift:1109-1134`, `BuddyGrammarKeyboard/KeyboardModel.swift:1365-1400`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:717-745`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:934-964`). The cloud client enforces an eight-second application timeout and rejects empty, prefixed, or implausibly long model output (`BuddyGrammarKit/Sources/BuddyGrammarKit/OpenRouterCorrectionClient.swift:26-108`, `BuddyGrammarKit/Sources/BuddyGrammarKit/OpenRouterCorrectionClient.swift:119-148`).

### Specialized input is meaningful, not decorative

- Both keyboards implement a SHARK²-style recognizer that mixes location, shape, endpoint, frequency, and previous-word signals. iOS uses a 7,999-line bundled vocabulary (`BuddyGrammarKit/Sources/BuddyGrammarKit/SwipeTypingEngine.swift:41-99`, `BuddyGrammarKit/Sources/BuddyGrammarKit/SwipeTypingEngine.swift:112-160`); the current Android worktree implements the same scoring family (`android/app/src/main/java/com/francescooddo/buddygrammar/core/SwipeTypingEngine.kt:28-117`).
- iOS handwriting first uses Vision text recognition and asks the cloud only when candidates are empty or confidence is below 0.65 (`BuddyGrammarKeyboard/HandwritingKeyboardView.swift:73-116`, `BuddyGrammarKeyboard/HandwritingKeyboardView.swift:176-225`). Android uses ML Kit Digital Ink and falls back to a normalized PNG only after local failure/empty candidates (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/HandwritingController.kt:106-224`).
- Android uses AndroidX's maintained emoji picker (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:942-970`). iOS supplies eight emoji categories and recents (`BuddyGrammarKeyboard/EmojiKeyboardView.swift:10-87`, `BuddyGrammarKeyboard/EmojiKeyboardView.swift:89-205`).
- Both platforms expose a useful domain-specific LaTeX layer rather than burying symbols in a generic page; the iOS commands illustrate its depth (`BuddyGrammarKeyboard/LatexKeyboardView.swift:10-54`, `BuddyGrammarKeyboard/LatexKeyboardView.swift:56-141`).
- Android adapts to wide/foldable windows with a split layout (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardLayoutPolicy.kt:3-80`). iOS adjusts keyboard height for phone landscape and iPad (`BuddyGrammarKeyboard/KeyboardViewController.swift:106-118`).

## 3. Everyday interaction and parity audit

These basics should be treated as product correctness, not polish.

| Capability | iOS current behavior | Android current behavior | Recommendation |
|---|---|---|---|
| Auto-capitalization | Starts uppercase, drops shift after one letter, and restores uppercase after return. Space does not inspect sentence context, so `Hello. ` does not reliably re-enable shift (`BuddyGrammarKeyboard/KeyboardModel.swift:240-241`, `BuddyGrammarKeyboard/KeyboardModel.swift:343-365`, `BuddyGrammarKeyboard/KeyboardModel.swift:441-461`) | Recomputes sentence-start shift from text before the cursor after refresh (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardState.kt:62-65`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:980-1000`) | Bring iOS to parity and honor platform capitalization traits on both platforms. |
| Delete repeat | Letter layer repeats after 450 ms and accelerates from 110 ms to 45 ms (`BuddyGrammarKeyboard/KeyboardRootView.swift:515-563`) | One Compose click deletes one code point (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:474-482`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:432-445`) | Add Android repeat immediately; use code-point/grapheme-safe deletion. |
| Word delete | No word-delete gesture/action in the delete key path | No word-delete gesture/action in the delete key path | Add a discoverable long-hold acceleration or swipe-left delete that graduates from character to word without making a normal hold destructive. |
| Spacebar cursor control | Space is a plain button (`BuddyGrammarKeyboard/KeyboardRootView.swift:704-710`) | Space is a plain `Surface(onClick)` (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:433-452`) | Add horizontal cursor movement with activation threshold, visual state, selection/accessibility handling, and host-editor fallbacks. |
| Key previews | Pressed color only; no enlarged preview (`BuddyGrammarKeyboard/KeyboardRootView.swift:586-625`) | Static key surface during pointer capture; no preview (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:587-653`) | Add optional pop-up previews, especially because invisible hit adaptation can otherwise feel mysterious. |
| Haptics/audio | Repository-wide keyboard search found no `UIFeedbackGenerator`, SwiftUI sensory feedback, Compose `HapticFeedback`, or IME haptic call; key implementations only update visual state | Same | Add low-latency, system-respecting haptics for tap, delete-repeat start, shift/caps, swipe commit, mode change, correction, and errors; expose an off switch. |
| Long-press accents | Fixed ASCII QWERTY rows and no alternate-key interaction (`BuddyGrammarKeyboard/KeyboardRootView.swift:781-800`) | Fixed ASCII QWERTY rows and tap/swipe gesture only (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:497-553`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:587-653`) | Add locale-aware accent/alternate popovers with directional selection and TalkBack/VoiceOver actions. |
| Per-field layouts | Text traits gate correction/learning, but visible keys remain manually selected QWERTY/symbol pages and return is always generic (`BuddyGrammarKeyboard/KeyboardViewController.swift:134-178`, `BuddyGrammarKeyboard/KeyboardRootView.swift:42-55`, `BuddyGrammarKeyboard/KeyboardRootView.swift:712-720`) | Number/phone/date classes start on the same generic numeric page; return icon/action adapts (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:201-206`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:455-471`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:667-710`) | Add URL/email `@`/`.`/`.com`, decimal separator, phone, date/time, and field-specific return layouts. Android is a useful starting point, not the finish. |
| Local correction revert | Boundary autocorrection directly deletes/replaces the word; only star correction creates the visible Undo state (`BuddyGrammarKeyboard/KeyboardModel.swift:924-1000`, `BuddyGrammarKeyboard/KeyboardRootView.swift:72-81`) | Same: boundary correction directly replaces; UI semantics explicitly call its undo “Undo star correction” (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:846-876`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:180-205`) | Briefly mark every automatic replacement and make immediate backspace/tap restore the literal word and train a negative signal. |
| Return action | Always inserts newline and shows generic Return (`BuddyGrammarKeyboard/KeyboardModel.swift:451-461`, `BuddyGrammarKeyboard/KeyboardRootView.swift:712-720`) | Shows Search/Send/Go/Next/Done and invokes the editor action before newline fallback (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:455-471`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:447-461`) | Bring iOS to platform parity via proxy traits where available. |
| Emoji | Curated static catalog and recents, but no search, skin-tone variant chooser, or current Unicode data source (`BuddyGrammarKeyboard/EmojiKeyboardView.swift:10-87`) | Maintained AndroidX picker (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:942-970`) | Prefer an updateable Unicode data source on iOS; add search and variants. |

The repository's own research already specifies temporary marking plus one-action revert for high-confidence autocorrection, field-aware punctuation/learning, optional key previews and haptics, and configurable repeat behavior (`docs/research/smart-keyboard-adaptive-practice.md:80-87`, `docs/research/smart-keyboard-adaptive-practice.md:298-308`, `docs/research/smart-keyboard-adaptive-practice.md:332-375`). The current implementation has delivered much of the decoder but not these trust and interaction requirements.

## 4. Language and cross-platform quality drift

### The keyboards are locale-aware internally but not multilingual externally

iOS declares `en-US` and ASCII capability in extension metadata while the controller changes `primaryLanguage` to the first preferred locale (`BuddyGrammarKeyboard/Info.plist:23-39`, `BuddyGrammarKeyboard/KeyboardViewController.swift:33-36`). Android declares only one `en-US` subtype (`android/app/src/main/res/xml/input_method.xml:2-10`). Both visible letter layouts remain fixed ASCII QWERTY.

This creates a misleading middle state:

- personal models and handwriting can be language-scoped;
- non-English language hints disable some English priors;
- users still cannot type diacritics naturally, choose a matching layout, or explicitly switch enabled languages;
- Italian and other morphologically rich languages are forced through fixed word vocabularies and plain Latin keys.

Do not market this as multilingual keyboard support until layout, diacritics, punctuation, autocapitalization, lexicon, and evaluation all agree on the locale.

### Swipe quality differs by more than the UI suggests

The Android engine defaults to the 1,800-entry `WordList` (`android/app/src/main/java/com/francescooddo/buddygrammar/core/SwipeTypingEngine.kt:35-66`), while iOS loads a dedicated 7,999-entry swipe resource and can add supplementary lexicon replacements (`BuddyGrammarKit/Sources/BuddyGrammarKit/SwipeTypingEngine.swift:63-99`, `BuddyGrammarKeyboard/KeyboardModel.swift:650-656`). The algorithms look intentionally parallel, but candidate coverage will not be.

Use one generated, versioned vocabulary/corpus pipeline for both platforms, with platform-specific build output. Evaluate top-1/top-3 recognition on the same recorded key-space paths, including names, contractions, repeated letters, short words, Italian, code-switching, and noisy endpoints.

### “Adaptive typing” currently means different things

iOS stores per-key means and confusion counts and shrinks each key's personal offset toward a population prior (`BuddyGrammarKit/Sources/BuddyGrammarKit/TypingIntelligence.swift:158-190`, `BuddyGrammarKit/Sources/BuddyGrammarKit/TypingIntelligence.swift:342-361`). Android stores only a single global mean X/Y offset and applies it after a minimum observation count (`android/app/src/main/java/com/francescooddo/buddygrammar/core/adaptive/TypingIntelligence.kt:65-120`). A user who consistently misses `q` differently from `p`, or has row-specific motor bias, can be modeled on iOS but not Android.

Define behavioral parity tests rather than requiring identical source. At minimum both should promise:

- a central literal anchor;
- bounded per-key or per-region adaptation;
- no learning in sensitive/no-personalization fields;
- explicit positive and negative evidence only;
- resettable local aggregates;
- identical confidence/revert semantics.

## 5. Privacy, safety, and platform findings

### P0: star correction bypasses structured-field policy on both platforms

iOS correctly classifies URL, email, phone, name, username, password, one-time-code, and credit-card inputs as unsafe for automatic correction and learning (`BuddyGrammarKeyboard/KeyboardViewController.swift:134-178`). Suggestions honor that decision (`BuddyGrammarKeyboard/KeyboardModel.swift:777-782`). However, the always-visible star button calls `correctCurrentText`, whose guards cover only Full Access and cloud consent before asking the controller for a snapshot (`BuddyGrammarKeyboard/KeyboardRootView.swift:147-162`, `BuddyGrammarKeyboard/KeyboardModel.swift:1066-1085`). `captureCorrectionSnapshot` does not re-check the safety policy (`BuddyGrammarKeyboard/KeyboardViewController.swift:224-267`).

Android similarly disables dictionary intelligence for email, URI, person-name, password, and `NO_SUGGESTIONS` fields (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/EditorSuggestionPolicy.kt:5-22`), but star correction checks only the narrower password-style `secureField` plus consent (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:575-587`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/BuddyGrammarImeService.kt:1110-1119`).

Therefore a user can explicitly send an email address, URL, or identity field to OpenRouter even though local suggestions are suppressed there. Explicit consent makes the network action intentional in a general text field, but the mismatch violates the safety model the rest of the keyboard communicates. Use a single editor capability object for **suggest**, **learn**, **auto-correct**, **star**, **handwriting cloud fallback**, **voice**, and **transcript insertion**; hide or disable each control with an exact explanation. Test every supported input type.

### P0: iOS dictation implementation conflicts with the repository's Apple research

The current containing app keeps an `AVAudioEngine` input session active, publishes a Live Activity/heartbeat, and waits for the keyboard's request (`BuddyGrammarIOS/App/DynamicIslandDictationController.swift:29-84`, `BuddyGrammarIOS/App/DynamicIslandDictationController.swift:174-185`). If the companion is not alive, the keyboard invokes `extensionContext.open`, then falls back to a dynamic responder-chain `openURL:` selector (`BuddyGrammarKeyboard/KeyboardModel.swift:1210-1257`, `BuddyGrammarKeyboard/KeyboardViewController.swift:190-221`).

The repository's completed Apple research says Full Access does not grant microphone access, custom keyboards have no supported containing-app round trip, guideline 4.4.1 disallows launching another app except Settings, and the responder-chain dependency should be removed (`docs/research/apple-keyboard-workarounds.md:39-68`). It recommends Apple-owned Dictation plus explicit polish as the safest same-field shipping path and treating a BuddyGrammar recording session as an honest, user-started containing-app feature (`docs/research/apple-keyboard-workarounds.md:174-181`).

This is a release/compliance decision, not merely engineering cleanup. Either align shipping code with that recommendation or obtain current written Apple clarification and device/App Review evidence before depending on this flow.

### Android voice needs a distinct privacy control story

The Android voice layer wraps `SpeechRecognizer`, requests partial results, and can report network errors (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/VoiceTypingController.kt:15-65`, `android/app/src/main/java/com/francescooddo/buddygrammar/ime/VoiceTypingController.kt:101-136`). Its UI gates password-style secure fields, microphone permission, and recognizer availability, but not BuddyGrammar's cloud-consent setting (`android/app/src/main/java/com/francescooddo/buddygrammar/ime/KeyboardUi.kt:1099-1172`). The settings copy says cloud processing is required for star and ElevenLabs, while the privacy page separately discloses Android speech recognition (`android/app/src/main/java/com/francescooddo/buddygrammar/ui/BuddyGrammarApp.kt:604-608`, `android/app/src/main/java/com/francescooddo/buddygrammar/ui/BuddyGrammarApp.kt:1039-1046`).

That may be intentional because `SpeechRecognizer` is a platform service rather than BuddyGrammar's worker, but its processing location depends on the installed recognizer. Make the distinction explicit at first use and offer a separate “Android speech recognition” control if cloud consent is meant to be comprehensive.

### Privacy declarations and retained copies need a release audit

The keyboard extension's privacy manifest declares no collected data, while its code can send correction text and handwriting images; the containing app's manifest declares audio and other user content (`BuddyGrammarKeyboard/PrivacyInfo.xcprivacy:5-19`, `BuddyGrammarIOS/Support/PrivacyInfo.xcprivacy:16-44`). This may aggregate correctly at submission time, but the target-level mismatch deserves an App Store privacy-manifest review rather than assumption.

iOS stores settings, an installation identifier, saved dictation, session state, and pending transcript in App Group `UserDefaults`; the pending keyboard copy expires after 24 hours (`BuddyGrammarKit/Sources/BuddyGrammarKit/SharedPreferences.swift:3-28`, `BuddyGrammarKit/Sources/BuddyGrammarKit/SharedPreferences.swift:38-58`). Both host apps also automatically copy finished dictation to the system clipboard (`BuddyGrammarIOS/App/IOSAppModel.swift:383-406`, `BuddyGrammarIOS/App/IOSAppModel.swift:597-599`, `android/app/src/main/java/com/francescooddo/buddygrammar/ui/BuddyGrammarAppState.kt:362-381`, `android/app/src/main/java/com/francescooddo/buddygrammar/ui/BuddyGrammarAppState.kt:453-455`). Clipboard copies are a wider data surface than app-private storage; make automatic copying opt-in or time-bound where platform APIs permit.

Android has a strong baseline: cleartext traffic is disabled, the IME is protected by `BIND_INPUT_METHOD`, app backup is disabled, and every backup/data-transfer domain is excluded (`android/app/src/main/AndroidManifest.xml:4-39`, `android/app/src/main/res/xml/backup_rules.xml:1-8`, `android/app/src/main/res/xml/data_extraction_rules.xml:1-16`). Preserve that posture.

## 6. Test and evaluation gaps

The repository currently contains 136 Swift test declarations across the package/app/UI test trees and 122 Android JVM `@Test` declarations. Coverage is strongest in pure logic: language models, adaptive state, tap decoding, swipe scoring, correction guards, persistence, text extraction, and formatting.

Verification on the audited working tree passed: `swift test` executed 123 package tests with zero failures (two opt-in live-service checks skipped), and a forced `testDebugUnitTest` rerun executed all 122 Android JVM tests with zero failures. Android required Android Studio's bundled JDK because the host's OpenJDK 26 is newer than this Gradle toolchain accepts.

The gap is real-editor behavior:

- The two iOS tests that exercise the signed keyboard's star and dictation flows are compilation-gated and skipped unless `KEYBOARD_E2E` is enabled (`BuddyGrammarIOSUITests/BuddyGrammarIOSUITests.swift:127-133`, `BuddyGrammarIOSUITests/BuddyGrammarIOSUITests.swift:214-219`). The star path at least validates exact undo when enabled (`BuddyGrammarIOSUITests/BuddyGrammarIOSUITests.swift:189-208`).
- Android has one instrumentation test, and it renders host-app onboarding rather than instantiating the IME in a real editor (`android/app/src/androidTest/java/com/francescooddo/buddygrammar/BuddyGrammarUiTest.kt:16-55`).
- The new Android swipe tests use six synthetic words and test three simple cases; they do not cover the production 1,800-word vocabulary, pointer capture, service commit, alternate replacement, or real editor behavior (`android/app/src/test/java/com/francescooddo/buddygrammar/core/SwipeTypingEngineTest.kt:7-26`).
- The Android structured-field policy has unit tests, but no integration test proves that every cloud affordance obeys it (`android/app/src/test/java/com/francescooddo/buddygrammar/ime/EditorSuggestionPolicyTest.kt:8-35`). The same integration gap exists on iOS.

Add a shared behavioral matrix and run it against real host fields:

1. plain text, multiline, search, send, URL, email, name, phone, decimal, OTP, password, and no-suggestions/incognito;
2. empty field, after punctuation/space, mid-word cursor, selection, emoji/grapheme, RTL, and hardware keyboard;
3. tap, long press, swipe, delete hold, word delete, cursor gesture, suggestion pick, local autocorrection, immediate revert, star correction, stale result, handwriting, dictation, and field switch;
4. Full Access/consent/permission/network combinations;
5. VoiceOver/TalkBack and large accessibility text.

For model quality, retain a versioned offline benchmark with literal sequence, touch/swipe path, previous words, locale, expected top candidates, and abstention expectation. Track top-1/top-3 accuracy, false autocorrection rate, revert rate, backspaces, p50/p95 input latency, OOV coverage, and memory. The existing research already defines these gates (`docs/research/smart-keyboard-adaptive-practice.md:415-445`).

## 7. Recommended sequence

### P0 — safety and trust before broader rollout

1. **Unify editor safety policy.** One capability decision should drive suggestions, learning, automatic correction, star, handwriting cloud fallback, voice, pending transcript insertion, and control visibility. Block structured/sensitive fields conservatively and add real-editor tests.
2. **Make every automatic word replacement visible and reversible.** Immediate backspace/tap restores the literal word, records a negative signal, and suppresses the same mapping in context. Do not reserve Undo for the star feature.
3. **Resolve the iOS dictation shipping architecture.** Align code with the completed Apple-platform recommendation or obtain authoritative approval/evidence for the current microphone-ready and app-opening dependency.
4. **Audit privacy submission artifacts.** Reconcile extension/app manifests, Android recognizer disclosure, local retention, and automatic clipboard copying.

### P1 — daily keyboard baseline

5. **Ship interaction parity:** Android delete repeat, safe word delete, spacebar cursor control, optional haptics, key previews, long-press accents, and consistent pressed states on both platforms.
6. **Make editors feel native:** robust iOS auto-cap, field-specific punctuation/layout, platform return actions, decimal/locale handling, and conservative code/URL behavior.
7. **Create a parity contract:** common test vectors, thresholds, vocabulary generation, versioning, and feature flags. Keep platform-native UI while eliminating accidental algorithm/data drift.

### P2 — quality and differentiation

8. **Build real multilingual support:** explicit enabled languages, layouts, diacritics, code-switching, per-language calibration, and language-specific quality gates. Italian should be the first non-English end-to-end target.
9. **Deepen Android adaptation to per-key/region aggregates** while preserving its compact, privacy-safe representation.
10. **Modernize iOS emoji** with current Unicode data, search, variants, and parity with Android's maintained picker.
11. **Tune with evidence:** use offline replay and opt-in/local aggregate outcomes to calibrate suggestions, autocorrection, swipe, and abstention before adding a more complex model.

## Bottom line

BuddyGrammar's most defensible advantage is the combination of deterministic local typing intelligence, explicit AI polishing, specialized input modes, and privacy-preserving practice. Preserve that. The fastest improvement in perceived quality will not come from another headline mode; it will come from making every ordinary tap, space, delete, correction, field transition, and language choice behave as reliably as users expect from a daily keyboard.
