# BuddyGrammar shared keyboard contract

This directory is the versioned, data-only contract shared by the native iOS
and Android keyboards. It deliberately does not contain a cross-platform UI
runtime. Swift and Kotlin remain native; they consume the same catalog and
replay the same conformance traces.

## Published v1 files

- `v1/catalog.schema.json` defines the catalog's JSON Schema dialect and shape.
- `v1/catalog.json` publishes layouts, language metadata, locale aliases,
  long-press alternates, field variants, gesture thresholds, and tool data-use
  declarations.
- `v1/trace-suite.schema.json` defines the common trace-suite envelope.
- `v1/traces/capability-policy.json` is the field/privacy capability matrix.
- `v1/traces/correction-receipts.json` specifies creation, invalidation,
  Backspace restore, visible revert, deferred learning, and stale-field rules.
- `v1/traces/interaction-routing.json` specifies six synthetic pointer traces:
  literal feedback/commit, cancellation, swipe arbitration, spacebar cursor
  scrubbing, character-only delete repeat, and long-press alternates.
- `v1/traces/swipe-dwell.json` specifies repeated-letter dwell behavior for
  English and Italian swipe paths.
- `v1/traces/swipe-recognition.json` verifies that Italian accents,
  apostrophes, names, short words, code-switch terms, noisy endpoints, and
  dwell evidence produce the same display candidate on both platforms.

The v1 contract currently contains 47 conformance cases: 16 capability, 10
correction-receipt, 6 interaction-routing, 6 swipe-dwell, and 9 swipe
recognition cases.

All fixture text is synthetic. Production text, touch paths, or learned data
must never be added to these files.

## Validation

From this directory:

```sh
bun run validate
bun test
```

The validator checks catalog references and privacy invariants, then evaluates
every golden case with the platform-neutral reference semantics. It has no
third-party dependencies and is suitable for CI.

## Native integration contract

Both native targets should implement the following contract independently:

1. Bundle `v1/catalog.json` and reject an unsupported `schemaVersion` before a
   keyboard session opens. `en` / `en-qwerty` are the literal fallback.
2. Resolve locale aliases case-insensitively, trying the full language tag
   before its base language. An unrecognized locale falls back to
   `defaultLanguageId`.
3. Resolve one field variant from the native editor's normalized field kind.
   Capability policy is authoritative: catalog `suggestionMode` is a surface
   default and can never override a denied capability.
4. Use the active language's decimal separator when the selected variant has
   `usesLocaleDecimalSeparator`. Long-press output comes from that language's
   `alternates`; visible QWERTY geometry comes from its layout profile.
5. Apply the published swipe dwell thresholds in normalized key units. A run
   emits one repeated letter only when time, sample-count, and drift gates all
   pass.
6. Keep a swipe candidate's NFC display spelling separate from its geometry:
   lowercase it, normalize internal/elision apostrophes to U+2019, remove them, and fold
   diacritics to a-z only for the QWERTY path. Emit the original canonical
   display spelling.
7. Evaluate editor capabilities before requesting surrounding text. Denied
   cloud tools perform no context capture, network work, or learning.
8. Give every automatic replacement one correction receipt. Immediate
   Backspace restores the literal word and removes the triggering boundary;
   visible revert preserves that boundary. A new field or unrecognized editor
   mutation invalidates the receipt and pending learning.
9. Stamp asynchronous results with the field epoch. Results from an older
   epoch are ignored without editor mutation or learning.
10. Replay interaction traces through the production pointer router and count
   its raw feedback effects. Every key, space, or delete press dispatches one
   immediate key-feedback effect; release does not duplicate it. Cancellation
   and swipe suppress the pending literal commit but retain that press feedback.
   Delete-repeat deadlines each dispatch feedback for their repeated deletion.

The JSON traces are test fixtures, not runtime decision tables. Native code
should implement the behavior in Swift/Kotlin and run each case through its
public keyboard-session Interface using a fake editor Adapter. This keeps the
tests at the same Seam used by production while avoiding generated duplicate
controller code.

## Versioning

- Additive catalog content increments `catalogRevision` and updates every trace
  suite to the same revision.
- A breaking shape or semantic change creates a new top-level version directory
  and schema ID. Do not reinterpret v1 in place.
- Native releases may support more than one schema version during migration,
  but must use exactly one catalog revision per keyboard session.
- Fixture expectations change only with an intentional product-contract change,
  never merely to make one platform's implementation pass.
