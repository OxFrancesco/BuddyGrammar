# Mobile-keyboard roadmap implementation status

_Implementation date: 2026-07-21. This document records the engineering pass
that followed the competitive research; the original reports remain the
historical baseline._

## Outcome

The P0–P2 roadmap is implemented as a cross-platform product contract rather
than disconnected UI features. Swift/UIKit/SwiftUI and Kotlin/Compose remain
native, while generated layouts, ranked language assets, capability decisions,
correction lifecycles, and deterministic input traces share one versioned
source of truth.

## P0 — safety and correction trust

- One field/session capability policy gates context reads, composition,
  suggestions, learning, automatic correction, swipe, Buddy cloud actions,
  handwriting, voice, saved transcript insertion, Android clipboard insertion,
  and cursor movement. Secure, structured, code, search, OTP, and editor-disabled
  fields have explicit outcomes and explanatory UI states.
- Automatic spelling, shortcut, tap-lattice, and selected swipe-alternate
  corrections create short-lived receipts. Immediate Backspace and the visible
  literal-word action restore the original, preserve exact field and language
  ownership, reject stale context, defer positive learning, and record bounded
  negative evidence on revert. Add-to-dictionary and explicit never-suggest are
  available for correction candidates.
- Every rendered candidate is owned by field epoch, language, stable candidate
  identifier, and the exact context that produced it. Acceptance is a
  compare-and-swap operation; truncated word starts, a missing non-word
  predecessor, changed context, and stale slots all fail closed rather than
  replacing adjacent text.
- Buddy Fix/Rewrite is an explicit, cancellable proposal transaction with
  intent, bounded scope, changed-span preview, accept/dismiss, stale-result
  rejection, and whole-operation undo. Its bounded cloud snapshot preserves
  grapheme boundaries at UTF-16 limits, rechecks capability before dispatch,
  and refuses ambiguous or unreadable selections.
- The iOS keyboard no longer tries to open the containing app or access a
  microphone. It explains Apple Dictation; Buddy recording remains visibly
  user-started in the containing app. Android voice is an owned
  `SpeechRecognizer` request with first-use privacy disclosure and stale
  callback rejection.
- Extension privacy declarations cover extension-originated user content, and
  automatic transcript copying is off by default behind a separate preference.

## P1 — daily keyboard baseline

- A single-pointer interaction router arbitrates literal taps, previews,
  accents, swipe, stationary Space hold, Space scrub, delete repeat,
  cancellation, haptics/sound, and accessibility activation. Gesture-only
  editing also has visible/accessibility actions.
- Character deletion is grapheme-safe; the visible and accessibility word-delete
  action removes one whitespace run, one word run, or one punctuation/emoji
  grapheme without crossing a bounded/truncated context edge.
- Visible variants cover ordinary, multiline, literal/no-suggestions, email,
  URL, number, decimal, phone, date/time, search, code, OTP, and password
  editors, including return intent, locale decimal punctuation,
  capitalization, compact iPad, and wide/split Android presentation.
- Automatic capitalization distinguishes sentence/word ownership from
  user-selected Shift and Caps Lock. When surrounding text is intentionally
  unavailable, platform cursor-capitalization state still supports names and
  sentence starts without attempting a private context read.
- Handwriting, voice, and saved-transcript insertion infer casing and spacing
  only from context the editor actually returned. An unavailable context stays
  unknown and inserts literally; it is never treated as an empty document.
- The idle strip has stable candidate slots plus one Buddy entry point. LaTeX,
  handwriting, iOS saved transcript, Android clipboard, voice/platform
  guidance, and settings live in contextual tool surfaces instead of
  permanently displacing candidates.
- Unicode emoji data is generated from the official release, with categories,
  search, recents, and tone variants on iOS; Android uses the maintained
  AndroidX picker.

## P2 — focused differentiation and quality

- English and Italian use generated ranked lexicons shared byte-for-byte by
  tap suggestions and swipe recognition. Apostrophes are normalized for
  geometry without losing display spelling, including Italian curly-apostrophe
  forms.
- Tap decoding has bounded lattices, literal/resolved anchors, ranked
  candidates, context scoring, per-language acceptance thresholds, explicit
  abstention, correction-suppression integration, and cross-platform traces.
- Swipe recognition has dwell-aware repeated letters, bounded live paths,
  confidence-based abstention, shared vocabulary/traces, and runner-up recall.
- Android personalization is bounded per key rather than one global offset;
  both platforms learn only under the capability/evidence policy and expose
  independent language/touch reset controls. Reset generations also fence
  delayed persistence, so an in-flight save cannot resurrect erased language
  or touch calibration data.
- Handwriting input is bounded. Every recognition result is owned by field
  epoch, layer, request identifier, and input revision, so Clear, new ink,
  field changes, and tool changes invalidate stale local or cloud callbacks.
- Content-free in-memory latency windows measure feedback dispatch, native
  editor commit, and swipe decoding. They retain only bounded aggregate
  p50/p95/p99 and lifecycle counters—never text, taps, or paths.

## Shared quality boundary

`shared/keyboard-contract` publishes the declarative keyboard catalog, ranked
language packs, and conformance suites for capability policy, interaction
routing, correction receipts, tap decoding, swipe dwell, and swipe recognition.
Generated native resources are checked byte-for-byte. CI validates the shared
contract, generated-data drift, Swift tests plus unsigned iOS build, and Android
unit tests, Android instrumentation-source compilation, assembly, and lint.

## Evidence still requiring real devices

The implementation and deterministic simulations can prove ownership,
staleness, bounds, privacy gates, Unicode safety, and native compilation. They
cannot honestly prove physical-keyboard feel or host-app interoperability.
Before broad release, run the documented real-editor matrix on representative
iPhones/iPads and Android phones/foldables for:

- rendered/tactile/audio p50/p95 latency and cold keyboard launch;
- host-specific cursor, selection, composition, and long-document behavior;
- VoiceOver/TalkBack focus, actions, large text, switch control, and haptics;
- Android recognizer on-device/network behavior and permission recovery;
- App Store privacy metadata/App Review plus signed extension installation;
- empirical tap/swipe accuracy, false-correction rate, revert rate, and Italian
  code-switching thresholds.

These are release-validation gates, not missing alternate code paths. No
simulator or unit suite should be presented as evidence for them.
