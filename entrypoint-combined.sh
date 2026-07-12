#!/bin/sh
set -e

OMNIROUTE_URL="${OMNIROUTE_URL:-http://omniroute:20128}"
OMNI_ROUTE_API_KEY="${OMNI_ROUTE_API_KEY}"

mkdir -p /root/.openclaw /data

# Seed default config if not present (preserves custom provider models)
if [ ! -f /root/.openclaw/openclaw.json ] && [ -f /configs/openclaw.json ]; then
  cp /configs/openclaw.json /root/.openclaw/openclaw.json
fi

export OPENAI_API_KEY="${OPENAI_API_KEY:-${OMNI_ROUTE_API_KEY}}"
export OPENAI_BASE_URL="${OMNIROUTE_URL}/v1"

openclaw setup 2>/dev/null || true
openclaw config set gateway.mode local 2>/dev/null || true
openclaw config set gateway.port 18789 2>/dev/null || true
openclaw config set gateway.bind auto 2>/dev/null || true
openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true 2>/dev/null || true
openclaw config set gateway.controlUi.allowedOrigins '["*"]' 2>/dev/null || true
openclaw config set gateway.trustedProxies '["0.0.0.0/0"]' 2>/dev/null || true

openclaw config set models.providers.anthropic.api anthropic-messages 2>/dev/null || true
openclaw config set models.providers.anthropic.baseUrl "${OMNIROUTE_URL}" 2>/dev/null || true
openclaw config set models.providers.anthropic.apiKey "${OMNI_ROUTE_API_KEY}" 2>/dev/null || true
openclaw config set models.providers.kg.api "openai-completions" 2>/dev/null || true
openclaw config set models.providers.kg.baseUrl "${OMNIROUTE_URL}" 2>/dev/null || true
openclaw config set models.providers.kg.apiKey "${OMNI_ROUTE_API_KEY}" 2>/dev/null || true

openclaw config set models.providers.or.baseUrl "${OMNIROUTE_URL}" 2>/dev/null || true
openclaw config set models.providers.or.apiKey "${OMNI_ROUTE_API_KEY}" 2>/dev/null || true
openclaw config set agents.defaults.model.primary "or/auto/best-free" 2>/dev/null || true

if [ -n "$OPENCLAW_TELEGRAM_BOT_TOKEN" ]; then
  if ! openclaw channels list 2>/dev/null | grep -q "telegram"; then
    echo "Configuring Telegram channel..."
    timeout 30 openclaw channels add --channel telegram --token "$OPENCLAW_TELEGRAM_BOT_TOKEN" 2>/dev/null || true
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
PORT=3333 DASHBOARD_AUTH_MODE=none node lib/server.js &

wait
