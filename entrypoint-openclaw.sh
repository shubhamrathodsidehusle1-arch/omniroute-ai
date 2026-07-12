#!/bin/sh
set -e

OMNIROUTE_URL="${OMNIROUTE_URL:-http://omniroute:20128}"
OMNI_ROUTE_API_KEY="${OMNI_ROUTE_API_KEY}"

mkdir -p /root/.openclaw

export OPENAI_API_KEY="${OPENAI_API_KEY:-${OMNI_ROUTE_API_KEY}}"
export OPENAI_BASE_URL="${OMNIROUTE_URL}/v1"

openclaw setup 2>/dev/null || true
openclaw config set gateway.mode local 2>/dev/null || true
openclaw config set gateway.port 18789 2>/dev/null || true
openclaw config set gateway.bind auto 2>/dev/null || true
openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true 2>/dev/null || true

openclaw config set models.providers.anthropic.api anthropic-messages 2>/dev/null || true
openclaw config set models.providers.anthropic.baseUrl "${OMNIROUTE_URL}" 2>/dev/null || true
openclaw config set models.providers.anthropic.apiKey "${OMNI_ROUTE_API_KEY}" 2>/dev/null || true
openclaw config set models.providers.kg.api "openai-completions" 2>/dev/null || true
openclaw config set models.providers.kg.baseUrl "${OMNIROUTE_URL}" 2>/dev/null || true
openclaw config set models.providers.kg.apiKey "${OMNI_ROUTE_API_KEY}" 2>/dev/null || true
openclaw config set agents.defaults.model.primary "kg/kilo-gateway/kilo-auto/free" 2>/dev/null || true

echo "Starting OpenClaw gateway on http://0.0.0.0:18789"
exec openclaw gateway --port 18789 --allow-unconfigured
