# Generated keyboard data

## Italian swipe lexicon

The original ranked Italian core vocabulary lives at
`shared/keyboard-contract/v1/lexicons/it-core.txt`. Generate or verify the
Android raw-resource copy without consulting third-party keyboard dictionaries:

```sh
bun scripts/sync-swipe-lexicons.ts
bun scripts/sync-swipe-lexicons.ts --check
```

## Shared keyboard conformance fixtures

The published keyboard contract is copied byte-for-byte into the Swift and
Android test bundles so native conformance tests are hermetic. Regenerate the
copies after intentionally changing any v1 catalog or trace:

```sh
bun scripts/sync-keyboard-contract-fixtures.ts
bun scripts/sync-keyboard-contract-fixtures.ts --check
```

The shared contract's Bun test also fails if a native copy drifts.

## Unicode emoji catalog

`generate-emoji-catalog.ts` downloads Unicode's official
[`emoji-test.txt`](https://www.unicode.org/Public/UCD/latest/emoji/emoji-test.txt),
keeps only RGI `fully-qualified` sequences, preserves the file's recommended
CLDR keyboard order and English group/subgroup/name metadata, and nests skin
tone sequences under their unmodified base emoji.

The generator is intentionally pinned to Emoji 17.0. If Unicode's `latest`
endpoint changes versions, generation fails until the product explicitly
adopts and tests that release.

```sh
bun scripts/generate-emoji-catalog.ts
bun scripts/generate-emoji-catalog.ts --check
```

For an offline or reproducible source snapshot:

```sh
bun scripts/generate-emoji-catalog.ts --input /path/to/emoji-test.txt
bun scripts/generate-emoji-catalog.ts --check --input /path/to/emoji-test.txt
```

The output is the compact, deterministic package resource at
`BuddyGrammarKit/Sources/BuddyGrammarKit/Resources/EmojiCatalog.json`. Unicode
data usage is subject to the [Unicode Terms of Use](https://www.unicode.org/terms_of_use.html).
