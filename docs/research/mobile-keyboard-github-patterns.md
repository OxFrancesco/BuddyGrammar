# GitHub/open-source keyboard patterns for BuddyGrammar

_Research date: 2026-07-20. Scope: primary repositories and release histories for AOSP LatinIME, HeliBoard, FlorisBoard, AnySoftKeyboard, and FUTO Keyboard. This is architecture and failure-pattern research, not a request to copy licensed implementation code._

## Executive recommendation

Open-source keyboards reinforce the web benchmark's product conclusion: the hard part is not drawing QWERTY keys. It is maintaining a deterministic interaction state machine, a compatible editor transaction layer, versioned language/layout assets, and graceful fallbacks across thousands of editor/device combinations.

BuddyGrammar should borrow five patterns:

1. separate pointer routing, key detection, geometry/proximity, layout state, decoding, and editor actions;
2. make layouts, language metadata, dictionaries, and special planes generated data rather than duplicated Swift/Kotlin literals;
3. make all intelligence replaceable and failure-tolerant so literal typing never depends on a dictionary, model, network, or composing API;
4. use shared event traces and model corpora to keep iOS and Android behavior aligned;
5. release advanced models behind device/performance gates and keep compatibility switches for problematic editors/OS versions.

## Repository lessons at a glance

| Repository | Concrete evidence | Lesson for BuddyGrammar |
| --- | --- | --- |
| [AOSP LatinIME keyboard package](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/4f5c3a2/java/src/com/android/inputmethod/keyboard/) | Separate `PointerTracker`, `KeyDetector`, `MoreKeysDetector/Panel`, `ProximityInfo`, `KeyboardSet/Switcher`, view, key model, and action listener | Use an explicit input pipeline instead of accumulating gestures and policies inside key views/services |
| [HeliBoard](https://github.com/HeliBorg/HeliBoard) | Offline core, importable text/JSON layouts, separate dictionaries, multilingual typing, one-handed/split modes, backup/restore; glide needs a separate library | Treat layouts/languages/personal data as portable artifacts; keep optional engines replaceable |
| [FlorisBoard](https://github.com/florisboard/florisboard) | Extension/add-on architecture, clipboard/theming/emoji shipped, while word suggestions remain a major unfinished milestone in current releases | Modular UI is useful, but high-quality prediction is a separate multi-year product—protect BuddyGrammar's working local core |
| [AnySoftKeyboard](https://github.com/AnySoftKeyboard/AnySoftKeyboard) | External language packs can mix layout and suggestion languages; explicit numeric/email/URI layouts; configurable correction; incognito; no internet permission | Package language assets independently and make privacy/field behavior first-class state |
| [FUTO Keyboard releases](https://github.com/futo-org/android-keyboard/releases) | Lower-end transformer cost, large model assets, composing disabled on older Android for long-document performance, many dictionary/swipe/locale fixes | Benchmark the full system, gate heavy models, and maintain editor/OS compatibility fallbacks |

## 1. Use a real interaction pipeline

The AOSP LatinIME tree is unusually instructive because its package boundaries name the responsibilities a production keyboard accumulates:

- `PointerTracker` owns pointer lifecycle rather than leaving it to each key;
- `KeyDetector` and `ProximityInfo` translate coordinates into candidates;
- `MoreKeysDetector` and `MoreKeysPanel` handle alternates as a distinct interaction;
- `KeyboardSet` and `KeyboardSwitcher` own layout/mode state;
- `KeyboardActionListener` separates detected actions from editor effects;
- `SuddenJumpingTouchEventHandler` isolates a device/touch anomaly instead of contaminating decoding code.

BuddyGrammar currently has useful platform-native shells, but gesture responsibility is distributed between SwiftUI key gestures, a layer-level swipe gesture, Compose per-key pointer capture, delete handling, and service/model methods. Adding spacebar cursor movement, accents, delete gestures, and previews directly to those views will create precedence bugs.

Recommended boundaries:

```text
PointerRouter
  -> InteractionStateMachine
       tap | swipe | hold | alternate | cursor | deleteRepeat | cancel
  -> Geometry/KeyDetector
  -> CompositionSession
  -> Decoder/Ranker
  -> EditorPolicyGate
  -> NativeEditorAdapter
```

The router owns pointer identity, movement threshold, dwell, cancellation, gesture precedence, and feedback. Accessibility invokes semantic actions at the state-machine boundary and remains literal. The decoder never decides whether cloud, learning, or editor mutation is allowed.

## 2. Make layouts and languages data

HeliBoard documents main and special keyboard layouts as editable/shareable text files, with JSON layout tooling, while dictionaries are separately compiled and installed. Its feature list also treats multilingual typing, custom layouts, special planes, one-handed/split geometry, and dictionaries as separate axes rather than one `language` enum.

AnySoftKeyboard goes further at packaging level: external language packs supply layouts and word lists, and the README explicitly describes using one language's physical layout with suggestions from other languages. It also lists special numeric, email, and URI keyboards as normal baseline variants.

BuddyGrammar should define a versioned source schema such as:

```text
LanguagePack
  id, locale aliases, script, compatible layouts
  capitalization and spacing rules
  decimal/punctuation symbols
  alternates per key
  lexicon/dictionary inputs
  swipe vocabulary inputs
  evaluation corpora

LayoutPack
  rows, key weights, anchors, output/actions
  field variants: text, email, URL, phone, decimal
  width variants: compact, one-handed, split
  symbol/number/function planes
```

A generator should validate the source and emit Swift and Kotlin resources plus common golden fixtures. Native renderers remain native. This directly addresses BuddyGrammar's current English-QWERTY metadata, fixed literals, iOS/Android vocabulary-size gap, and adaptive-geometry drift.

Do not dynamically execute community layout logic. Parse a constrained schema, validate bounds/actions, version migrations, and fall back to a bundled known-good layout.

## 3. Treat intelligence engines as optional dependencies

HeliBoard's README says glide typing depends on a separately obtained closed-source library because a compatible open-source engine is not included. FlorisBoard's current README says word suggestions and spell checking are still a major milestone even though clipboard, theming, extensions, and emoji are mature. These are honest demonstrations that input intelligence is not a small UI feature.

BuddyGrammar already owns functioning local suggestion, spatial, tap-lattice, and swipe seams. Preserve them behind small interfaces:

```text
TapDecoder.decode(taps, context, locale) -> ranked candidates + confidence
SwipeDecoder.decode(path, context, layout, locale) -> ranked candidates + confidence
SuggestionProvider.suggest(composition, context, policy) -> stable candidates
Personalizer.observe(explicit outcome) -> aggregate update
```

Every interface must support `unavailable`, timeout, corrupt asset, and empty-result behavior. The fallback is literal text with no lost input. A failed dictionary must not disable space, delete, or composition; a cold swipe model must not delay tap commit; a network rewrite must not own the suggestion strip until it returns.

## 4. Copy failure lessons, not just features

FUTO's release history is valuable precisely because it records production costs:

- transformer language-model work can still hurt lower-end devices under load;
- voice and language models dominate package size even when the core keyboard is small;
- composing changes were disabled on Android 11 and below after severe performance problems in long documents;
- dictionary, personal-word, locale-spacing, and swipe regressions repeatedly affect ordinary typing;
- emoji suggestions for short words were removed because they were noisy;
- English QWERTY can receive a stronger swipe model than other languages, which makes per-language capability disclosure necessary.

BuddyGrammar implications:

- maintain a literal/no-composition compatibility mode per OS/editor family;
- cap all surrounding-text reads, tap lattices, swipe paths, beam widths, and candidate lists;
- warm heavy assets off the keypress path and expose readiness separately;
- benchmark cold start, memory, thermal/load, long documents, and low-end Android—not only candidate accuracy;
- version dictionaries/models atomically and retain a known-good rollback/fallback asset;
- show capability per language rather than implying uniform quality;
- use feature flags for decoder/model rollout, with local deterministic fallback.

## 5. Separate core, packs, personalization, and tools

The open-source projects suggest four lifecycles that should not be coupled:

1. **Core keyboard:** interaction state, editor adapters, deterministic literal behavior, common correction contract.
2. **Language/layout assets:** generated, versioned, testable, independently updateable.
3. **Personal data:** local aggregates, learned words, settings, export/reset/backup rules.
4. **Advanced tools:** handwriting, voice, LaTeX, clipboard/snippets, cloud writing help.

This lets a broken tool disappear without destabilizing typing, a language pack update without migrating touch state, and a user reset learned words without erasing layout preferences.

AnySoftKeyboard's incognito mode and HeliBoard's offline posture also show that privacy is clearer when it is structural: learning/history can be switched off independently, and basic operation does not have an internet dependency. BuddyGrammar can retain optional cloud writing help while enforcing the same structural separation.

## 6. Build conformance from events, not screenshots

Snapshot/UI tests are insufficient for a keyboard. The important contract is a sequence:

```text
field traits -> pointer events -> detected action -> composition state
-> ranked candidates -> policy decision -> editor mutations -> undo/revert
```

Create platform-neutral fixtures containing:

- layout and locale;
- editor traits/capabilities;
- raw normalized pointer sequence or semantic accessibility action;
- context before/after and cursor/selection state;
- expected committed literal text;
- allowed correction candidates and abstention;
- expected editor operations and correction receipt;
- whether learning/telemetry/cloud is allowed.

Run the same fixtures through Swift and Kotlin implementations. Scores may differ within documented tolerance; editor actions, privacy gates, literal anchors, and revert behavior should not.

Also maintain replay corpora for swipe and tap decoding. FUTO reports a public dataset effort exceeding one million swipes before its newer swipe model became competitive; six synthetic words can validate math but cannot validate a shipping gesture keyboard. BuddyGrammar needs recorded representative paths, names/OOVs, repeated letters, short words, noisy endpoints, and each supported language/layout.

## Recommended sequence

1. Extract the editor capability/policy object and correction receipt.
2. Introduce the interaction router/state machine before adding cursor, accents, or more gestures.
3. Define and generate field/layout/language assets for both platforms.
4. Unify vocabulary inputs and add cross-platform event/replay fixtures.
5. Add model/asset health and deterministic fallbacks.
6. Gate swipe/model changes by device/language performance and quality data.
7. Keep handwriting, voice, LaTeX, clipboard, and cloud rewrite as modular panels over the stable core.

## What not to copy literally

- AOSP/HeliBoard code licensing and legacy architecture require legal and technical review; copy responsibility boundaries, not source wholesale.
- Android-only editor assumptions do not transfer to `UITextDocumentProxy`.
- Community-installable layouts/dictionaries need a smaller trusted schema on iOS and careful validation everywhere.
- A giant plugin framework is unnecessary before BuddyGrammar has two or three independently shipped pack types.
- FUTO's heavy local-model tradeoffs are not automatically justified for BuddyGrammar's current correction problem.

## Source index

- [AOSP LatinIME keyboard package tree](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/4f5c3a2/java/src/com/android/inputmethod/keyboard/)
- [HeliBoard repository and feature/layout documentation](https://github.com/HeliBorg/HeliBoard)
- [HeliBoard layout format](https://github.com/HeliBorg/HeliBoard/blob/main/layouts.md)
- [FlorisBoard repository](https://github.com/florisboard/florisboard)
- [FlorisBoard language-pack documentation](https://github.com/florisboard/florisboard/blob/main/LANGUAGEPACKS.md)
- [AnySoftKeyboard repository and external packs](https://github.com/AnySoftKeyboard/AnySoftKeyboard)
- [FUTO Keyboard source mirror](https://github.com/futo-org/android-keyboard)
- [FUTO Keyboard release history](https://github.com/futo-org/android-keyboard/releases)

## Bottom line

The GitHub lesson is architectural humility: reliable keyboards accumulate specialized machinery because fingers, editors, languages, devices, and models all fail in different ways. BuddyGrammar should keep its sophisticated intelligence, but surround it with explicit state machines, generated assets, small replaceable engines, and event-level conformance. That is how the product can add quality without multiplying cross-platform surprises.
