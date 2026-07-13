#!/usr/bin/env bash
set -euo pipefail

# Values move directly from Doppler stdout to Wrangler stdin. This script never
# stores or prints either provider key. Run only after reviewing the source.
DOPPLER_BIN="${DOPPLER_BIN:-/opt/homebrew/bin/doppler}"
WORKER_NAME="${WORKER_NAME:-buddygrammar-api}"
OPENROUTER_DOPPLER_PROJECT="${OPENROUTER_DOPPLER_PROJECT:-buddybox}"
OPENROUTER_DOPPLER_CONFIG="${OPENROUTER_DOPPLER_CONFIG:-dev_personal}"
ELEVENLABS_DOPPLER_PROJECT="${ELEVENLABS_DOPPLER_PROJECT:-mao-mao}"
ELEVENLABS_DOPPLER_CONFIG="${ELEVENLABS_DOPPLER_CONFIG:-prd}"

if [[ ! -x "$DOPPLER_BIN" ]]; then
  echo "Doppler CLI not found at $DOPPLER_BIN" >&2
  exit 1
fi

bunx wrangler deploy

"$DOPPLER_BIN" secrets get OPENROUTER_API_KEY --plain \
  --project "$OPENROUTER_DOPPLER_PROJECT" \
  --config "$OPENROUTER_DOPPLER_CONFIG" \
  | bunx wrangler secret put OPENROUTER_API_KEY --name "$WORKER_NAME"

"$DOPPLER_BIN" secrets get ELEVENLABS_API_KEY --plain \
  --project "$ELEVENLABS_DOPPLER_PROJECT" \
  --config "$ELEVENLABS_DOPPLER_CONFIG" \
  | bunx wrangler secret put ELEVENLABS_API_KEY --name "$WORKER_NAME"

echo "Worker deployed and provider secret bindings updated."
