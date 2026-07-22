#!/usr/bin/env bun

import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const repositoryRoot = resolve(import.meta.dir, "..");
const checkOnly = Bun.argv.includes("--check");
let hasOutdatedCopy = false;

const lexicons = [
  {
    languageId: "en",
    canonical: resolve(
      repositoryRoot,
      "shared/keyboard-contract/v1/lexicons/en-core.txt",
    ),
    generatedCopies: [
      resolve(
        repositoryRoot,
        "android/app/src/main/res/raw/swipe_lexicon_en_v1.txt",
      ),
      resolve(
        repositoryRoot,
        "BuddyGrammarKit/Sources/BuddyGrammarKit/Resources/SwipeVocabulary.txt",
      ),
      resolve(
        repositoryRoot,
        "android/app/src/test/resources/keyboard-contract/lexicons/en-core.txt",
      ),
    ],
  },
  {
    languageId: "it",
    canonical: resolve(
      repositoryRoot,
      "shared/keyboard-contract/v1/lexicons/it-core.txt",
    ),
    generatedCopies: [
      resolve(
        repositoryRoot,
        "android/app/src/main/res/raw/swipe_lexicon_it_v1.txt",
      ),
      resolve(
        repositoryRoot,
        "BuddyGrammarKit/Sources/BuddyGrammarKit/Resources/SwipeVocabulary-it-v1.txt",
      ),
      resolve(
        repositoryRoot,
        "android/app/src/test/resources/keyboard-contract/lexicons/it-core.txt",
      ),
    ],
  },
] as const;

for (const lexicon of lexicons) {
  const published = await Bun.file(lexicon.canonical).text();
  for (const generatedCopy of lexicon.generatedCopies) {
    const existing = await Bun.file(generatedCopy).text().catch(() => undefined);
    if (existing === published) continue;

    if (checkOnly) {
      console.error(`Out of date: ${generatedCopy}`);
      hasOutdatedCopy = true;
      continue;
    }
    await mkdir(dirname(generatedCopy), { recursive: true });
    await Bun.write(generatedCopy, published);
    console.log(`Updated ${lexicon.languageId}: ${generatedCopy}`);
  }
}

if (hasOutdatedCopy) process.exit(1);
