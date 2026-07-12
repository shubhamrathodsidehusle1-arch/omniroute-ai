#!/bin/sh
set -e

mkdir -p /root/.hermes

OMNIROUTE_URL="${OMNIROUTE_URL:-http://omniroute:20128}"
OMNI_ROUTE_API_KEY="${OMNI_ROUTE_API_KEY}"

cat > /root/.hermes/.env <<EOF
ANTHROPIC_BASE_URL=${OMNIROUTE_URL}
ANTHROPIC_API_KEY=${OMNI_ROUTE_API_KEY}
OPENAI_BASE_URL=${OMNIROUTE_URL}/v1
OPENAI_API_KEY=${OMNI_ROUTE_API_KEY}
OMNIROUTE_URL=${OMNIROUTE_URL}
TELEGRAM_BOT_TOKEN=${HERMES_TELEGRAM_BOT_TOKEN:-}
EOF

PASSWORD_HASH=$(/hermes-agent/.venv/bin/python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('${HERMES_ADMIN_PASSWORD:?HERMES_ADMIN_PASSWORD is required}'))")
cat > /root/.hermes/config.yaml <<EOF
dashboard:
  basic_auth:
    username: admin
    password_hash: ${PASSWORD_HASH}
model:
  provider: custom
  default: auto/best-free
  base_url: ${OMNIROUTE_URL}/v1
  api_key: ${OMNI_ROUTE_API_KEY}
EOF

# Build web frontend once if not cached
if [ ! -d /hermes-agent/hermes_cli/web_dist ]; then
  apk add --no-cache npm 2>/dev/null
  cd /hermes-agent/web && npm install -q 2>/dev/null && npm run build 2>/dev/null
fi

echo "Starting Hermes gateway in background..."
/hermes-agent/.venv/bin/hermes gateway run > /tmp/gateway.log 2>&1 &
GATEWAY_PID=$!
echo "Gateway PID: $GATEWAY_PID"

echo "Starting Hermes dashboard..."
exec /hermes-agent/.venv/bin/hermes dashboard --port 9119 --host 0.0.0.0
