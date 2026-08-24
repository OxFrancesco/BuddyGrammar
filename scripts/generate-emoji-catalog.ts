#!/usr/bin/env bun

/**
 * Deterministically generates the iOS emoji catalog from Unicode's stable
 * Emoji 17.0 keyboard/display test data.
 *
 * Usage:
 *   bun scripts/generate-emoji-catalog.ts
 *   bun scripts/generate-emoji-catalog.ts --input /path/to/emoji-test.txt
 *   bun scripts/generate-emoji-catalog.ts --check --input /path/to/emoji-test.txt
 *
 * The default fetch URL intentionally uses UCD `latest`, but generation fails
 * unless its header is exactly Version 17.0. That prevents a future Unicode
 * release from silently changing the checked-in keyboard asset.
 */

import { resolve } from "node:path";

const SOURCE_URL = "https://www.unicode.org/Public/UCD/latest/emoji/emoji-test.txt";
const EXPECTED_VERSION = "17.0";
const DEFAULT_OUTPUT = resolve(
  import.meta.dir,
  "../BuddyGrammarKit/Sources/BuddyGrammarKit/Resources/EmojiCatalog.json",
);
const SKIN_TONES = new Map([
  ["1F3FB", "light skin tone"],
  ["1F3FC", "medium-light skin tone"],
  ["1F3FD", "medium skin tone"],
  ["1F3FE", "medium-dark skin tone"],
  ["1F3FF", "dark skin tone"],
]);
const GROUP_ICONS: Record<string, string> = {
  "Smileys & Emotion": "face.smiling",
  "People & Body": "hand.wave",
  "Animals & Nature": "pawprint",
  "Food & Drink": "fork.knife",
  "Travel & Places": "car",
  Activities: "figure.run",
  Objects: "lightbulb",
  Symbols: "heart",
  Flags: "flag",
};
const GROUP_IDS: Record<string, string> = {
  "Smileys & Emotion": "smileys",
  "People & Body": "people",
  "Animals & Nature": "animals",
  "Food & Drink": "food",
  "Travel & Places": "travel",
  Activities: "activities",
  Objects: "objects",
  Symbols: "symbols",
  Flags: "flags",
};

type RawEntry = {
  codePoints: string[];
  sequence: string;
  name: string;
  group: string;
  subgroup: string;
};

type Variant = {
  sequence: string;
  name: string;
  keywords: string[];
  skinTones: string[];
};

type Entry = {
  sequence: string;
  name: string;
  keywords: string[];
  variants: Variant[];
};

function option(name: string): string | undefined {
  const index = Bun.argv.indexOf(name);
  if (index < 0) return undefined;
  const value = Bun.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
  return value;
}

function slug(value: string): string {
  return value
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function normalizedPhrase(value: string): string {
  return (value.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []).join(" ");
}

function keywords(entry: RawEntry): string[] {
  // The English name is stored separately. Group/subgroup labels from the
  // same Unicode file provide compact additional search vocabulary.
  return [
    ...new Set([normalizedPhrase(entry.subgroup), normalizedPhrase(entry.group)]),
  ].filter(Boolean);
}

function sequenceFrom(codePoints: string[]): string {
  return String.fromCodePoint(...codePoints.map((value) => Number.parseInt(value, 16)));
}

function parseSource(source: string): {
  version: string;
  date: string;
  entries: RawEntry[];
} {
  let version = "";
  let date = "";
  let group = "";
  let subgroup = "";
  const entries: RawEntry[] = [];

  for (const [index, rawLine] of source.split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (line.startsWith("# Version:")) {
      version = line.slice("# Version:".length).trim();
      continue;
    }
    if (line.startsWith("# Date:")) {
      date = line.slice("# Date:".length).trim();
      continue;
    }
    if (line.startsWith("# group:")) {
      group = line.slice("# group:".length).trim();
      subgroup = "";
      continue;
    }
    if (line.startsWith("# subgroup:")) {
      subgroup = line.slice("# subgroup:".length).trim();
      continue;
    }
    if (!line || line.startsWith("#")) continue;

    const match = line.match(
      /^([0-9A-F ]+)\s*;\s*([a-z-]+)\s*#\s*(\S+)\s+E[0-9.]+\s+(.+)$/,
    );
    if (!match) throw new Error(`Malformed emoji-test entry on line ${index + 1}`);
    const [, rawCodePoints, qualification, , name] = match;
    if (qualification !== "fully-qualified") continue;
    if (!group || !subgroup) {
      throw new Error(`Fully-qualified entry outside a group on line ${index + 1}`);
    }
    const codePoints = rawCodePoints.trim().split(/\s+/);
    entries.push({
      codePoints,
      sequence: sequenceFrom(codePoints),
      name,
      group,
      subgroup,
    });
  }

  if (!version) throw new Error("emoji-test.txt is missing a Version header");
  if (!date) throw new Error("emoji-test.txt is missing a Date header");
  if (version !== EXPECTED_VERSION) {
    throw new Error(`Expected Unicode Emoji ${EXPECTED_VERSION}, received ${version}`);
  }
  return { version, date, entries };
}

function buildCatalog(source: string) {
  const parsed = parseSource(source);
  const byCodePoints = new Map(
    parsed.entries.map((entry) => [entry.codePoints.join(" "), entry]),
  );
  const variantsByBase = new Map<string, RawEntry[]>();
  const nestedVariantSequences = new Set<string>();

  for (const entry of parsed.entries) {
    const baseCodePoints = entry.codePoints.filter((value) => !SKIN_TONES.has(value));
    if (baseCodePoints.length === entry.codePoints.length) continue;
    const base = byCodePoints.get(baseCodePoints.join(" "));
    if (!base) continue;
    const variants = variantsByBase.get(base.sequence) ?? [];
    variants.push(entry);
    variantsByBase.set(base.sequence, variants);
    nestedVariantSequences.add(entry.sequence);
  }

  const categoryMap = new Map<
    string,
    { id: string; name: string; icon: string; entries: Entry[] }
  >();
  for (const rawEntry of parsed.entries) {
    if (nestedVariantSequences.has(rawEntry.sequence)) continue;
    const category = categoryMap.get(rawEntry.group) ?? {
      id: GROUP_IDS[rawEntry.group] ?? slug(rawEntry.group),
      name: rawEntry.group,
      icon: GROUP_ICONS[rawEntry.group] ?? "circle.grid.3x3",
      entries: [],
    };
    const variants = (variantsByBase.get(rawEntry.sequence) ?? []).map(
      (variant): Variant => ({
        sequence: variant.sequence,
        name: variant.name,
        keywords: keywords(variant),
        skinTones: variant.codePoints.flatMap((value) => {
          const tone = SKIN_TONES.get(value);
          return tone ? [tone] : [];
        }),
      }),
    );
    category.entries.push({
      sequence: rawEntry.sequence,
      name: rawEntry.name,
      keywords: keywords(rawEntry),
      variants,
    });
    categoryMap.set(rawEntry.group, category);
  }

  const categories = [...categoryMap.values()].filter((category) => category.entries.length > 0);
  const representedCount = categories.reduce(
    (categoryTotal, category) =>
      categoryTotal +
      category.entries.reduce((entryTotal, entry) => entryTotal + 1 + entry.variants.length, 0),
    0,
  );
  if (representedCount !== parsed.entries.length) {
    throw new Error(
      `Generated ${representedCount} sequences from ${parsed.entries.length} fully-qualified entries`,
    );
  }

  return {
    schemaVersion: 1,
    unicodeVersion: parsed.version,
    source: SOURCE_URL,
    sourceDate: parsed.date,
    qualification: "fully-qualified",
    fullyQualifiedSequenceCount: parsed.entries.length,
    categories,
  };
}

async function loadSource(): Promise<string> {
  const input = option("--input");
  if (input) return Bun.file(resolve(input)).text();
  const response = await fetch(SOURCE_URL);
  if (!response.ok) throw new Error(`Unicode download failed: HTTP ${response.status}`);
  return response.text();
}

const outputPath = resolve(option("--output") ?? DEFAULT_OUTPUT);
// This is a machine-generated mobile resource, so compact JSON materially
// reduces extension bundle and decode overhead while the script stays legible.
const generated = `${JSON.stringify(buildCatalog(await loadSource()))}\n`;

if (Bun.argv.includes("--check")) {
  const existing = await Bun.file(outputPath).text();
  if (existing !== generated) {
    throw new Error(`Generated catalog differs from ${outputPath}`);
  }
  console.log(`Emoji catalog is deterministic and current: ${outputPath}`);
} else {
  await Bun.write(outputPath, generated);
  const catalog = JSON.parse(generated);
  console.log(
    `Generated Emoji ${catalog.unicodeVersion}: ${catalog.fullyQualifiedSequenceCount} sequences across ${catalog.categories.length} categories`,
  );
  console.log(outputPath);
}
