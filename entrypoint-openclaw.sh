#!/bin/sh
set -e

OMNIROUTE_URL="${OMNIROUTE_URL:-http://omniroute:20128}"
OMNI_ROUTE_API_KEY="${OMNI_ROUTE_API_KEY}"
GW_TOKEN="${OPENCLAW_GATEWAY_TOKEN}"

mkdir -p /root/.openclaw /data

# Seed default config if not present (preserves custom provider models)
if [ ! -f /root/.openclaw/openclaw.json ] && [ -f /configs/openclaw.json ]; then
  cp /configs/openclaw.json /root/.openclaw/openclaw.json
fi

export OPENAI_API_KEY="${OPENAI_API_KEY:-${OMNI_ROUTE_API_KEY}}"
export OPENAI_BASE_URL="${OMNIROUTE_URL}/v1"

timeout 10 openclaw setup 2>/dev/null || true

# Inject runtime config via jq (avoids interactive openclaw prompts)
jq --arg url "$OMNIROUTE_URL" --arg key "$OMNI_ROUTE_API_KEY" --arg token "$GW_TOKEN" \
  '.gateway.mode = "local"
   | .gateway.port = 18789
   | .gateway.bind = "auto"
   | .gateway.auth.mode = "token"
   | .gateway.auth.token = $token
   | .gateway.controlUi.dangerouslyDisableDeviceAuth = true
   | .gateway.controlUi.allowedOrigins = ["*"]
   | .gateway.trustedProxies = ["0.0.0.0/0"]
   | .models.providers.anthropic.api = "anthropic-messages"
   | .models.providers.anthropic.baseUrl = $url
   | .models.providers.anthropic.apiKey = $key
   | .models.providers.kg.api = "openai-completions"
   | .models.providers.kg.baseUrl = $url
   | .models.providers.kg.apiKey = $key
   | .models.providers.or.baseUrl = $url
   | .models.providers.or.apiKey = $key
   | .agents.defaults.model.primary = "or/auto/best-free"' \
  /root/.openclaw/openclaw.json > /tmp/openclaw.json \
  && mv /tmp/openclaw.json /root/.openclaw/openclaw.json

if [ -n "$OPENCLAW_TELEGRAM_BOT_TOKEN" ]; then
  CURRENT_TOKEN=$(jq -r '.channels.telegram.botToken // ""' /root/.openclaw/openclaw.json)
  if [ "$CURRENT_TOKEN" != "$OPENCLAW_TELEGRAM_BOT_TOKEN" ]; then
    echo "Configuring Telegram channel..."
    jq --arg token "$OPENCLAW_TELEGRAM_BOT_TOKEN" \
      '.channels.telegram.enabled = true | .channels.telegram.botToken = $token' \
      /root/.openclaw/openclaw.json > /tmp/openclaw.json \
      && mv /tmp/openclaw.json /root/.openclaw/openclaw.json
  fi
fi

echo "Starting OpenClaw gateway on http://0.0.0.0:18789"
openclaw gateway --port 18789 --allow-unconfigured &

if [ ! -f /data/server.js ]; then
  apk add --no-cache git
  git clone --depth 1 https://github.com/jontsai/openclaw-command-center /tmp/cc
  cp -r /tmp/cc/* /data/
  rm -rf /tmp/cc
fi

cd /data
echo "Starting Command Center on http://0.0.0.0:3333"
PORT=3333 node lib/server.js &

wait
