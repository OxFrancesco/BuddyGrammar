import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";

export interface ValidationIssue {
  path: string;
  code: string;
  message: string;
}

export interface ValidationReport {
  catalogRevision: string | null;
  traceCaseCount: number;
  issues: ValidationIssue[];
}

export interface CapabilityPolicyInput {
  fieldKind: string;
  secure: boolean;
  noSuggestions: boolean;
  noPersonalizedLearning: boolean;
  cloudProcessingConsent: boolean;
  cloudTransportAvailable: boolean;
  platformVoiceAvailable: boolean;
  editorCanMoveCursor: boolean;
}

export interface CapabilityPolicyDecision {
  layoutVariant: string;
  canSuggest: boolean;
  canLearn: boolean;
  canAutoCorrect: boolean;
  canSwipe: boolean;
  canReadContext: boolean;
  canUseComposition: boolean;
  canMoveCursor: boolean;
  buddyFix: string;
  platformVoice: string;
}

export interface CorrectionTraceInput {
  initialText: string;
  initialFieldEpoch: number;
}

export interface CorrectionTraceEvent {
  kind: string;
  atMilliseconds: number;
  source?: string;
  original?: string;
  replacement?: string;
  boundary?: string;
  receiptLifetimeMilliseconds?: number;
  text?: string;
  capturedFieldEpoch?: number;
}

export interface CorrectionTraceState {
  text: string;
  fieldEpoch: number;
  activeReceipt: boolean;
  receiptMode: "automatic" | "explicit" | null;
  receiptSource: string | null;
  pendingLearning: boolean;
  acceptedLearning: string[];
  rejectedSources: string[];
  ignoredEvents: number;
}

export interface SwipeSample {
  key: string;
  atMilliseconds: number;
  x: number;
  y: number;
}

export interface SwipeDwellExpectation {
  keySequence: string;
  repeatedRuns: string[];
}

export interface SwipeWordForm {
  display: string;
  geometry: string;
}

export interface TapTraceCandidate {
  key: string;
  confidence: number;
}

export interface TapTraceTap {
  literalKey: string;
  resolvedKey: string;
  candidates: TapTraceCandidate[];
}

export interface TapDecodingTraceInput {
  languageId: string;
  policy: "suggestion" | "automatic";
  taps: TapTraceTap[];
}

export interface TapDecodingTraceExpectation {
  literalWord: string;
  resolvedWord: string;
  topWord: string;
  acceptedWord: string | null;
  containsWords: string[];
  excludesWords: string[];
}

export interface TapDecodingTraceResult {
  literalWord: string;
  resolvedWord: string;
  candidateWords: string[];
  confidence: number;
  margin: number;
  acceptedWord: string | null;
}

interface RankedLexiconEntry {
  display: string;
  geometry: string;
  rank: number;
}

interface RankedLanguageLexicon {
  languageId: string;
  entries: RankedLexiconEntry[];
  byGeometry: Map<string, RankedLexiconEntry>;
}

export interface InteractionTraceConfiguration {
  longPressDelayMilliseconds: number;
  swipeDistance: number;
  alternateStep: number;
  cursorActivationMilliseconds: number;
  cursorActivationDistance: number;
  cursorStep: number;
  deleteRepeatDelayMilliseconds: number;
  deleteRepeatIntervalMilliseconds: number;
}

export interface InteractionTraceEvent {
  kind: string;
  atMilliseconds: number;
  literal?: string;
  alternates?: string[];
  x?: number;
  y?: number;
  deadlineKind?: "longPress" | "cursorActivation" | "deleteRepeat";
}

export interface InteractionTraceOutcome {
  committedText: string[];
  deleteBackwardCount: number;
  deleteWordCount: number;
  cursorDeltas: number[];
  swipePhases: string[];
  keyFeedbackCount: number;
  selectionFeedbackCount: number;
  alternateSelections: number[];
  hideAlternatesCount: number;
  settled: boolean;
}

interface CorrectionReceipt {
  mode: "automatic" | "explicit";
  source: string;
  original: string;
  replacement: string;
  boundary: string;
  fieldEpoch: number;
  expiresAtMilliseconds: number;
}

type JsonObject = Record<string, unknown>;

const REQUIRED_FIELD_VARIANTS = [
  "text",
  "literal",
  "email",
  "url",
  "number",
  "decimal",
  "phone",
  "search",
  "code",
  "secure",
] as const;

const REQUIRED_FIELD_KINDS = [
  "text",
  "multiline",
  "literal",
  "email",
  "url",
  "name",
  "number",
  "decimal",
  "phone",
  "datetime",
  "search",
  "code",
  "oneTimeCode",
  "password",
] as const;

const STRUCTURED_FIELDS = new Set([
  "email",
  "url",
  "name",
  "number",
  "decimal",
  "phone",
  "datetime",
]);

const SENSITIVE_FIELDS = new Set(["password", "oneTimeCode"]);

/**
 * Reference capability policy used by both native conformance suites.
 * It is deliberately text-free and evaluated before an editor context read.
 */
export function evaluateCapabilityPolicy(
  input: CapabilityPolicyInput,
): CapabilityPolicyDecision {
  const sensitive = input.secure || SENSITIVE_FIELDS.has(input.fieldKind);
  const structured = STRUCTURED_FIELDS.has(input.fieldKind);
  const code = input.fieldKind === "code";
  const search = input.fieldKind === "search";
  const localIntelligence =
    !sensitive && !structured && !code && !input.noSuggestions;

  let buddyFix: string;
  if (sensitive) {
    buddyFix = "denied.sensitive-field";
  } else if (code) {
    buddyFix = "denied.code-field";
  } else if (structured || search) {
    buddyFix = "denied.structured-field";
  } else if (input.noSuggestions) {
    buddyFix = "denied.editor-no-suggestions";
  } else if (!input.cloudTransportAvailable) {
    buddyFix = "denied.cloud-transport-unavailable";
  } else if (!input.cloudProcessingConsent) {
    buddyFix = "denied.cloud-consent-required";
  } else {
    buddyFix = "allowed";
  }

  let platformVoice: string;
  if (sensitive) {
    platformVoice = "denied.sensitive-field";
  } else if (code) {
    platformVoice = "denied.code-field";
  } else if (structured) {
    platformVoice = "denied.structured-field";
  } else if (!input.platformVoiceAvailable) {
    platformVoice = "denied.platform-voice-unavailable";
  } else {
    platformVoice = "allowed";
  }

  return {
    layoutVariant: sensitive
      ? "secure"
      : input.noSuggestions && new Set(["text", "multiline"]).has(input.fieldKind)
        ? "literal"
        : layoutVariantFor(input.fieldKind),
    canSuggest: localIntelligence,
    canLearn:
      localIntelligence && !search && !input.noPersonalizedLearning,
    canAutoCorrect: localIntelligence,
    canSwipe: localIntelligence,
    canReadContext: localIntelligence,
    canUseComposition: localIntelligence,
    canMoveCursor: input.editorCanMoveCursor,
    buddyFix,
    platformVoice,
  };
}

function layoutVariantFor(fieldKind: string): string {
  switch (fieldKind) {
    case "email":
    case "url":
    case "decimal":
    case "phone":
    case "search":
    case "code":
      return fieldKind;
    case "number":
    case "datetime":
      return "number";
    case "password":
    case "oneTimeCode":
      return "secure";
    default:
      return "text";
  }
}

/** Replays the platform-neutral correction receipt contract. */
export function replayCorrectionTrace(
  input: CorrectionTraceInput,
  events: CorrectionTraceEvent[],
): CorrectionTraceState {
  let text = input.initialText;
  let fieldEpoch = input.initialFieldEpoch;
  let receipt: CorrectionReceipt | null = null;
  const acceptedLearning: string[] = [];
  const rejectedSources: string[] = [];
  let ignoredEvents = 0;

  const discardReceipt = () => {
    receipt = null;
  };

  const applyCorrection = (
    event: CorrectionTraceEvent,
    mode: "automatic" | "explicit",
  ) => {
    const source = event.source;
    const original = event.original;
    const replacement = event.replacement;
    const boundary = mode === "automatic" ? event.boundary ?? "" : "";
    if (
      !source ||
      original === undefined ||
      original.length === 0 ||
      replacement === undefined ||
      replacement.length === 0
    ) {
      ignoredEvents += 1;
      return;
    }
    if (!text.endsWith(original)) {
      ignoredEvents += 1;
      return;
    }
    text = `${text.slice(0, -original.length)}${replacement}${boundary}`;
    receipt = {
      mode,
      source,
      original,
      replacement,
      boundary,
      fieldEpoch,
      expiresAtMilliseconds:
        event.atMilliseconds + (event.receiptLifetimeMilliseconds ?? 3_000),
    };
  };

  for (const event of events) {
    switch (event.kind) {
      case "applyAutomatic":
        applyCorrection(event, "automatic");
        break;
      case "applyExplicit":
        applyCorrection(event, "explicit");
        break;
      case "applyAsyncAutomatic":
        if (event.capturedFieldEpoch !== fieldEpoch) {
          ignoredEvents += 1;
        } else {
          applyCorrection(event, "automatic");
        }
        break;
      case "backspace": {
        if (
          receipt?.mode === "automatic" &&
          receipt.fieldEpoch === fieldEpoch &&
          text.endsWith(`${receipt.replacement}${receipt.boundary}`)
        ) {
          text = `${text.slice(
            0,
            -(receipt.replacement.length + receipt.boundary.length),
          )}${receipt.original}`;
          rejectedSources.push(receipt.source);
          discardReceipt();
        } else {
          discardReceipt();
          text = droppingLastGrapheme(text);
        }
        break;
      }
      case "revert": {
        if (!receipt || receipt.fieldEpoch !== fieldEpoch) {
          ignoredEvents += 1;
          break;
        }
        const appliedSuffix = `${receipt.replacement}${receipt.boundary}`;
        if (!text.endsWith(appliedSuffix)) {
          discardReceipt();
          ignoredEvents += 1;
          break;
        }
        const preservedBoundary =
          receipt.mode === "automatic" ? receipt.boundary : "";
        text = `${text.slice(0, -appliedSuffix.length)}${receipt.original}${preservedBoundary}`;
        rejectedSources.push(receipt.source);
        discardReceipt();
        break;
      }
      case "externalEdit":
        text = event.text ?? text;
        discardReceipt();
        break;
      case "changeField":
        text = event.text ?? "";
        fieldEpoch += 1;
        discardReceipt();
        break;
      case "advanceTime":
        if (receipt && event.atMilliseconds >= receipt.expiresAtMilliseconds) {
          acceptedLearning.push(receipt.replacement);
          discardReceipt();
        }
        break;
      default:
        ignoredEvents += 1;
    }
  }

  return {
    text,
    fieldEpoch,
    activeReceipt: receipt !== null,
    receiptMode: receipt?.mode ?? null,
    receiptSource: receipt?.source ?? null,
    pendingLearning: receipt !== null,
    acceptedLearning,
    rejectedSources,
    ignoredEvents,
  };
}

function droppingLastGrapheme(text: string): string {
  if (text.length === 0) return text;
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  const segments = [...segmenter.segment(text)];
  return segments.slice(0, -1).map((segment) => segment.segment).join("");
}

/** Resolves repeated-letter intent from stable same-key dwell runs. */
export function resolveSwipeDwell(
  samples: SwipeSample[],
  settings: {
    minimumDwellMilliseconds: number;
    minimumDwellSamples: number;
    maximumDwellDriftKeyUnits: number;
  },
): SwipeDwellExpectation {
  if (samples.length === 0) {
    return { keySequence: "", repeatedRuns: [] };
  }

  const runs: SwipeSample[][] = [];
  for (const sample of samples) {
    const active = runs.at(-1);
    if (active?.[0]?.key === sample.key) {
      active.push(sample);
    } else {
      runs.push([sample]);
    }
  }

  let keySequence = "";
  const repeatedRuns: string[] = [];
  for (const run of runs) {
    const first = run[0]!;
    const last = run.at(-1)!;
    keySequence += first.key;
    const duration = last.atMilliseconds - first.atMilliseconds;
    const maximumDrift = Math.max(
      ...run.map((sample) => Math.hypot(sample.x - first.x, sample.y - first.y)),
    );
    if (
      run.length >= settings.minimumDwellSamples &&
      duration >= settings.minimumDwellMilliseconds &&
      maximumDrift <= settings.maximumDwellDriftKeyUnits
    ) {
      keySequence += first.key;
      repeatedRuns.push(first.key);
    }
  }
  return { keySequence, repeatedRuns };
}

/**
 * Replays the logical interaction contract. Native conformance tests project
 * raw effects emitted by their production router into this same observable
 * shape. Every pointer press dispatches one immediate key-feedback effect;
 * release, cancellation, and swipe transition never add a duplicate.
 */
export function replayInteractionTrace(
  configuration: InteractionTraceConfiguration,
  events: InteractionTraceEvent[],
): InteractionTraceOutcome {
  type Point = { x: number; y: number };
  type Active =
    | {
        kind: "key";
        literal: string;
        alternates: string[];
        origin: Point;
        swiping: boolean;
        alternatesVisible: boolean;
        alternateIndex: number;
      }
    | {
        kind: "space";
        origin: Point;
        cursorMode: boolean;
        emittedCursorSteps: number;
      }
    | { kind: "delete" };

  let active: Active | null = null;
  let previewVisible = false;
  const scheduled = new Map<string, number>();
  const outcome: InteractionTraceOutcome = {
    committedText: [],
    deleteBackwardCount: 0,
    deleteWordCount: 0,
    cursorDeltas: [],
    swipePhases: [],
    keyFeedbackCount: 0,
    selectionFeedbackCount: 0,
    alternateSelections: [],
    hideAlternatesCount: 0,
    settled: false,
  };

  const point = (event: InteractionTraceEvent): Point => ({
    x: event.x ?? 0,
    y: event.y ?? 0,
  });
  const distance = (left: Point, right: Point) =>
    Math.hypot(left.x - right.x, left.y - right.y);

  for (const event of events) {
    switch (event.kind) {
      case "pressKey": {
        const origin = point(event);
        active = {
          kind: "key",
          literal: event.literal ?? "",
          alternates: event.alternates ?? [],
          origin,
          swiping: false,
          alternatesVisible: false,
          alternateIndex: 0,
        };
        previewVisible = true;
        outcome.keyFeedbackCount += 1;
        if ((event.alternates?.length ?? 0) > 0) {
          scheduled.set(
            "longPress",
            event.atMilliseconds + configuration.longPressDelayMilliseconds,
          );
        }
        break;
      }
      case "pressSpace":
        active = {
          kind: "space",
          origin: point(event),
          cursorMode: false,
          emittedCursorSteps: 0,
        };
        outcome.keyFeedbackCount += 1;
        scheduled.set(
          "cursorActivation",
          event.atMilliseconds + configuration.cursorActivationMilliseconds,
        );
        break;
      case "pressDelete":
        active = { kind: "delete" };
        outcome.deleteBackwardCount += 1;
        outcome.keyFeedbackCount += 1;
        scheduled.set(
          "deleteRepeat",
          event.atMilliseconds + configuration.deleteRepeatDelayMilliseconds,
        );
        break;
      case "move": {
        const movedTo = point(event);
        if (active?.kind === "key") {
          if (active.alternatesVisible) {
            const rawIndex = Math.round(
              (movedTo.x - active.origin.x) / configuration.alternateStep,
            );
            const index = Math.min(
              active.alternates.length - 1,
              Math.max(0, rawIndex),
            );
            if (index !== active.alternateIndex) {
              active.alternateIndex = index;
              outcome.alternateSelections.push(index);
            }
          } else if (active.swiping) {
            outcome.swipePhases.push("moved");
          } else if (distance(active.origin, movedTo) >= configuration.swipeDistance) {
            active.swiping = true;
            previewVisible = false;
            outcome.swipePhases.push("began", "moved");
          }
        } else if (active?.kind === "space") {
          const horizontalDistance = movedTo.x - active.origin.x;
          if (
            active.cursorMode ||
            Math.abs(horizontalDistance) >= configuration.cursorActivationDistance
          ) {
            if (!active.cursorMode) {
              active.cursorMode = true;
              outcome.selectionFeedbackCount += 1;
              previewVisible = false;
            }
            const totalSteps = Math.trunc(horizontalDistance / configuration.cursorStep);
            const delta = totalSteps - active.emittedCursorSteps;
            if (delta !== 0) {
              active.emittedCursorSteps = totalSteps;
              outcome.cursorDeltas.push(delta);
            }
          }
        }
        break;
      }
      case "release":
        if (active?.kind === "key") {
          if (active.swiping) {
            outcome.swipePhases.push("ended");
          } else if (active.alternatesVisible) {
            outcome.committedText.push(active.alternates[active.alternateIndex]!);
            outcome.hideAlternatesCount += 1;
          } else {
            outcome.committedText.push(active.literal);
          }
        } else if (active?.kind === "space" && !active.cursorMode) {
          outcome.committedText.push(" ");
        }
        active = null;
        previewVisible = false;
        break;
      case "fireScheduled": {
        const kind = event.deadlineKind;
        if (!kind || !scheduled.has(kind)) break;
        scheduled.delete(kind);
        if (
          kind === "longPress" &&
          active?.kind === "key" &&
          !active.swiping &&
          !active.alternatesVisible &&
          active.alternates.length > 0
        ) {
          active.alternatesVisible = true;
          active.alternateIndex = 0;
          outcome.alternateSelections.push(0);
          outcome.selectionFeedbackCount += 1;
        } else if (
          kind === "cursorActivation" &&
          active?.kind === "space" &&
          !active.cursorMode
        ) {
          active.cursorMode = true;
          outcome.selectionFeedbackCount += 1;
          previewVisible = false;
        } else if (kind === "deleteRepeat" && active?.kind === "delete") {
          outcome.deleteBackwardCount += 1;
          outcome.keyFeedbackCount += 1;
          scheduled.set(
            "deleteRepeat",
            event.atMilliseconds + configuration.deleteRepeatIntervalMilliseconds,
          );
        }
        break;
      }
      case "cancel":
        if (active?.kind === "key" && active.alternatesVisible) {
          outcome.hideAlternatesCount += 1;
        }
        active = null;
        previewVisible = false;
        break;
    }
  }

  outcome.settled =
    active === null &&
    !previewVisible;
  return outcome;
}

export async function validateContractDirectory(
  contractRoot: string,
): Promise<ValidationReport> {
  const issues: ValidationIssue[] = [];
  const versionRoot = join(contractRoot, "v1");
  const catalogSchema = await readJson(
    join(versionRoot, "catalog.schema.json"),
    "v1/catalog.schema.json",
    issues,
  );
  const traceSchema = await readJson(
    join(versionRoot, "trace-suite.schema.json"),
    "v1/trace-suite.schema.json",
    issues,
  );
  validatePublishedSchema(catalogSchema, "v1/catalog.schema.json", issues);
  validatePublishedSchema(traceSchema, "v1/trace-suite.schema.json", issues);

  const catalog = await readJson(
    join(versionRoot, "catalog.json"),
    "v1/catalog.json",
    issues,
  );
  validateCatalog(catalog, issues);
  const catalogRevision = stringValue(catalog, "catalogRevision");

  const lexicons = new Map<string, RankedLanguageLexicon>();
  const expectedLexiconCounts = new Map([
    ["en", 8_000],
    ["it", 1_096],
  ]);
  for (const [languageId, expectedCount] of expectedLexiconCounts) {
    const path = `v1/lexicons/${languageId}-core.txt`;
    const source = await readText(join(versionRoot, "lexicons", `${languageId}-core.txt`), path, issues);
    if (source === null) continue;
    const lexicon = parseRankedLanguageLexicon(source, languageId, path, issues);
    if (!lexicon) continue;
    if (lexicon.entries.length !== expectedCount) {
      addIssue(
        issues,
        path,
        "lexicon.entry-count",
        `Expected ${expectedCount} ranked entries, found ${lexicon.entries.length}.`,
      );
    }
    lexicons.set(languageId, lexicon);
  }

  let traceCaseCount = 0;
  const traceFiles = [
    "capability-policy.json",
    "correction-receipts.json",
    "interaction-routing.json",
    "swipe-dwell.json",
    "swipe-recognition.json",
    "tap-decoding.json",
  ];
  for (const file of traceFiles) {
    const path = `v1/traces/${file}`;
    const suite = await readJson(join(versionRoot, "traces", file), path, issues);
    traceCaseCount += validateTraceSuite(suite, path, catalog, lexicons, issues);
    const suiteRevision = stringValue(suite, "catalogRevision");
    if (catalogRevision && suiteRevision !== catalogRevision) {
      addIssue(
        issues,
        `${path}.catalogRevision`,
        "trace.catalog-revision",
        `Expected ${catalogRevision}, found ${suiteRevision ?? "missing"}.`,
      );
    }
  }

  return { catalogRevision, traceCaseCount, issues };
}

export function validateCatalog(
  rawCatalog: unknown,
  issues: ValidationIssue[] = [],
): ValidationIssue[] {
  const base = "v1/catalog.json";
  const catalog = asObject(rawCatalog);
  if (!catalog) {
    addIssue(issues, base, "catalog.type", "Catalog must be an object.");
    return issues;
  }
  if (catalog.schemaVersion !== 1) {
    addIssue(
      issues,
      `${base}.schemaVersion`,
      "catalog.schema-version",
      "Only schemaVersion 1 is supported.",
    );
  }
  const revision = stringValue(catalog, "catalogRevision");
  if (!revision || !/^\d{4}\.\d{2}\.\d+$/.test(revision)) {
    addIssue(
      issues,
      `${base}.catalogRevision`,
      "catalog.revision",
      "Catalog revision must use YYYY.MM.N.",
    );
  }

  const layouts = objectArray(catalog.layouts);
  const profiles = objectArray(catalog.layoutProfiles);
  const languages = objectArray(catalog.languages);
  const tools = objectArray(catalog.tools);
  validateUniqueIds(layouts, `${base}.layouts`, issues);
  validateUniqueIds(profiles, `${base}.layoutProfiles`, issues);
  validateUniqueIds(languages, `${base}.languages`, issues);
  validateUniqueIds(tools, `${base}.tools`, issues);

  const layoutIds = new Set(layouts.map((item) => stringValue(item, "id")));
  const profileIds = new Set(profiles.map((item) => stringValue(item, "id")));
  const languageIds = new Set(languages.map((item) => stringValue(item, "id")));
  if (!languageIds.has(stringValue(catalog, "defaultLanguageId"))) {
    addIssue(
      issues,
      `${base}.defaultLanguageId`,
      "catalog.reference",
      "Default language must reference a published language.",
    );
  }
  if (!profileIds.has(stringValue(catalog, "fallbackLayoutProfileId"))) {
    addIssue(
      issues,
      `${base}.fallbackLayoutProfileId`,
      "catalog.reference",
      "Fallback layout profile must reference a published profile.",
    );
  }

  profiles.forEach((profile, index) => {
    if (!layoutIds.has(stringValue(profile, "layoutId"))) {
      addIssue(
        issues,
        `${base}.layoutProfiles[${index}].layoutId`,
        "catalog.reference",
        "Layout profile references an unknown layout.",
      );
    }
    if (!languageIds.has(stringValue(profile, "languageId"))) {
      addIssue(
        issues,
        `${base}.layoutProfiles[${index}].languageId`,
        "catalog.reference",
        "Layout profile references an unknown language.",
      );
    }
  });

  const aliases = new Map<string, string>();
  languages.forEach((language, index) => {
    const id = stringValue(language, "id") ?? `language-${index}`;
    if (!profileIds.has(stringValue(language, "defaultLayoutProfileId"))) {
      addIssue(
        issues,
        `${base}.languages[${index}].defaultLayoutProfileId`,
        "catalog.reference",
        "Language references an unknown default layout profile.",
      );
    }
    for (const alias of stringArray(language.localeAliases)) {
      const normalized = alias.toLowerCase();
      const existing = aliases.get(normalized);
      if (existing && existing !== id) {
        addIssue(
          issues,
          `${base}.languages[${index}].localeAliases`,
          "catalog.locale-alias-collision",
          `Locale alias ${alias} is already owned by ${existing}.`,
        );
      }
      aliases.set(normalized, id);
    }
  });

  for (const requiredLanguage of ["en", "it"]) {
    if (!languageIds.has(requiredLanguage)) {
      addIssue(
        issues,
        `${base}.languages`,
        "catalog.required-language",
        `Missing required ${requiredLanguage} language metadata.`,
      );
    }
  }
  for (const alias of ["en-US", "en-GB", "it-IT", "it-CH"]) {
    if (!aliases.has(alias.toLowerCase())) {
      addIssue(
        issues,
        `${base}.languages`,
        "catalog.required-locale-alias",
        `Missing required locale alias ${alias}.`,
      );
    }
  }

  const allVariants = new Set<string>();
  for (const layout of layouts) {
    const fieldKindOwners = new Map<string, string>();
    for (const variant of objectArray(layout.fieldVariants)) {
      const id = stringValue(variant, "id");
      if (id) allVariants.add(id);
      for (const fieldKind of stringArray(variant.fieldKinds)) {
        const existing = fieldKindOwners.get(fieldKind);
        if (existing) {
          addIssue(
            issues,
            `${base}.layouts[${String(layout.id)}].fieldVariants[${id ?? "unknown"}].fieldKinds`,
            "catalog.field-kind-collision",
            `${fieldKind} is already owned by ${existing}.`,
          );
        } else if (id) {
          fieldKindOwners.set(fieldKind, id);
        }
      }
      if (
        id &&
        new Set(["literal", "email", "url", "number", "decimal", "phone", "code", "secure"]).has(id) &&
        (variant.suggestionMode !== "off" || variant.autoCapitalization !== "never")
      ) {
        addIssue(
          issues,
          `${base}.layouts[${String(layout.id)}].fieldVariants[${id}]`,
          "catalog.unsafe-field-variant",
          `${id} must disable suggestions and automatic capitalization.`,
        );
      }
    }
    for (const fieldKind of REQUIRED_FIELD_KINDS) {
      if (!fieldKindOwners.has(fieldKind)) {
        addIssue(
          issues,
          `${base}.layouts[${String(layout.id)}].fieldVariants`,
          "catalog.missing-field-kind",
          `No layout variant owns ${fieldKind}.`,
        );
      }
    }
  }
  for (const variant of REQUIRED_FIELD_VARIANTS) {
    if (!allVariants.has(variant)) {
      addIssue(
        issues,
        `${base}.layouts`,
        "catalog.required-field-variant",
        `Missing ${variant} field layout variant.`,
      );
    }
  }

  validateRequiredAlternates(languages, base, issues);
  validateGestureSettings(catalog.gestures, base, issues);
  return issues;
}

function validateRequiredAlternates(
  languages: JsonObject[],
  base: string,
  issues: ValidationIssue[],
) {
  const italian = languages.find((language) => language.id === "it");
  const alternates = asObject(italian?.alternates);
  const requirements: Record<string, string[]> = {
    a: ["à"],
    e: ["è", "é"],
    i: ["ì"],
    o: ["ò"],
    u: ["ù"],
  };
  for (const [key, required] of Object.entries(requirements)) {
    const outputs = stringArray(alternates?.[key]);
    for (const output of required) {
      if (!outputs.includes(output)) {
        addIssue(
          issues,
          `${base}.languages[it].alternates.${key}`,
          "catalog.required-alternate",
          `Italian ${key} must expose ${output}.`,
        );
      }
    }
  }
}

function validateGestureSettings(
  rawGestures: unknown,
  base: string,
  issues: ValidationIssue[],
) {
  const gestures = asObject(rawGestures);
  const swipe = asObject(gestures?.swipe);
  if (swipe?.repeatedLetterStrategy !== "dwell") {
    addIssue(
      issues,
      `${base}.gestures.swipe.repeatedLetterStrategy`,
      "catalog.swipe-dwell",
      "Repeated swipe letters must use the dwell strategy.",
    );
  }
  for (const key of ["minimumDwellMilliseconds", "minimumDwellSamples"] as const) {
    if (typeof swipe?.[key] !== "number" || swipe[key] <= 0) {
      addIssue(
        issues,
        `${base}.gestures.swipe.${key}`,
        "catalog.swipe-dwell",
        `${key} must be positive.`,
      );
    }
  }
  const drift = swipe?.maximumDwellDriftKeyUnits;
  if (typeof drift !== "number" || drift <= 0 || drift > 1) {
    addIssue(
      issues,
      `${base}.gestures.swipe.maximumDwellDriftKeyUnits`,
      "catalog.swipe-dwell",
      "maximumDwellDriftKeyUnits must be in (0, 1].",
    );
  }
}

function validateTraceSuite(
  rawSuite: unknown,
  path: string,
  catalog: unknown,
  lexicons: Map<string, RankedLanguageLexicon>,
  issues: ValidationIssue[],
): number {
  const suite = asObject(rawSuite);
  if (!suite) {
    addIssue(issues, path, "trace.type", "Trace suite must be an object.");
    return 0;
  }
  if (suite.schemaVersion !== 1) {
    addIssue(
      issues,
      `${path}.schemaVersion`,
      "trace.schema-version",
      "Only schemaVersion 1 is supported.",
    );
  }
  const cases = objectArray(suite.cases);
  validateUniqueIds(cases, `${path}.cases`, issues);
  if (cases.length === 0) {
    addIssue(issues, `${path}.cases`, "trace.empty", "Trace suite is empty.");
  }

  switch (suite.suite) {
    case "capability-policy":
      cases.forEach((testCase, index) => {
        const input = parseCapabilityInput(testCase.input);
        const expected = asObject(testCase.expect);
        if (!input || !expected) {
          addIssue(
            issues,
            `${path}.cases[${index}]`,
            "trace.capability-shape",
            "Capability case has an invalid input or expectation.",
          );
          return;
        }
        const actual = evaluateCapabilityPolicy(input);
        if (!isDeepStrictEqual(actual, expected)) {
          addIssue(
            issues,
            `${path}.cases[${index}].expect`,
            "trace.capability-mismatch",
            `Expected ${JSON.stringify(expected)}, evaluated ${JSON.stringify(actual)}.`,
          );
        }
      });
      break;
    case "correction-receipts":
      cases.forEach((testCase, index) => {
        const input = parseCorrectionInput(testCase.input);
        const events = parseCorrectionEvents(testCase.events);
        const expected = asObject(testCase.expect);
        if (!input || !events || !expected) {
          addIssue(
            issues,
            `${path}.cases[${index}]`,
            "trace.correction-shape",
            "Correction case has an invalid input, events, or expectation.",
          );
          return;
        }
        const actual = replayCorrectionTrace(input, events);
        if (!isDeepStrictEqual(actual, expected)) {
          addIssue(
            issues,
            `${path}.cases[${index}].expect`,
            "trace.correction-mismatch",
            `Expected ${JSON.stringify(expected)}, replayed ${JSON.stringify(actual)}.`,
          );
        }
      });
      break;
    case "interaction-routing": {
      const configuration = parseInteractionConfiguration(suite.configuration);
      if (!configuration) {
        addIssue(
          issues,
          `${path}.configuration`,
          "trace.interaction-configuration",
          "Interaction suite has an invalid router configuration.",
        );
        break;
      }
      cases.forEach((testCase, index) => {
        const input = asObject(testCase.input);
        const events = parseInteractionEvents(testCase.events);
        const expected = parseInteractionOutcome(testCase.expect);
        if (!input || !events || !expected) {
          addIssue(
            issues,
            `${path}.cases[${index}]`,
            "trace.interaction-shape",
            "Interaction case has an invalid input, events, or expectation.",
          );
          return;
        }
        const actual = replayInteractionTrace(configuration, events);
        if (!isDeepStrictEqual(actual, expected)) {
          addIssue(
            issues,
            `${path}.cases[${index}].expect`,
            "trace.interaction-mismatch",
            `Expected ${JSON.stringify(expected)}, replayed ${JSON.stringify(actual)}.`,
          );
        }
      });
      break;
    }
    case "swipe-dwell": {
      const settings = swipeSettings(catalog);
      if (!settings) {
        addIssue(
          issues,
          path,
          "trace.swipe-settings",
          "Catalog does not publish valid swipe dwell settings.",
        );
        break;
      }
      const languageIds = new Set(
        objectArray(asObject(catalog)?.languages).map((language) => language.id),
      );
      cases.forEach((testCase, index) => {
        const input = asObject(testCase.input);
        const samples = parseSwipeSamples(input?.samples);
        const expected = asObject(testCase.expect);
        if (!input || !samples || !expected) {
          addIssue(
            issues,
            `${path}.cases[${index}]`,
            "trace.swipe-shape",
            "Swipe case has an invalid input or expectation.",
          );
          return;
        }
        if (!languageIds.has(input.languageId)) {
          addIssue(
            issues,
            `${path}.cases[${index}].input.languageId`,
            "trace.language-reference",
            "Swipe trace references an unknown language.",
          );
        }
        const actual = resolveSwipeDwell(samples, settings);
        if (!isDeepStrictEqual(actual, expected)) {
          addIssue(
            issues,
            `${path}.cases[${index}].expect`,
            "trace.swipe-mismatch",
            `Expected ${JSON.stringify(expected)}, resolved ${JSON.stringify(actual)}.`,
          );
        }
      });
      break;
    }
    case "swipe-recognition": {
      const languageIds = new Set(
        objectArray(asObject(catalog)?.languages).map((language) => language.id),
      );
      cases.forEach((testCase, index) => {
        const input = asObject(testCase.input);
        const expected = asObject(testCase.expect);
        const rawVocabulary = input?.vocabulary;
        const vocabulary = stringArray(rawVocabulary);
        const samples = parseSwipeSamples(input?.samples);
        const displayWord = stringValue(expected, "displayWord");
        const geometryKey = stringValue(expected, "geometryKey");
        if (
          !input ||
          !expected ||
          !Array.isArray(rawVocabulary) ||
          vocabulary.length !== rawVocabulary.length ||
          vocabulary.length < 2 ||
          !samples ||
          !displayWord ||
          !geometryKey
        ) {
          addIssue(
            issues,
            `${path}.cases[${index}]`,
            "trace.swipe-recognition-shape",
            "Recognition case has an invalid vocabulary, samples, or expectation.",
          );
          return;
        }
        if (!languageIds.has(input.languageId)) {
          addIssue(
            issues,
            `${path}.cases[${index}].input.languageId`,
            "trace.language-reference",
            "Swipe recognition trace references an unknown language.",
          );
        }
        const forms = vocabulary.map(normalizeSwipeWord);
        if (forms.some((form) => form === null)) {
          addIssue(
            issues,
            `${path}.cases[${index}].input.vocabulary`,
            "trace.swipe-vocabulary",
            "Vocabulary entries must be swipeable words with letters and internal apostrophes.",
          );
          return;
        }
        const normalizedForms = forms as SwipeWordForm[];
        if (new Set(normalizedForms.map((form) => form.display)).size !== forms.length) {
          addIssue(
            issues,
            `${path}.cases[${index}].input.vocabulary`,
            "trace.swipe-vocabulary-duplicate",
            "Vocabulary entries must be unique after Unicode and apostrophe normalization.",
          );
        }
        const expectedForm = normalizeSwipeWord(displayWord);
        if (
          !expectedForm ||
          expectedForm.display !== displayWord ||
          expectedForm.geometry !== geometryKey ||
          !normalizedForms.some((form) => form.display === displayWord)
        ) {
          addIssue(
            issues,
            `${path}.cases[${index}].expect`,
            "trace.swipe-display-geometry",
            "Expected displayWord must be canonical, present in vocabulary, and derive geometryKey.",
          );
        }
      });
      break;
    }
    case "tap-decoding": {
      const languageIds = new Set(
        objectArray(asObject(catalog)?.languages).map((language) => language.id),
      );
      cases.forEach((testCase, index) => {
        const input = parseTapDecodingInput(testCase.input);
        const expected = parseTapDecodingExpectation(testCase.expect);
        if (!input || !expected) {
          addIssue(
            issues,
            `${path}.cases[${index}]`,
            "trace.tap-decoding-shape",
            "Tap decoding case has an invalid lattice or expectation.",
          );
          return;
        }
        const languageId = baseLanguage(input.languageId);
        if (!languageIds.has(languageId)) {
          addIssue(
            issues,
            `${path}.cases[${index}].input.languageId`,
            "trace.language-reference",
            "Tap decoding trace references an unknown language.",
          );
          return;
        }
        const lexicon = lexicons.get(languageId);
        if (!lexicon) {
          addIssue(
            issues,
            `${path}.cases[${index}].input.languageId`,
            "trace.lexicon-reference",
            `No ranked lexicon is published for ${languageId}.`,
          );
          return;
        }
        const actual = replayTapDecodingTrace(input, lexicon);
        const topWord = actual.candidateWords[0] ?? null;
        const missingWords = expected.containsWords.filter(
          (word) => !actual.candidateWords.includes(word),
        );
        const unexpectedWords = expected.excludesWords.filter((word) =>
          actual.candidateWords.includes(word),
        );
        if (
          actual.literalWord !== expected.literalWord ||
          actual.resolvedWord !== expected.resolvedWord ||
          topWord !== expected.topWord ||
          actual.acceptedWord !== expected.acceptedWord ||
          missingWords.length > 0 ||
          unexpectedWords.length > 0
        ) {
          addIssue(
            issues,
            `${path}.cases[${index}].expect`,
            "trace.tap-decoding-mismatch",
            `Expected ${JSON.stringify(expected)}, replayed ${JSON.stringify(actual)}.`,
          );
        }
      });
      break;
    }
    default:
      addIssue(
        issues,
        `${path}.suite`,
        "trace.unknown-suite",
        `Unknown trace suite ${String(suite.suite)}.`,
      );
  }
  return cases.length;
}

function parseInteractionConfiguration(
  raw: unknown,
): InteractionTraceConfiguration | null {
  const configuration = asObject(raw);
  if (!configuration) return null;
  const keys = [
    "longPressDelayMilliseconds",
    "swipeDistance",
    "alternateStep",
    "cursorActivationMilliseconds",
    "cursorActivationDistance",
    "cursorStep",
    "deleteRepeatDelayMilliseconds",
    "deleteRepeatIntervalMilliseconds",
  ] as const;
  if (
    keys.some(
      (key) =>
        typeof configuration[key] !== "number" ||
        !Number.isFinite(configuration[key]) ||
        Number(configuration[key]) <= 0,
    )
  ) {
    return null;
  }
  return configuration as unknown as InteractionTraceConfiguration;
}

function parseInteractionEvents(raw: unknown): InteractionTraceEvent[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const events: InteractionTraceEvent[] = [];
  let previousTime = -Infinity;
  for (const rawEvent of raw) {
    const event = asObject(rawEvent);
    if (
      !event ||
      typeof event.kind !== "string" ||
      typeof event.atMilliseconds !== "number" ||
      !Number.isFinite(event.atMilliseconds) ||
      event.atMilliseconds < previousTime
    ) {
      return null;
    }
    const hasPoint =
      typeof event.x === "number" &&
      Number.isFinite(event.x) &&
      typeof event.y === "number" &&
      Number.isFinite(event.y);
    switch (event.kind) {
      case "pressKey":
        if (
          !hasPoint ||
          typeof event.literal !== "string" ||
          event.literal.length === 0 ||
          !Array.isArray(event.alternates) ||
          event.alternates.some(
            (alternate) => typeof alternate !== "string" || alternate.length === 0,
          )
        ) {
          return null;
        }
        break;
      case "pressSpace":
      case "pressDelete":
      case "move":
      case "release":
        if (!hasPoint) return null;
        break;
      case "fireScheduled":
        if (
          !new Set(["longPress", "cursorActivation", "deleteRepeat"]).has(
            String(event.deadlineKind),
          )
        ) {
          return null;
        }
        break;
      case "cancel":
        break;
      default:
        return null;
    }
    previousTime = event.atMilliseconds;
    events.push(event as unknown as InteractionTraceEvent);
  }
  return events;
}

function parseInteractionOutcome(raw: unknown): InteractionTraceOutcome | null {
  const outcome = asObject(raw);
  if (!outcome) return null;
  const nonNegativeIntegers = [
    "deleteBackwardCount",
    "deleteWordCount",
    "keyFeedbackCount",
    "selectionFeedbackCount",
    "hideAlternatesCount",
  ] as const;
  if (
    !Array.isArray(outcome.committedText) ||
    outcome.committedText.some((value) => typeof value !== "string") ||
    !Array.isArray(outcome.cursorDeltas) ||
    outcome.cursorDeltas.some((value) => !Number.isInteger(value) || value === 0) ||
    !Array.isArray(outcome.swipePhases) ||
    outcome.swipePhases.some(
      (value) => !new Set(["began", "moved", "ended"]).has(String(value)),
    ) ||
    !Array.isArray(outcome.alternateSelections) ||
    outcome.alternateSelections.some(
      (value) => !Number.isInteger(value) || Number(value) < 0,
    ) ||
    nonNegativeIntegers.some(
      (key) => !Number.isInteger(outcome[key]) || Number(outcome[key]) < 0,
    ) ||
    typeof outcome.settled !== "boolean"
  ) {
    return null;
  }
  return outcome as unknown as InteractionTraceOutcome;
}

function parseCapabilityInput(raw: unknown): CapabilityPolicyInput | null {
  const input = asObject(raw);
  if (!input || typeof input.fieldKind !== "string") return null;
  const booleanKeys = [
    "secure",
    "noSuggestions",
    "noPersonalizedLearning",
    "cloudProcessingConsent",
    "cloudTransportAvailable",
    "platformVoiceAvailable",
    "editorCanMoveCursor",
  ] as const;
  if (booleanKeys.some((key) => typeof input[key] !== "boolean")) return null;
  return input as unknown as CapabilityPolicyInput;
}

function parseCorrectionInput(raw: unknown): CorrectionTraceInput | null {
  const input = asObject(raw);
  if (
    !input ||
    typeof input.initialText !== "string" ||
    !Number.isInteger(input.initialFieldEpoch) ||
    Number(input.initialFieldEpoch) < 1
  ) {
    return null;
  }
  return {
    initialText: input.initialText,
    initialFieldEpoch: Number(input.initialFieldEpoch),
  };
}

function parseCorrectionEvents(raw: unknown): CorrectionTraceEvent[] | null {
  if (!Array.isArray(raw)) return null;
  const events: CorrectionTraceEvent[] = [];
  for (const item of raw) {
    const event = asObject(item);
    if (
      !event ||
      typeof event.kind !== "string" ||
      typeof event.atMilliseconds !== "number"
    ) {
      return null;
    }
    events.push(event as unknown as CorrectionTraceEvent);
  }
  return events;
}

function parseSwipeSamples(raw: unknown): SwipeSample[] | null {
  if (!Array.isArray(raw) || raw.length < 2) return null;
  const samples: SwipeSample[] = [];
  let previousTime = -Infinity;
  for (const item of raw) {
    const sample = asObject(item);
    if (
      !sample ||
      typeof sample.key !== "string" ||
      !/^[a-z]$/.test(sample.key) ||
      typeof sample.atMilliseconds !== "number" ||
      sample.atMilliseconds < previousTime ||
      typeof sample.x !== "number" ||
      !Number.isFinite(sample.x) ||
      typeof sample.y !== "number" ||
      !Number.isFinite(sample.y)
    ) {
      return null;
    }
    previousTime = sample.atMilliseconds;
    samples.push(sample as unknown as SwipeSample);
  }
  return samples;
}

function parseRankedLanguageLexicon(
  source: string,
  languageId: string,
  path: string,
  issues: ValidationIssue[],
): RankedLanguageLexicon | null {
  const entries: RankedLexiconEntry[] = [];
  const byDisplay = new Set<string>();
  const byGeometry = new Map<string, RankedLexiconEntry>();
  let invalid = false;
  source.split(/\r?\n/u).forEach((rawLine, offset) => {
    const display = rawLine.trim();
    if (display.length === 0 || display.startsWith("#")) return;
    const form = normalizeSwipeWord(display);
    if (!form || form.display !== display) {
      invalid = true;
      addIssue(
        issues,
        `${path}:${offset + 1}`,
        "lexicon.invalid-entry",
        `Entries must use canonical lowercase display spelling; found ${JSON.stringify(display)}.`,
      );
      return;
    }
    if (!byDisplay.add(form.display)) {
      invalid = true;
      addIssue(
        issues,
        `${path}:${offset + 1}`,
        "lexicon.duplicate-entry",
        `Duplicate canonical entry ${form.display}.`,
      );
      return;
    }
    const entry = {
      display: form.display,
      geometry: form.geometry,
      rank: entries.length,
    };
    entries.push(entry);
    // Multiple accented display forms can intentionally share one ASCII
    // geometry. Rank order is the deterministic canonical choice for taps.
    if (!byGeometry.has(form.geometry)) byGeometry.set(form.geometry, entry);
  });
  return invalid ? null : { languageId, entries, byGeometry };
}

function parseTapDecodingInput(raw: unknown): TapDecodingTraceInput | null {
  const input = asObject(raw);
  if (
    !input ||
    typeof input.languageId !== "string" ||
    !new Set(["suggestion", "automatic"]).has(String(input.policy))
  ) return null;
  if (!Array.isArray(input.taps) || input.taps.length === 0 || input.taps.length > 32) {
    return null;
  }
  const taps: TapTraceTap[] = [];
  for (const rawTap of input.taps) {
    const tap = asObject(rawTap);
    if (
      !tap ||
      !isASCIIKey(tap.literalKey) ||
      !isASCIIKey(tap.resolvedKey) ||
      !Array.isArray(tap.candidates) ||
      tap.candidates.length === 0 ||
      tap.candidates.length > 15
    ) {
      return null;
    }
    const candidates: TapTraceCandidate[] = [];
    for (const rawCandidate of tap.candidates) {
      const candidate = asObject(rawCandidate);
      if (
        !candidate ||
        !isASCIIKey(candidate.key) ||
        typeof candidate.confidence !== "number" ||
        !Number.isFinite(candidate.confidence) ||
        candidate.confidence <= 0
      ) {
        return null;
      }
      candidates.push({
        key: candidate.key as string,
        confidence: candidate.confidence,
      });
    }
    taps.push({
      literalKey: tap.literalKey as string,
      resolvedKey: tap.resolvedKey as string,
      candidates,
    });
  }
  return {
    languageId: input.languageId,
    policy: input.policy as "suggestion" | "automatic",
    taps,
  };
}

function parseTapDecodingExpectation(
  raw: unknown,
): TapDecodingTraceExpectation | null {
  const expected = asObject(raw);
  if (!expected) return null;
  const literalWord = stringValue(expected, "literalWord");
  const resolvedWord = stringValue(expected, "resolvedWord");
  const topWord = stringValue(expected, "topWord");
  const acceptedWord = expected.acceptedWord;
  const rawContainsWords = expected.containsWords;
  const rawExcludesWords = expected.excludesWords;
  const containsWords = stringArray(rawContainsWords);
  const excludesWords = stringArray(rawExcludesWords);
  if (
    !literalWord ||
    !resolvedWord ||
    !topWord ||
    !(acceptedWord === null || (typeof acceptedWord === "string" && acceptedWord.length > 0)) ||
    !Array.isArray(rawContainsWords) ||
    containsWords.length !== rawContainsWords.length ||
    !Array.isArray(rawExcludesWords) ||
    excludesWords.length !== rawExcludesWords.length ||
    new Set(containsWords).size !== containsWords.length ||
    new Set(excludesWords).size !== excludesWords.length ||
    containsWords.some((word) => excludesWords.includes(word))
  ) {
    return null;
  }
  return {
    literalWord,
    resolvedWord,
    topWord,
    acceptedWord,
    containsWords,
    excludesWords,
  };
}

function replayTapDecodingTrace(
  input: TapDecodingTraceInput,
  lexicon: RankedLanguageLexicon,
): TapDecodingTraceResult {
  type Option = { key: string; probability: number };
  type Path = { word: string; spatialLogScore: number };
  type ScoredPath = {
    word: string;
    score: number;
    isLiteral: boolean;
    isResolved: boolean;
  };

  const rows: Option[][] = [];
  let literalWord = "";
  let resolvedWord = "";
  for (const tap of input.taps) {
    const literal = tap.literalKey.toLowerCase();
    const resolved = safeTapKey(tap.resolvedKey, tap.literalKey);
    literalWord += tap.literalKey;
    resolvedWord += resolved;
    const weights = new Map<string, number>();
    for (const candidate of tap.candidates.slice(0, 15)) {
      const key = candidate.key.toLowerCase();
      if (!areAdjacentTapKeys(literal, key)) continue;
      weights.set(key, Math.max(weights.get(key) ?? 0, candidate.confidence));
    }
    const normalizedResolved = resolved.toLowerCase();
    weights.set(literal, Math.max(weights.get(literal) ?? 0, 0.015));
    weights.set(
      normalizedResolved,
      Math.max(weights.get(normalizedResolved) ?? 0, 0.015),
    );
    const ranked = [...weights].map(([key, weight]) => ({
      key,
      weight,
      isLiteral: key === literal,
      isResolved: key === normalizedResolved,
    })).sort((left, right) => {
      if (Math.abs(left.weight - right.weight) > 1e-9) return right.weight - left.weight;
      if (left.isLiteral !== right.isLiteral) return left.isLiteral ? -1 : 1;
      if (left.isResolved !== right.isResolved) return left.isResolved ? -1 : 1;
      return left.key.localeCompare(right.key);
    });
    const required = new Set([literal, normalizedResolved]);
    const selected = ranked.slice(0, 5);
    for (const key of required) {
      if (selected.some((candidate) => candidate.key === key)) continue;
      const forced = ranked.find((candidate) => candidate.key === key);
      const replaceAt = selected.findLastIndex((candidate) => !required.has(candidate.key));
      if (forced && replaceAt >= 0) selected[replaceAt] = forced;
    }
    selected.sort((left, right) => {
      if (Math.abs(left.weight - right.weight) > 1e-9) return right.weight - left.weight;
      if (left.isLiteral !== right.isLiteral) return left.isLiteral ? -1 : 1;
      if (left.isResolved !== right.isResolved) return left.isResolved ? -1 : 1;
      return left.key.localeCompare(right.key);
    });
    const total = selected.reduce((sum, candidate) => sum + candidate.weight, 0);
    rows.push(selected.map((candidate) => ({
      key: renderTapKey(candidate.key, tap.literalKey),
      probability: Math.max(candidate.weight / total, 1e-9),
    })));
  }

  let beam: Path[] = [{ word: "", spatialLogScore: 0 }];
  for (const row of rows) {
    beam = beam.flatMap((path) => row.map((option) => ({
      word: path.word + option.key,
      spatialLogScore: path.spatialLogScore + Math.log(option.probability),
    }))).sort(tapPathComparator).slice(0, 48);
  }

  const paths = new Map<string, Path>();
  const insertPath = (path: Path) => {
    const existing = paths.get(path.word);
    if (!existing || path.spatialLogScore > existing.spatialLogScore) {
      paths.set(path.word, path);
    }
  };
  beam.forEach(insertPath);
  insertPath(forcedTapPath(literalWord, rows));
  insertPath(forcedTapPath(resolvedWord, rows));

  const requiredWords = new Set([literalWord, resolvedWord]);
  const scoredByWord = new Map<string, ScoredPath>();
  const insertScored = (candidate: ScoredPath) => {
    const existing = scoredByWord.get(candidate.word);
    if (!existing || tapScoredComparator(candidate, existing) < 0) {
      scoredByWord.set(candidate.word, candidate);
    }
  };
  for (const path of paths.values()) {
    const geometry = path.word.toLowerCase();
    const lexical = lexicon.byGeometry.get(geometry);
    if (lexical) {
      const word = matchingTapCase(lexical.display, path.word);
      insertScored({
        word,
        score: path.spatialLogScore + tapLexicalScore(lexical.rank),
        isLiteral: word === literalWord,
        isResolved: word === resolvedWord,
      });
      if (!requiredWords.has(path.word) || word === path.word) continue;
    }
    insertScored({
      word: path.word,
      score: path.spatialLogScore - 0.75,
      isLiteral: path.word === literalWord,
      isResolved: path.word === resolvedWord,
    });
  }

  const scored = [...scoredByWord.values()].sort(tapScoredComparator);
  const requestedCount = Math.max(requiredWords.size, 5);
  const selected = scored.slice(0, requestedCount);
  for (const word of requiredWords) {
    if (selected.some((candidate) => candidate.word === word)) continue;
    const forced = scored.find((candidate) => candidate.word === word);
    const replaceAt = selected.findLastIndex(
      (candidate) => !requiredWords.has(candidate.word),
    );
    if (forced && selected.length < requestedCount) selected.push(forced);
    else if (forced && replaceAt >= 0) selected[replaceAt] = forced;
  }
  selected.sort(tapScoredComparator);
  const maximumScore = selected[0]?.score;
  const exponentials = maximumScore === undefined
    ? []
    : selected.map((candidate) => Math.exp((candidate.score - maximumScore) / 1.15));
  const total = exponentials.reduce((sum, value) => sum + value, 0);
  const confidences = total > 0
    ? exponentials.map((value) => value / total)
    : selected.map((_, index) => index === 0 ? 1 : 0);
  const confidence = confidences[0] ?? 0;
  const margin = Math.max(0, Math.min(1, confidence - (confidences[1] ?? 0)));
  const minimumConfidence = input.policy === "automatic" ? 0.50 : 0.38;
  const minimumMargin = input.policy === "automatic" ? 0.18 : 0.08;
  const bestWord = selected[0]?.word ?? null;
  const acceptedWord =
    bestWord !== null &&
    bestWord.toLocaleLowerCase("it") !== literalWord.toLocaleLowerCase("it") &&
    confidence >= minimumConfidence &&
    margin >= minimumMargin
      ? bestWord
      : null;
  return {
    literalWord,
    resolvedWord,
    candidateWords: selected.map((candidate) => candidate.word),
    confidence,
    margin,
    acceptedWord,
  };
}

function forcedTapPath(
  word: string,
  rows: Array<Array<{ key: string; probability: number }>>,
) {
  let spatialLogScore = 0;
  Array.from(word).forEach((character, index) => {
    const probability = rows[index]?.find(
      (option) => option.key.toLowerCase() === character.toLowerCase(),
    )?.probability ?? 0.015;
    spatialLogScore += Math.log(Math.max(probability, 1e-9));
  });
  return { word, spatialLogScore };
}

function tapPathComparator(
  left: { word: string; spatialLogScore: number },
  right: { word: string; spatialLogScore: number },
) {
  if (Math.abs(left.spatialLogScore - right.spatialLogScore) > 1e-9) {
    return right.spatialLogScore - left.spatialLogScore;
  }
  return left.word.localeCompare(right.word);
}

function tapScoredComparator(
  left: { word: string; score: number; isLiteral: boolean; isResolved: boolean },
  right: { word: string; score: number; isLiteral: boolean; isResolved: boolean },
) {
  if (Math.abs(left.score - right.score) > 1e-9) return right.score - left.score;
  if (left.isLiteral !== right.isLiteral) return left.isLiteral ? -1 : 1;
  if (left.isResolved !== right.isResolved) return left.isResolved ? -1 : 1;
  return left.word.localeCompare(right.word);
}

function tapLexicalScore(rank: number) {
  return Math.max(-0.2, 0.9 - 0.25 * Math.log10(rank + 1));
}

const tapKeyPositions = (() => {
  const positions = new Map<string, [number, number]>();
  ([
    ["qwertyuiop", 0, 0],
    ["asdfghjkl", 0.25, 1],
    ["zxcvbnm", 0.75, 2],
  ] as const).forEach(([row, offset, y]) => {
    Array.from(row).forEach((key, index) => positions.set(key, [index + offset, y]));
  });
  return positions;
})();

function isASCIIKey(value: unknown): value is string {
  return typeof value === "string" && /^[a-z]$/iu.test(value);
}

function areAdjacentTapKeys(left: string, right: string) {
  const leftPosition = tapKeyPositions.get(left.toLowerCase());
  const rightPosition = tapKeyPositions.get(right.toLowerCase());
  if (!leftPosition || !rightPosition) return false;
  return Math.hypot(
    leftPosition[0] - rightPosition[0],
    leftPosition[1] - rightPosition[1],
  ) <= 1.3;
}

function safeTapKey(resolved: string, literal: string) {
  return areAdjacentTapKeys(literal, resolved)
    ? renderTapKey(resolved.toLowerCase(), literal)
    : literal;
}

function renderTapKey(key: string, like: string) {
  return like === like.toUpperCase() && like !== like.toLowerCase()
    ? key.toUpperCase()
    : key.toLowerCase();
}

function matchingTapCase(display: string, typed: string) {
  if (typed.length > 1 && typed === typed.toUpperCase()) {
    return display.toLocaleUpperCase("it");
  }
  if (typed[0] === typed[0]?.toUpperCase() && typed[0] !== typed[0]?.toLowerCase()) {
    return (display[0]?.toLocaleUpperCase("it") ?? "") + display.slice(1);
  }
  return display;
}

function baseLanguage(languageId: string) {
  return languageId.toLowerCase().split(/[-_]/u, 1)[0] ?? languageId.toLowerCase();
}

/**
 * Derives QWERTY gesture geometry without changing the emitted spelling.
 * U+2019 is the one canonical display apostrophe across all native targets.
 */
export function normalizeSwipeWord(word: string): SwipeWordForm | null {
  const display = word
    .toLocaleLowerCase("it")
    .replace(/['‘ʼ＇]/gu, "’")
    .normalize("NFC");
  if (!/^\p{Ll}+(?:’\p{Ll}+)*(?:’)?$/u.test(display)) return null;
  const geometry = display
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/’/gu, "");
  return /^[a-z]{2,}$/.test(geometry) ? { display, geometry } : null;
}

function swipeSettings(rawCatalog: unknown) {
  const catalog = asObject(rawCatalog);
  const gestures = asObject(catalog?.gestures);
  const swipe = asObject(gestures?.swipe);
  if (
    !swipe ||
    typeof swipe.minimumDwellMilliseconds !== "number" ||
    typeof swipe.minimumDwellSamples !== "number" ||
    typeof swipe.maximumDwellDriftKeyUnits !== "number"
  ) {
    return null;
  }
  return {
    minimumDwellMilliseconds: swipe.minimumDwellMilliseconds,
    minimumDwellSamples: swipe.minimumDwellSamples,
    maximumDwellDriftKeyUnits: swipe.maximumDwellDriftKeyUnits,
  };
}

async function readJson(
  filePath: string,
  displayPath: string,
  issues: ValidationIssue[],
): Promise<unknown> {
  try {
    return await Bun.file(filePath).json();
  } catch (error) {
    addIssue(
      issues,
      displayPath,
      "json.read",
      error instanceof Error ? error.message : String(error),
    );
    return null;
  }
}

async function readText(
  filePath: string,
  displayPath: string,
  issues: ValidationIssue[],
): Promise<string | null> {
  try {
    return await Bun.file(filePath).text();
  } catch (error) {
    addIssue(
      issues,
      displayPath,
      "text.read",
      error instanceof Error ? error.message : String(error),
    );
    return null;
  }
}

function validatePublishedSchema(
  rawSchema: unknown,
  path: string,
  issues: ValidationIssue[],
) {
  const schema = asObject(rawSchema);
  if (!schema || typeof schema.$id !== "string") {
    addIssue(
      issues,
      path,
      "schema.id",
      "Published schema must have a stable $id.",
    );
  }
  if (schema?.$schema !== "https://json-schema.org/draft/2020-12/schema") {
    addIssue(
      issues,
      path,
      "schema.dialect",
      "Published schema must use JSON Schema draft 2020-12.",
    );
  }
}

function validateUniqueIds(
  values: JsonObject[],
  path: string,
  issues: ValidationIssue[],
) {
  const seen = new Set<string>();
  values.forEach((value, index) => {
    const id = stringValue(value, "id");
    if (!id) {
      addIssue(
        issues,
        `${path}[${index}].id`,
        "catalog.id",
        "Entry must have a non-empty id.",
      );
    } else if (seen.has(id)) {
      addIssue(
        issues,
        `${path}[${index}].id`,
        "catalog.duplicate-id",
        `Duplicate id ${id}.`,
      );
    } else {
      seen.add(id);
    }
  });
}

function asObject(value: unknown): JsonObject | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonObject)
    : null;
}

function objectArray(value: unknown): JsonObject[] {
  return Array.isArray(value)
    ? value.map(asObject).filter((item): item is JsonObject => item !== null)
    : [];
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function stringValue(object: unknown, key: string): string | null {
  const value = asObject(object)?.[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function addIssue(
  issues: ValidationIssue[],
  path: string,
  code: string,
  message: string,
) {
  issues.push({ path, code, message });
}
