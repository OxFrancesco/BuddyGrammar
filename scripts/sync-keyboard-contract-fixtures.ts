#!/usr/bin/env bun

import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const repositoryRoot = resolve(import.meta.dir, "..");
const contractRoot = resolve(repositoryRoot, "shared/keyboard-contract/v1");
const checkOnly = Bun.argv.includes("--check");

const copies = [
  {
    source: resolve(contractRoot, "catalog.json"),
    targets: [
      resolve(
        repositoryRoot,
        "BuddyGrammarKit/Sources/BuddyGrammarKit/Resources/KeyboardCatalog.json",
      ),
      resolve(repositoryRoot, "android/app/src/main/res/raw/keyboard_catalog.json"),
    ],
  },
  ...[
    "capability-policy.json",
    "correction-receipts.json",
    "interaction-routing.json",
    "swipe-dwell.json",
    "swipe-recognition.json",
    "tap-decoding.json",
  ].map((fileName) => ({
    source: resolve(contractRoot, "traces", fileName),
    targets: [
      resolve(
        repositoryRoot,
        "BuddyGrammarKit/Tests/BuddyGrammarKitTests/Fixtures/KeyboardContract",
        fileName,
      ),
      resolve(
        repositoryRoot,
        "android/app/src/test/resources/keyboard-contract",
        fileName,
      ),
    ],
  })),
];

let drifted = false;
for (const copy of copies) {
  const published = await Bun.file(copy.source).text();
  for (const target of copy.targets) {
    const existing = await Bun.file(target).text().catch(() => undefined);
    if (existing === published) continue;
    if (checkOnly) {
      drifted = true;
      console.error(`Out of date: ${target}`);
      continue;
    }
    await mkdir(dirname(target), { recursive: true });
    await Bun.write(target, published);
    console.log(`Updated ${target}`);
  }
}

if (drifted) process.exit(1);
