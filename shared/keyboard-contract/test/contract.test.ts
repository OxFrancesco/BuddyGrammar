import { describe, expect, test } from "bun:test";
import { join } from "node:path";

import {
  evaluateCapabilityPolicy,
  replayCorrectionTrace,
  validateCatalog,
  validateContractDirectory,
} from "../src/validate-contract";

const contractRoot = join(import.meta.dir, "..");

describe("published keyboard contract", () => {
  test("the checked-in v1 catalog and conformance traces are valid", async () => {
    const report = await validateContractDirectory(contractRoot);

    expect(report.issues).toEqual([]);
    expect(report.catalogRevision).toBe("2026.07.1");
    expect(report.traceCaseCount).toBe(55);
  });

  test("native targets bundle every published artifact byte-for-byte", async () => {
    const repositoryRoot = join(contractRoot, "..", "..");
    const swiftFixtureRoot = join(
      repositoryRoot,
      "BuddyGrammarKit",
      "Tests",
      "BuddyGrammarKitTests",
      "Fixtures",
      "KeyboardContract",
    );
    const androidFixtureRoot = join(
      repositoryRoot,
      "android",
      "app",
      "src",
      "test",
      "resources",
      "keyboard-contract",
    );
    const artifacts = [
      {
        published: join(contractRoot, "v1", "catalog.json"),
        copies: [
          join(
            repositoryRoot,
            "BuddyGrammarKit",
            "Sources",
            "BuddyGrammarKit",
            "Resources",
            "KeyboardCatalog.json",
          ),
          join(
            repositoryRoot,
            "android",
            "app",
            "src",
            "main",
            "res",
            "raw",
            "keyboard_catalog.json",
          ),
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
        published: join(contractRoot, "v1", "traces", fileName),
        copies: [
          join(swiftFixtureRoot, fileName),
          join(androidFixtureRoot, fileName),
        ],
      })),
    ];

    artifacts.push(
      ...["en-core.txt", "it-core.txt"].map((fileName) => ({
        published: join(contractRoot, "v1", "lexicons", fileName),
        copies: [
          join(
            repositoryRoot,
            "BuddyGrammarKit",
            "Sources",
            "BuddyGrammarKit",
            "Resources",
            fileName === "en-core.txt"
              ? "SwipeVocabulary.txt"
              : "SwipeVocabulary-it-v1.txt",
          ),
          join(
            repositoryRoot,
            "android",
            "app",
            "src",
            "main",
            "res",
            "raw",
            fileName === "en-core.txt"
              ? "swipe_lexicon_en_v1.txt"
              : "swipe_lexicon_it_v1.txt",
          ),
        ],
      })),
    );

    for (const artifact of artifacts) {
      const published = await Bun.file(artifact.published).text();
      for (const copy of artifact.copies) {
        expect(await Bun.file(copy).text()).toBe(published);
      }
    }
  });

  test("publishes the complete ranked English and Italian language packs", async () => {
    const words = async (languageId: "en" | "it") =>
      (await Bun.file(
        join(contractRoot, "v1", "lexicons", `${languageId}-core.txt`),
      ).text())
        .split(/\r?\n/u)
        .map((line) => line.trim())
        .filter((line) => line.length > 0 && !line.startsWith("#"));

    expect((await words("en")).length).toBe(8_000);
    expect((await words("it")).length).toBe(1_096);
  });

  test("an empty correction target is ignored instead of replacing unrelated text", () => {
    const state = replayCorrectionTrace(
      { initialText: "keep me", initialFieldEpoch: 1 },
      [
        {
          kind: "applyAutomatic",
          atMilliseconds: 100,
          source: "spelling",
          original: "",
          replacement: "unexpected",
          boundary: " ",
        },
      ],
    );

    expect(state.text).toBe("keep me");
    expect(state.activeReceipt).toBe(false);
    expect(state.ignoredEvents).toBe(1);
  });

  test("secure field layout metadata cannot opt back into suggestions", async () => {
    const catalog = await Bun.file(join(contractRoot, "v1", "catalog.json")).json();
    const mutated = structuredClone(catalog);
    const secure = mutated.layouts[0].fieldVariants.find(
      (variant: { id: string }) => variant.id === "secure",
    );
    secure.suggestionMode = "full";

    const issues = validateCatalog(mutated);

    expect(issues.map((issue) => issue.code)).toContain(
      "catalog.unsafe-field-variant",
    );
  });

  test("a field kind resolves to exactly one layout variant", async () => {
    const catalog = await Bun.file(join(contractRoot, "v1", "catalog.json")).json();
    const mutated = structuredClone(catalog);
    mutated.layouts[0].fieldVariants.find(
      (variant: { id: string }) => variant.id === "text",
    ).fieldKinds.push("email");

    const issues = validateCatalog(mutated);

    expect(issues.map((issue) => issue.code)).toContain(
      "catalog.field-kind-collision",
    );
  });

  test("a secure editor trait overrides an otherwise ordinary field kind", () => {
    const decision = evaluateCapabilityPolicy({
      fieldKind: "text",
      secure: true,
      noSuggestions: false,
      noPersonalizedLearning: false,
      cloudProcessingConsent: true,
      cloudTransportAvailable: true,
      platformVoiceAvailable: true,
      editorCanMoveCursor: true,
    });

    expect(decision.layoutVariant).toBe("secure");
    expect(decision.canSuggest).toBe(false);
    expect(decision.canReadContext).toBe(false);
    expect(decision.canUseComposition).toBe(false);
    expect(decision.buddyFix).toBe("denied.sensitive-field");
  });

  test("a no-suggestions text field keeps a distinct literal presentation", () => {
    const decision = evaluateCapabilityPolicy({
      fieldKind: "text",
      secure: false,
      noSuggestions: true,
      noPersonalizedLearning: false,
      cloudProcessingConsent: true,
      cloudTransportAvailable: true,
      platformVoiceAvailable: true,
      editorCanMoveCursor: true,
    });

    expect(decision.layoutVariant).toBe("literal");
    expect(decision.canReadContext).toBe(false);
    expect(decision.canUseComposition).toBe(false);
  });
});
