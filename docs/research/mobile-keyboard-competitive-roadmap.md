# BuddyGrammar mobile-keyboard competitive roadmap

> Historical baseline: the roadmap below describes the pre-implementation
> state. The 2026-07-21 engineering outcome and remaining real-device evidence
> are tracked in [mobile-keyboard-implementation-status.md](mobile-keyboard-implementation-status.md).

_Research date: 2026-07-20. Evidence base: the live BuddyGrammar iOS and Android worktree (including the current uncommitted Android swipe implementation), official platform and product documentation, published mobile-text-entry research, and open-source keyboard repositories._

## Executive verdict

BuddyGrammar should not add another headline input mode next.

Its intelligence layer is already unusually strong: anchored adaptive touch decoding, a whole-word tap lattice, local personal language models, gesture typing, explicit AI correction with stale-context protection, handwriting, dictation, LaTeX, emoji, and adaptive practice. The weaker part is the physical and editorial contract people exercise on every sentence: field-aware layouts, accents, cursor movement, deletion, feedback, correction undo, language selection, and consistent behavior between iOS and Android.

The product has an **inverted maturity profile**: differentiation is ahead of daily-keyboard trust. Mature keyboards and the best open-source implementations point to the same correction:

1. close the editor-safety gaps;
2. make ordinary typing immediate, familiar, and reversible;
3. establish one correction and parity contract across platforms;
4. make Buddy's writing help explicit, focused, and reviewable;
5. deepen multilingual, swipe, and personalization quality only after that foundation is measurable.

This is not a recommendation to imitate Gboard or SwiftKey feature for feature. It is a recommendation to copy their **interaction contracts**, copy the modularity visible in mature open-source keyboards, and preserve BuddyGrammar's local-first writing intelligence as the product's identity.

## The one-line product direction

> **A trustworthy daily keyboard first; a private, reviewable writing partner second; experimental input modes third.**

## Evidence boundary

- **Observed** means the behavior is present in BuddyGrammar's current working tree or documented by the cited platform/product.
- **Recommended** means this report's product or engineering inference.
- Competitor claims about their own quality are treated as product descriptions, not independent proof.
- Proposed performance gates are targets to calibrate on real devices, not claims that one universal threshold suits every device.

The supporting reports contain the detailed evidence and source links:

- [BuddyGrammar local audit](mobile-keyboard-local-audit.md)
- [Official web, product, platform, and HCI benchmark](mobile-keyboard-web-benchmarks.md)
- [GitHub/open-source architecture and failure lessons](mobile-keyboard-github-patterns.md)

## Where BuddyGrammar stands

| Area | Current position | Competitive interpretation | Priority |
| --- | --- | --- | --- |
| Adaptive tap decoding | Per-touch resolution, central literal anchors, personal aggregates, and whole-word decoding are implemented | Ahead of many young keyboards; preserve and benchmark | Protect |
| Personal language | Local, language-scoped unigram/bigram/trigram learning with rejection and reset | Strong privacy-preserving foundation | Protect |
| Explicit correction | Bounded selection/sentence capture, stale-context validation, exact undo, deferred learning | Strong implementation seam | Refine into reviewable writing help |
| Specialized input | Swipe, handwriting, LaTeX, emoji, voice/dictation, practice | Differentiated breadth | Keep modular; stop expanding for now |
| Correction trust | Local boundary autocorrection is silent and lacks immediate literal-word restore | Below mainstream expectation | P0 |
| Editor safety | Suggestions/learning are field-gated, but ★ uses a different and looser policy | Policy inconsistency with cloud-data consequences | P0 |
| iOS dictation | Current app-opening/microphone-ready flow conflicts with completed Apple research | Release/compliance decision | P0 |
| Basic editing | No spacebar cursor; no word delete; Android delete does not repeat | Below mainstream expectation | P1 |
| Key feedback | No key previews, haptics, sounds, or long-press alternates | Keyboard feels less physical and less complete | P1 |
| Field adaptation | Android partially adapts numbers and return action; iOS mostly uses one visible layout | Below platform guidance | P1 |
| Languages/layouts | Metadata and visible layout are effectively English QWERTY | Language hints are not end-to-end multilingual support | P1/P2 |
| Cross-platform parity | Similar concepts, different vocabulary, adaptation depth, editor behavior, and tests | Drift will grow without shared artifacts | P1 |
| Evaluation | Good pure-logic tests; little real-editor and cross-platform conformance coverage | Model quality cannot substitute for editor reliability | P0/P1 |

## What mature keyboards teach

### 1. Reversibility is part of speed

Apple, Gboard, SwiftKey, Grammarly, Samsung, Typewise, and Fleksy's public interfaces all treat correction rejection or undo as part of the main typing loop. SwiftKey's Flow goes further: after a flowed word, Backspace recalls alternative predictions, and a longer dwell represents a doubled letter ([SwiftKey Flow](https://support.microsoft.com/en-us/swiftkey-keyboard/what-is-flow-and-how-do-i-enable-it-with-microsoft-swiftkey-keyboard)).

This matters because an incorrect automatic change has a larger cost than its raw error count suggests. A controlled study found wrong autocorrections took roughly 5.5 seconds to repair, while restorable deletion reduced correction effort. The detailed studies are linked in the [web benchmark](mobile-keyboard-web-benchmarks.md#4-autocorrection-must-be-transparent-and-reversible).

**Recommended for BuddyGrammar:** every automatic word replacement creates a short-lived correction receipt containing the literal word, replacement, field/session identity, anchors, and learning provenance. Immediate Backspace or a visible `Undo “literal”` restores the exact original and records a negative signal. The higher-level ★ rewrite keeps its existing exact-context undo but gains a preview/diff before application.

### 2. A suggestion consumes attention even when ignored

Typing37K's 37,370-participant observational study associated autocorrection with faster entry and word prediction with slower entry. A controlled 170-person study found prediction saved keystrokes but added about two seconds per phrase. A 2025 eye-tracking study found frequent candidate checking without selection. These do not prove that predictions are bad; they show that a candidate must repay its visual and decision cost. Sources and caveats are in the [web benchmark](mobile-keyboard-web-benchmarks.md#5-suggestions-should-earn-their-visual-and-cognitive-cost).

**Recommended for BuddyGrammar:** corrections get first claim on three stable slots; completion appears only when it saves meaningful effort; generic next-word filler needs a higher value threshold. Do not move tool buttons into candidate positions or repopulate every slot while a finger is approaching.

### 3. The baseline is an interaction bundle, not a feature checkbox

Across [Apple's keyboard guide](https://support.apple.com/en-au/guide/iphone/iph3c50f96e/ios), [Gboard Help](https://support.google.com/gboard/?hl=en), and [SwiftKey Help](https://support.microsoft.com/en-us/swiftkey), users are taught a consistent set of mechanics:

- hold/scrub the spacebar for cursor control;
- hold or gesture for faster deletion;
- long-press for accents and symbols;
- see and feel key activation;
- get a layout and return action appropriate to the field;
- switch between tapping and gliding without an explicit mode switch;
- undo or reject an unwanted correction;
- manage learned words and languages.

None is a compelling differentiator in 2026. Together they determine whether someone trusts the keyboard long enough to discover BuddyGrammar's differentiators.

### 4. Multilingual behavior and physical layout are related but separate

SwiftKey can use multiple language models together while allowing different or shared layouts ([SwiftKey multilingual typing](https://support.microsoft.com/en-US/swiftkey-keyboard/how-to-use-microsoft-swiftkey-keyboard-with-more-than-one-language)). HeliBoard exposes multilingual typing, dictionaries, custom layouts, one-handed and split modes as separable facilities ([HeliBoard](https://github.com/HeliBorg/HeliBoard)).

BuddyGrammar currently passes language tags into parts of recognition and learning, but both keyboards expose fixed ASCII QWERTY and declare only an English keyboard/subtype. That is locale-aware internals, not multilingual product support.

**Recommended for BuddyGrammar:** make language packs declarative: layout, alternates, punctuation/spacing, capitalization behavior, lexicon metadata, swipe vocabulary, and evaluation corpus. Allow compatible language models to coexist on one layout, but require an explicit layout switch when alphabets or geometry differ. Italian is the best first non-English end-to-end quality gate; do not add several nominal languages before one passes the full interaction matrix.

### 5. Platform divergence is a design tool

Apple custom keyboard extensions cannot access the microphone, have limited surrounding-text/editing control, require Full Access for networking/shared writable storage, and may be replaced or blocked in sensitive contexts ([Apple custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface), [open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)). Android IMEs receive richer `EditorInfo` and `InputConnection` capabilities, but surrounding-text reads cross a potentially expensive IPC boundary and editor behavior varies ([Android IME guide](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method), [`InputConnection`](https://developer.android.com/reference/android/view/inputmethod/InputConnection)).

**Recommended for BuddyGrammar:** share behavioral contracts, layout/vocabulary assets, and test traces—not a forced identical UX or runtime. Android can own a first-class in-keyboard voice experience. iOS should favor Apple Dictation compatibility and explicit polish unless a supported containing-app flow is proven.

## The prioritized roadmap

### P0 — release safety and correction trust

#### 1. One editor-capability policy

Today, both platforms conservatively suppress dictionary suggestions and learning in structured fields, but the always-visible ★ action does not use the same policy. An explicit tap and prior cloud consent make the request intentional, but allowing email/URL/name text to take a cloud path while the rest of the keyboard calls the field unsafe is internally inconsistent.

Create one evaluated capability object per editor session:

```text
EditorCapabilities {
  fieldKind, secure, structured, codeLike, locale, returnAction,
  canSuggest, canLearn, canAutoCorrect, canUseStar,
  canUseCloudHandwriting, canUseVoice, canInsertTranscript,
  canReadContext, canMoveCursor, canUseComposition
}
```

Every feature consumes this object. Controls are hidden or disabled with an exact explanation; no feature invents a second security rule.

Acceptance evidence:

- plain, multiline, search, email, URL, name, phone, decimal, OTP, password, and no-suggestions fields have explicit expected capabilities;
- every local/cloud action is integration-tested against that matrix;
- field changes invalidate pending corrections, context, composition, and cloud results;
- sensitive fields create no learning or quality events containing content.

#### 2. Complete the automatic-correction trust loop

For local word-boundary correction:

- temporarily mark the changed word or strip state;
- show the literal/original word as the immediate revert affordance;
- make Backspace restore it before deleting characters;
- record rejection without immediately poisoning the global model;
- allow long-press `Never suggest` and `Add to dictionary` where appropriate;
- expose separate reset controls for learned words and touch calibration.

This should be the same contract for tap-lattice, spelling, swipe-alternate, and future multilingual correction. The correction source can vary; the user-facing receipt cannot.

#### 3. Resolve the iOS dictation architecture before release reliance

The current keyboard can request a containing-app microphone-ready session and fall back to an unsupported responder-chain `openURL:` route. The completed [Apple keyboard workaround research](apple-keyboard-workarounds.md) concludes that iOS 18–26 offers no public App-Store-safe keyboard-to-containing-app-to-host round trip and recommends Apple-owned Dictation plus explicit polish as the safest same-field path.

Choose one release position:

- **Recommended:** make Apple Dictation compatibility and bounded explicit polish the default; remove dependence on hidden app opening or keepalive behavior.
- Offer a BuddyGrammar recording session only as an honest, visibly active session started in the containing app.
- Treat future iOS execution-target APIs as a prototype until device, DTS, and App Review evidence exists.

#### 4. Reconcile privacy surfaces

Audit iOS target privacy manifests against extension-originated correction/handwriting traffic, distinguish Android platform speech recognition from BuddyGrammar/OpenRouter processing, and make automatic copying of completed dictation opt-in or deliberately time-bounded. Preserve the strong local-model reset and Android backup/cleartext protections already present.

### P1 — daily-keyboard baseline

#### 5. Build a unified interaction router

Both keyboards need a surface-level state machine that arbitrates tap, hold, slide, swipe typing, cursor scrub, alternate-character selection, delete repeat, accessibility activation, and cancellation. Do not keep adding overlapping recognizers to individual keys.

Behavior to ship:

- key-down visual feedback immediately;
- optional system-respecting haptic and sound;
- optional enlarged key preview;
- long-press accents/symbols with directional selection;
- Android delete repeat matching the already-accelerating iOS behavior;
- safe word-delete gesture/action with a visible/accessibility fallback;
- hold/scrub spacebar cursor movement with threshold, state feedback, cancellation, and editor fallback;
- deterministic gesture precedence documented in tests.

Accessibility activation must continue to commit the named key literally. Gesture-only functions need VoiceOver/TalkBack actions or visible controls.

#### 6. Make layouts editor- and device-aware

Build visible variants for normal text, email, URL, numeric, decimal, phone, date/time, search, send, next, done, and code/no-suggestions contexts. Honor locale decimal separators and capitalization traits. On iPad/foldables, keep keys thumb-reachable instead of stretching them; Android's current split policy is a useful start, while iOS's fixed full-width iPad surface needs a real compact/split decision.

#### 7. Simplify the top surface

The current suggestion row permanently competes with LaTeX, handwriting, transcript/dictation, and ★ controls. Recommended default:

```text
[ candidate 1 ] [ candidate 2 ] [ candidate 3 ] [ Buddy ★ ]
```

`Buddy ★` opens a compact, platform-appropriate action panel for Fix, Rewrite, Voice/Dictation guidance, Handwriting, LaTeX, Clipboard/Snippets, and settings. Pinning or reordering can be optional. Invoking a tool may replace the strip temporarily, but idle tools must not shrink or move candidates.

#### 8. Establish a cross-platform conformance contract

Keep native SwiftUI/UIKit and Compose/IME adapters. Share generated artifacts and behavior:

- declarative layout/language definitions;
- versioned lexicon and swipe-vocabulary inputs;
- correction-receipt semantics;
- editor-capability fixtures;
- recorded tap/swipe traces with expected top candidates and abstention;
- event-sequence golden tests for tap, boundary, correction, revert, field switch, cursor move, and stale result.

iOS and Android do not need byte-identical scores, but they should not silently differ in vocabulary by thousands of words, adaptation granularity, or whether a basic editor action works.

### P2 — focused differentiation

#### 9. Turn ★ into reviewable writing assistance

Preserve the current bounded-selection/current-sentence scope and stale-context checks. Improve the experience from one opaque replacement into an explicit proposal:

- intent chips such as Fix, Shorten, Clearer, Friendly, and Formal;
- original and proposal together, with changed spans highlighted;
- accept/reject per change when practical;
- whole-operation undo;
- cancellable network work that never blocks typing;
- visible local/cloud and text-scope state;
- no unrelated surrounding text when a smaller span is sufficient.

This is where BuddyGrammar should outclass generic keyboards. Ordinary autocorrection remains local, fast, and restrained; writing transformation is user-invoked and inspectable.

#### 10. Make multilingual and swipe quality measurable

After the interaction contract is stable:

- ship one complete non-English pack, then expand;
- unify iOS/Android vocabulary generation;
- add repeated-letter dwell, confidence-based abstention, and post-swipe alternative recall;
- test names, contractions, short words, code-switching, noisy starts/ends, and multiple layouts;
- keep tap and swipe seamless, as SwiftKey Flow teaches, but disable prediction-dependent paths in secure/no-suggestion fields.

#### 11. Deepen private personalization

Continue the local aggregate model. Bring Android from a single global offset toward bounded per-key or per-region aggregates; learn only from ground-truth practice, explicit choice/revert, or unambiguous stable text. Keep visible geometry fixed and retain central literal anchors. Let users reset language and touch personalization independently.

Practice remains a valuable opt-in calibration loop, not a prerequisite for using the keyboard.

## Proposed implementation architecture

Mature AOSP-derived keyboards separate pointer tracking, key detection, layout/state switching, proximity geometry, and editor actions. BuddyGrammar should use the same separation while keeping its own decoder and writing-assistance strengths:

```text
Pointer/accessibility events
        │
        ▼
Interaction router
(tap / hold / swipe / cursor / alternate / delete)
        │
        ▼
Composition session
(literal history, word boundary, correction receipt, cancellation)
        │
        ├───────────────┐
        ▼               ▼
Spatial/tap decoder   Swipe decoder
        └───────┬───────┘
                ▼
Language ranking + calibrated confidence
                │
                ▼
Editor capability/privacy gate
                │
                ▼
Native editor adapter
(UITextDocumentProxy / InputConnection)
```

Side inputs are declarative layout/language packs, local personalization aggregates, editor traits, and immutable model assets. Side outputs are privacy-safe aggregate quality events and deterministic trace fixtures. Network writing help is a separate explicit transaction; it is never on the path from key-down to text commit.

### Why this structure

- One router can resolve gesture collisions before they become platform-specific bugs.
- A composition session makes correction undo and field-switch invalidation explicit.
- The capability gate prevents each feature from inventing its own privacy rules.
- Native editor adapters embrace iOS/Android differences without duplicating product semantics.
- Generated shared artifacts prevent vocabulary/layout drift without forcing a cross-platform UI runtime.

## Quality program

### Measure the whole user cost

| Dimension | Measures |
| --- | --- |
| Hot path | cold/warm keyboard show; key-down-to-feedback; key-down-to-commit; p50/p95/p99; lost/duplicated input |
| Correction | changes per 100 words; false correction; immediate revert; delayed repair/retype; time to restore literal |
| Suggestions | impressions without use; characters and time saved; selection latency; post-selection undo; slot movement |
| Gesture | top-1/top-3; no-result/abstention; alternate recall; repeated letters; path latency; accidental swipe activation |
| Editing | cursor placement attempts/time; delete-repeat correctness; word-delete recovery; grapheme safety; host-editor failures |
| Languages | per-language and code-switch accuracy; wrong-language flips; layout/locale punctuation; OOV/name coverage |
| Privacy | forbidden actions by field; local/cloud comprehension; reset success; stale-result rejection; content-free telemetry checks |
| Accessibility | complete typing/editing/correction tasks with VoiceOver/TalkBack and gestures disabled |

### Device/editor matrix

Test real messaging, notes, email, browser search/URL, forms, phone/numeric, password/OTP, and long rich-text documents—not only BuddyGrammar's lab field. Include airplane mode, revoked permission/Full Access, cold relaunch, memory pressure, orientation/window changes, cursor-in-middle edits, emoji/graphemes, RTL, hardware keyboards, slow or missing context, and editors with broken composition behavior.

For Android, FUTO's release history is a useful warning: composing changes had to be disabled on Android 11 and below after severe long-document performance problems, transformer language models affected lower-end devices, model assets dominated app size, and dictionary failures broke core correction/swipe paths ([FUTO releases](https://github.com/futo-org/android-keyboard/releases)). Compatibility and graceful fallback are features.

### Proposed performance gates

Set device-class budgets after the baseline run, but enforce these principles immediately:

- visual feedback within the next rendered frame on the supported reference devices;
- literal commit independent of network, candidate refresh, and model warm-up;
- no unbounded decoder input, context capture, or candidate list;
- deterministic fallback when context/model/editor APIs fail;
- no raw typed text, swipe paths, or ordered tap history in analytics;
- zero forbidden cloud/learning actions in the editor-capability matrix.

### Implemented hot-path measurement boundary

The native keyboards now maintain the same process-local, content-free latency
snapshot for three production seams:

- key-down to native feedback dispatch;
- key-down to completion of the native editor-commit call;
- synchronous swipe-decoder execution, excluding context lookup and rendering.

Each metric retains 256 recent durations by default and is hard-clamped to 512.
The pairing table defaults to 32 in-flight events and is hard-clamped to 64; the
terminal-token duplicate detector defaults to 64 identifiers and is hard-clamped
to 128. Measurements longer than 60 seconds are rejected. Snapshots expose only
lifetime valid count, current window count, nearest-rank p50/p95/p99, current
in-flight count, and aggregate dropped/duplicate/lost counters. Ring eviction
increments `droppedSampleCount` because an older percentile-window sample was
discarded; cancellation and invalid/overlong durations are also dropped, while
an in-flight capacity eviction is both dropped and lost. Nothing is written to
disk or network, and no automatic diagnostic log or analytics event is emitted.

These are code-seam measurements, not claims about physical or rendered
latency. Only real-device editor-matrix runs can set and enforce device-class
budgets for frame presentation, tactile/audio actuation, host-editor visibility,
cold/warm keyboard show, OS process scheduling, and long-document IPC behavior.
Simulator/unit tests validate quantiles, bounds, pairing/cancellation, and the
aggregate-only privacy shape; they cannot validate those device-only limits.

## What not to copy

- **Do not make an alternative layout the admission price.** Typewise publicly described onboarding loss from its learning curve; keep experimental layouts optional.
- **Do not put a heavy transformer on the keypress path.** FUTO's release history shows the performance, size, battery, and compatibility burden even for an offline-first keyboard.
- **Do not turn the strip into an app launcher.** Tools should be customizable and contextual, with a quiet default.
- **Do not make basic typing server-dependent.** Network failure must remove enhancement, never letters.
- **Do not let language priors erase literal control.** Keep central anchors, the literal candidate, and confidence-based abstention.
- **Do not collect raw text to compensate for missing metrics.** Correction receipts and local aggregates are enough to learn quality signals.
- **Do not force identical platform features.** Android voice and iOS Dictation/polish can be excellent without pretending their capabilities match.
- **Do not share a runtime merely to claim reuse.** Share specifications, generated assets, fixtures, and semantics; keep the latency-critical UI native.

## Recommended order of work

1. Editor capability policy and integration matrix.
2. Local autocorrection receipt, visual state, Backspace revert, and negative learning.
3. iOS dictation release decision and privacy-manifest/retention audit.
4. Interaction router foundation; Android delete repeat; haptics/key previews.
5. Spacebar cursor, word delete, and long-press alternates with accessibility parity.
6. Field-aware layouts, return actions, auto-capitalization, and device-width modes.
7. Quiet suggestion strip plus Buddy action panel.
8. Shared layout/vocabulary generation and cross-platform golden traces.
9. Reviewable ★ writing proposals.
10. Italian end-to-end pack, swipe V2, and deeper Android personalization.

## Validation performed during this research

- `BuddyGrammarKit`: 123 test cases passed; two live cloud checks were skipped; no failures.
- Android `:app:testDebugUnitTest`: 122 tests passed under Android Studio's JDK 21; no failures or skips.
- No product code was changed by this research pass. Existing uncommitted Android work was treated as part of the audited current state and preserved.

## Bottom line

BuddyGrammar's moat is not “more buttons on a keyboard.” It is the combination of deterministic local touch/language intelligence, safe scoped editing, explicit writing help, and privacy-preserving personalization. The fastest route to a meaningfully better product is to wrap that intelligence in the boring, physical, reversible behaviors people already trust—then let ★ do something the stock keyboards do not do as clearly.
