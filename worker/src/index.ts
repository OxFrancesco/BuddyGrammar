export interface Env {
  OPENROUTER_API_KEY?: string;
  ELEVENLABS_API_KEY?: string;
  OPENROUTER_MODEL_ALLOWLIST?: string;
  ALLOWED_ORIGINS?: string;
  RATE_LIMITER: DurableObjectNamespace;
}

interface Dependencies {
  fetch: typeof fetch;
}

interface ErrorBody {
  error: {
    code: string;
    message: string;
  };
}

interface CorrectionRequest {
  text: string;
  modelID: string;
  instruction: string;
}

interface RatePolicy {
  clientLimit: number;
  ipLimit: number;
  windowSeconds: number;
}

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const ELEVENLABS_URL = "https://api.elevenlabs.io/v1/speech-to-text";
const CLIENT_HEADER = "x-buddygrammar-client-id";
const MAX_JSON_BYTES = 64 * 1024;
const MAX_TEXT_CHARACTERS = 10_000;
const MAX_INSTRUCTION_CHARACTERS = 2_000;
const MAX_AUDIO_BYTES = 12 * 1024 * 1024;
const OPENROUTER_TIMEOUT_MS = 25_000;
const ELEVENLABS_TIMEOUT_MS = 90_000;
const DEFAULT_MODEL = "openai/gpt-5.4-nano";
const CLIENT_ID_PATTERN = /^[A-Za-z0-9._-]{16,128}$/;
const LANGUAGE_CODE_PATTERN = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/;
const LANGUAGE_HEADER = "x-buddy-language-code";

const RATE_POLICIES: Record<string, RatePolicy> = {
  "/v1/correct": { clientLimit: 30, ipLimit: 180, windowSeconds: 60 },
  "/v1/transcribe": { clientLimit: 8, ipLimit: 40, windowSeconds: 60 },
};

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
} satisfies ExportedHandler<Env>;

export async function handleRequest(
  request: Request,
  env: Env,
  dependencies: Dependencies = { fetch: globalThis.fetch.bind(globalThis) },
): Promise<Response> {
  const requestID = crypto.randomUUID();
  const url = new URL(request.url);
  const originResult = validateOrigin(request, env, requestID);
  if (originResult) return originResult;

  if (request.method === "OPTIONS") {
    if (url.pathname !== "/v1/correct" && url.pathname !== "/v1/transcribe") {
      return errorResponse(404, "not_found", "The requested endpoint does not exist.", requestID, request, env);
    }
    return preflightResponse(request, env, requestID);
  }

  if (url.pathname === "/health") {
    if (request.method !== "GET") return methodNotAllowed("GET", requestID);
    if (!env.OPENROUTER_API_KEY || !env.ELEVENLABS_API_KEY) {
      return jsonResponse({ status: "unavailable" }, 503, requestID, request, env);
    }
    return jsonResponse({ status: "ok" }, 200, requestID, request, env);
  }

  if (url.pathname !== "/v1/correct" && url.pathname !== "/v1/transcribe") {
    return errorResponse(404, "not_found", "The requested endpoint does not exist.", requestID, request, env);
  }
  if (request.method !== "POST") return methodNotAllowed("POST", requestID);

  const clientID = request.headers.get(CLIENT_HEADER)?.trim() ?? "";
  if (!CLIENT_ID_PATTERN.test(clientID)) {
    return errorResponse(
      400,
      "invalid_client_id",
      "A valid client identifier is required.",
      requestID,
      request,
      env,
    );
  }

  let rateResponse: Response | null;
  try {
    rateResponse = await enforceRateLimits(url.pathname, clientID, request, env, requestID);
  } catch {
    return errorResponse(
      503,
      "rate_limiter_unavailable",
      "The processing service is temporarily unavailable.",
      requestID,
      request,
      env,
    );
  }
  if (rateResponse) return rateResponse;

  try {
    if (url.pathname === "/v1/correct") {
      return await correct(request, env, dependencies, requestID);
    }
    return await transcribe(request, env, dependencies, requestID);
  } catch (error) {
    if (error instanceof RequestProblem) {
      return errorResponse(error.status, error.code, error.message, requestID, request, env);
    }
    return errorResponse(
      502,
      "upstream_unavailable",
      "The processing service is temporarily unavailable.",
      requestID,
      request,
      env,
    );
  }
}

async function correct(
  request: Request,
  env: Env,
  dependencies: Dependencies,
  requestID: string,
): Promise<Response> {
  if (!env.OPENROUTER_API_KEY) {
    throw new RequestProblem(503, "service_not_configured", "Correction is temporarily unavailable.");
  }
  requireContentType(request, "application/json");
  const bytes = await readBodyWithLimit(request, MAX_JSON_BYTES);
  let input: unknown;
  try {
    input = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new RequestProblem(400, "invalid_json", "The request body must be valid JSON.");
  }
  const body = validateCorrectionRequest(input, env);

  const upstream = await dependencies.fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
      "content-type": "application/json",
      "x-title": "BuddyGrammar iOS",
    },
    body: JSON.stringify({
      model: body.modelID,
      temperature: 0,
      max_tokens: 4_096,
      messages: [
        { role: "system", content: body.instruction },
        { role: "user", content: body.text },
      ],
      provider: { zdr: true, data_collection: "deny" },
    }),
    signal: AbortSignal.timeout(OPENROUTER_TIMEOUT_MS),
  });

  if (!upstream.ok) {
    throw new RequestProblem(
      upstream.status === 429 ? 429 : 502,
      upstream.status === 429 ? "provider_rate_limited" : "provider_error",
      upstream.status === 429
        ? "Correction is busy. Please try again shortly."
        : "Correction could not be completed.",
    );
  }

  const payload = await safeJSON(upstream);
  const output = extractOpenRouterText(payload)?.trim();
  const maximumOutputCharacters = Math.max(500, body.text.length * 4);
  if (!output || output.length > maximumOutputCharacters) {
    throw new RequestProblem(502, "invalid_provider_response", "Correction could not be completed.");
  }
  return jsonResponse({ text: output }, 200, requestID, request, env);
}

async function transcribe(
  request: Request,
  env: Env,
  dependencies: Dependencies,
  requestID: string,
): Promise<Response> {
  if (!env.ELEVENLABS_API_KEY) {
    throw new RequestProblem(503, "service_not_configured", "Transcription is temporarily unavailable.");
  }
  requireContentType(request, "audio/mp4");
  if (request.headers.has("content-encoding")) {
    throw new RequestProblem(415, "unsupported_content_encoding", "Compressed request bodies are not supported.");
  }
  const bytes = await readBodyWithLimit(request, MAX_AUDIO_BYTES);
  if (bytes.byteLength === 0) {
    throw new RequestProblem(422, "invalid_audio", "An audio file between 1 byte and 12 MB is required.");
  }
  const languageCode = request.headers.get(LANGUAGE_HEADER)?.trim() ?? "";
  if (languageCode && !LANGUAGE_CODE_PATTERN.test(languageCode)) {
    throw new RequestProblem(422, "invalid_language_code", "The language code is invalid.");
  }

  const outgoing = new FormData();
  outgoing.set("model_id", "scribe_v2");
  outgoing.set("tag_audio_events", "false");
  outgoing.set("diarize", "false");
  if (languageCode) outgoing.set("language_code", languageCode);
  outgoing.set("file", new File([bytes], "dictation.m4a", { type: "audio/mp4" }));

  const upstream = await dependencies.fetch(ELEVENLABS_URL, {
    method: "POST",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
    body: outgoing,
    signal: AbortSignal.timeout(ELEVENLABS_TIMEOUT_MS),
  });
  if (!upstream.ok) {
    throw new RequestProblem(
      upstream.status === 429 ? 429 : 502,
      upstream.status === 429 ? "provider_rate_limited" : "provider_error",
      upstream.status === 429
        ? "Transcription is busy. Please try again shortly."
        : "Transcription could not be completed.",
    );
  }

  const payload = await safeJSON(upstream);
  const transcript = validateTranscript(payload);
  return jsonResponse(transcript, 200, requestID, request, env);
}

function validateCorrectionRequest(input: unknown, env: Env): CorrectionRequest {
  if (!isRecord(input)) {
    throw new RequestProblem(400, "invalid_request", "The correction request is invalid.");
  }
  const allowedKeys = new Set(["text", "modelID", "instruction"]);
  if (Object.keys(input).some((key) => !allowedKeys.has(key))) {
    throw new RequestProblem(400, "unexpected_field", "The correction request contains an unexpected field.");
  }
  const text = typeof input.text === "string" ? input.text.trim() : "";
  const modelID = typeof input.modelID === "string" ? input.modelID.trim() : "";
  const instruction = typeof input.instruction === "string" ? input.instruction.trim() : "";
  if (!text || text.length > MAX_TEXT_CHARACTERS) {
    throw new RequestProblem(422, "invalid_text", "Text must contain between 1 and 10,000 characters.");
  }
  if (!instruction || instruction.length > MAX_INSTRUCTION_CHARACTERS) {
    throw new RequestProblem(422, "invalid_instruction", "The instruction must contain between 1 and 2,000 characters.");
  }
  if (!modelID || modelID.length > 200 || !allowedModels(env).has(modelID)) {
    throw new RequestProblem(422, "model_not_allowed", "The requested correction model is not allowed.");
  }
  return { text, modelID, instruction };
}

function validateTranscript(input: unknown): {
  text: string;
  language_code: string | null;
  language_probability: number | null;
} {
  if (!isRecord(input) || typeof input.text !== "string" || !input.text.trim()) {
    throw new RequestProblem(502, "invalid_provider_response", "Transcription could not be completed.");
  }
  const languageCode = typeof input.language_code === "string" ? input.language_code : null;
  const languageProbability =
    typeof input.language_probability === "number" && Number.isFinite(input.language_probability)
      ? input.language_probability
      : null;
  return {
    text: input.text.trim(),
    language_code: languageCode,
    language_probability: languageProbability,
  };
}

async function enforceRateLimits(
  path: string,
  clientID: string,
  request: Request,
  env: Env,
  requestID: string,
): Promise<Response | null> {
  const policy = RATE_POLICIES[path];
  if (!policy) return null;
  const ip = request.headers.get("cf-connecting-ip")?.trim() || "unknown";
  const checks = [
    { scope: `client:${path}:${clientID}`, limit: policy.clientLimit },
    { scope: `ip:${path}:${ip}`, limit: policy.ipLimit },
  ];

  for (const check of checks) {
    const digest = await sha256(check.scope);
    const id = env.RATE_LIMITER.idFromName(digest);
    const response = await env.RATE_LIMITER.get(id).fetch("https://rate-limiter/check", {
      method: "POST",
      headers: {
        "x-rate-limit": String(check.limit),
        "x-rate-window-seconds": String(policy.windowSeconds),
      },
    });
    if (response.status === 429) {
      const retryAfter = response.headers.get("retry-after") ?? String(policy.windowSeconds);
      return errorResponse(
        429,
        "rate_limited",
        "Too many requests. Please try again shortly.",
        requestID,
        request,
        env,
        { "retry-after": retryAfter },
      );
    }
    if (!response.ok) {
      return errorResponse(
        503,
        "rate_limiter_unavailable",
        "The processing service is temporarily unavailable.",
        requestID,
        request,
        env,
      );
    }
  }
  return null;
}

export class RateLimiter {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") return new Response(null, { status: 405 });
    const limit = positiveInteger(request.headers.get("x-rate-limit"), 1, 10_000);
    const windowSeconds = positiveInteger(request.headers.get("x-rate-window-seconds"), 1, 3_600);
    if (!limit || !windowSeconds) return new Response(null, { status: 400 });

    const now = Date.now();
    let bucket = await this.state.storage.get<{ count: number; resetAt: number }>("bucket");
    if (!bucket || bucket.resetAt <= now) {
      bucket = { count: 0, resetAt: now + windowSeconds * 1_000 };
    }
    if (bucket.count >= limit) {
      return new Response(null, {
        status: 429,
        headers: { "retry-after": String(Math.max(1, Math.ceil((bucket.resetAt - now) / 1_000))) },
      });
    }
    bucket.count += 1;
    await this.state.storage.put("bucket", bucket);
    return new Response(null, {
      status: 204,
      headers: {
        "x-rate-limit-remaining": String(Math.max(0, limit - bucket.count)),
        "x-rate-limit-reset": String(Math.ceil(bucket.resetAt / 1_000)),
      },
    });
  }
}

async function readBodyWithLimit(request: Request, maximumBytes: number): Promise<ArrayBuffer> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new RequestProblem(413, "payload_too_large", "The request body is too large.");
  }
  const body = await request.arrayBuffer();
  if (body.byteLength > maximumBytes) {
    throw new RequestProblem(413, "payload_too_large", "The request body is too large.");
  }
  return body;
}

function requireContentType(request: Request, expected: string): void {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith(expected)) {
    throw new RequestProblem(415, "unsupported_media_type", `Content-Type must be ${expected}.`);
  }
}

function allowedModels(env: Env): Set<string> {
  const configured = env.OPENROUTER_MODEL_ALLOWLIST ?? DEFAULT_MODEL;
  return new Set(configured.split(",").map((model) => model.trim()).filter(Boolean));
}

function validateOrigin(request: Request, env: Env, requestID: string): Response | null {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  if (allowedOrigins(env).has(origin)) return null;
  return errorResponse(403, "origin_not_allowed", "This request origin is not allowed.", requestID, request, env);
}

function preflightResponse(request: Request, env: Env, requestID: string): Response {
  const origin = request.headers.get("origin");
  if (!origin || !allowedOrigins(env).has(origin)) {
    return errorResponse(403, "origin_not_allowed", "This request origin is not allowed.", requestID, request, env);
  }
  const requestedMethod = request.headers.get("access-control-request-method");
  if (requestedMethod !== "POST") return methodNotAllowed("POST", requestID);
  return new Response(null, {
    status: 204,
    headers: responseHeaders(requestID, request, env, {
      "access-control-allow-methods": "POST",
      "access-control-allow-headers": `content-type, ${CLIENT_HEADER}, ${LANGUAGE_HEADER}`,
      "access-control-max-age": "600",
    }),
  });
}

function allowedOrigins(env: Env): Set<string> {
  return new Set((env.ALLOWED_ORIGINS ?? "").split(",").map((origin) => origin.trim()).filter(Boolean));
}

function methodNotAllowed(allow: string, requestID: string): Response {
  return new Response(
    JSON.stringify({ error: { code: "method_not_allowed", message: "The request method is not allowed." } }),
    {
      status: 405,
      headers: responseHeaders(requestID, undefined, undefined, { allow }),
    },
  );
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  requestID: string,
  request?: Request,
  env?: Env,
  additionalHeaders?: HeadersInit,
): Response {
  const body: ErrorBody = { error: { code, message } };
  return jsonResponse(body, status, requestID, request, env, additionalHeaders);
}

function jsonResponse(
  body: unknown,
  status: number,
  requestID: string,
  request?: Request,
  env?: Env,
  additionalHeaders?: HeadersInit,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(requestID, request, env, additionalHeaders),
  });
}

function responseHeaders(
  requestID: string,
  request?: Request,
  env?: Env,
  additionalHeaders?: HeadersInit,
): Headers {
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    pragma: "no-cache",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
    "x-request-id": requestID,
    vary: "Origin",
  });
  const origin = request?.headers.get("origin");
  if (origin && env && allowedOrigins(env).has(origin)) {
    headers.set("access-control-allow-origin", origin);
  }
  if (additionalHeaders) {
    new Headers(additionalHeaders).forEach((value, key) => headers.set(key, value));
  }
  return headers;
}

function extractOpenRouterText(input: unknown): string | null {
  if (!isRecord(input) || !Array.isArray(input.choices)) return null;
  const first = input.choices[0];
  if (!isRecord(first) || !isRecord(first.message)) return null;
  const content = first.message.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return null;
  return content
    .map((part) => (isRecord(part) && typeof part.text === "string" ? part.text : ""))
    .filter(Boolean)
    .join("\n");
}

async function safeJSON(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw new RequestProblem(502, "invalid_provider_response", "The processing service returned an invalid response.");
  }
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function positiveInteger(value: string | null, minimum: number, maximum: number): number | null {
  if (!value || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= minimum && parsed <= maximum ? parsed : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

class RequestProblem extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}
