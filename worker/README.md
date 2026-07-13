# BuddyGrammar Worker

Cloudflare Worker proxy for BuddyGrammar's correction and transcription calls. Provider credentials exist only as encrypted Worker secret bindings; they are never sent to or stored by the iOS app or keyboard extension.

## API

Every `POST` requires `X-BuddyGrammar-Client-ID`, a stable per-install identifier containing 16–128 letters, digits, dots, underscores, or hyphens. The iOS app generates it once and shares it with the keyboard through the App Group. Native iOS requests do not send an `Origin` header. Browser origins are rejected unless explicitly listed in `ALLOWED_ORIGINS`.

- `GET /health` returns `{ "status": "ok" }`, or the generic `{ "status": "unavailable" }` when either provider binding is missing.
- `POST /v1/correct` accepts `application/json`:

  ```json
  {
    "text": "this need fixing",
    "modelID": "openai/gpt-5.4-nano",
    "instruction": "Correct grammar and punctuation only."
  }
  ```

  It returns `{ "text": "This needs fixing." }`. Models must appear in the comma-separated `OPENROUTER_MODEL_ALLOWLIST`. Each OpenRouter request sets `provider.zdr` to `true` and `provider.data_collection` to `deny`, restricting routing to Zero Data Retention endpoints that do not collect user data.

- `POST /v1/transcribe` accepts the M4A recording bytes directly with `Content-Type: audio/mp4`. Send the optional language in `X-Buddy-Language-Code`. It returns the ElevenLabs-compatible fields `text`, `language_code`, and `language_probability`. The Worker, not the client, constructs ElevenLabs' multipart request and server-controlled fields.

The Worker rejects unexpected fields, oversized payloads, unsupported content types, disallowed models/origins, and malformed language/client identifiers. It returns generic provider errors and does not log prompt, completion, or audio content. Wrangler observability is disabled in `wrangler.toml`.

The Durable Object limiter enforces both per-install and per-IP fixed windows: correction is limited to 30/client/minute and 180/IP/minute; transcription to 8/client/minute and 40/IP/minute. The client identifier is hashed before being used as the Durable Object name. This controls ordinary misuse but is not proof that a request came from the signed app; add Apple App Attest before a broad public launch.

## Local checks

```bash
cd worker
bun install
bun test
bun run check
```

Local development uses Wrangler:

```bash
bunx wrangler dev
```

Use `.dev.vars` for local-only credentials and never commit that file.

## Deployment without exposing Doppler values

The checked-in script uses the authenticated Doppler CLI and pipes each value directly into Wrangler. It defaults to `buddybox/dev_personal` for `OPENROUTER_API_KEY` and `mao-mao/prd` for `ELEVENLABS_API_KEY`. Review or override those source selectors before running it.

```bash
cd worker
bun install
./scripts/deploy-with-doppler.sh
```

Equivalent secret-only commands are:

```bash
/opt/homebrew/bin/doppler secrets get OPENROUTER_API_KEY --plain --project buddybox --config dev_personal \
  | bunx wrangler secret put OPENROUTER_API_KEY --name buddygrammar-api

/opt/homebrew/bin/doppler secrets get ELEVENLABS_API_KEY --plain --project mao-mao --config prd \
  | bunx wrangler secret put ELEVENLABS_API_KEY --name buddygrammar-api
```

Do not use `doppler secrets download`, place secrets in `wrangler.toml`, or copy values into Xcode build settings. The script is intentionally not run by tests or setup.
