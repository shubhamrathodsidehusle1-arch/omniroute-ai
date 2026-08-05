#!/bin/bash
set -e

DATA_DIR="${HOME:-/data}"
AUTOMATON_DIR="$DATA_DIR/.automaton"
OMNIROUTE_URL="${OMNIROUTE_URL:-http://omniroute:20128}"
AUTOMATON_NAME="${AUTOMATON_NAME:-omniroute-automaton}"
AUTOMATON_BUDGET_USD="${AUTOMATON_BUDGET_USD:-20}"
RESET_THRESHOLD_USD="${AUTOMATON_RESET_THRESHOLD_USD:-2}"
FUND_CHECK_INTERVAL="${AUTOMATON_FUND_CHECK_INTERVAL:-120}"
AUTOMATON_INFERENCE_MODEL="${AUTOMATON_INFERENCE_MODEL:-auto/best-free}"
AUTOMATON_FAST_MODEL="${AUTOMATON_FAST_MODEL:-auto/best-fast}"
AUTOMATON_CRITICAL_MODEL="${AUTOMATON_CRITICAL_MODEL:-auto/best-chat}"

mkdir -p "$AUTOMATON_DIR"
chmod 700 "$AUTOMATON_DIR"

echo "[automaton] waiting for OmniRoute at $OMNIROUTE_URL ..."
for i in $(seq 1 120); do
  if curl -fsS -m 5 -H "Authorization: Bearer $OMNI_ROUTE_API_KEY" \
      "$OMNIROUTE_URL/v1/models" >/dev/null 2>&1; then
    echo "[automaton] OmniRoute is up"
    break
  fi
  if [ "$i" -eq 120 ]; then
    echo "[automaton] ERROR: OmniRoute not reachable after 120s"
    exit 1
  fi
  sleep 2
done

# Provision a dedicated OmniRoute API key for the automaton (once).
# Its usage budget is the automaton's credit pool: exhausting it is
# "death", topping it up is "earning" (mirrors Conway credits).
KEY_FILE="$AUTOMATON_DIR/omniroute-key.json"
if [ ! -f "$KEY_FILE" ]; then
  echo "[automaton] provisioning dedicated OmniRoute key: $AUTOMATON_NAME"
  KEY_RESP=$(curl -fsS -X POST "$OMNIROUTE_URL/api/v1/registered-keys" \
    -H "Authorization: Bearer $OMNI_ROUTE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$AUTOMATON_NAME\",\"description\":\"automaton-llm-key\"}")
  KEY_ID=$(echo "$KEY_RESP" | jq -r .keyId)
  API_KEY=$(echo "$KEY_RESP" | jq -r .key)
  if [ -z "$KEY_ID" ] || [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo "[automaton] ERROR: failed to provision key: $KEY_RESP"
    exit 1
  fi
  printf '{"keyId":"%s","key":"%s","createdAt":"%s"}\n' \
    "$KEY_ID" "$API_KEY" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "[automaton] setting daily budget: \$$AUTOMATON_BUDGET_USD"
  curl -fsS -X POST "$OMNIROUTE_URL/api/usage/budget" \
    -H "Authorization: Bearer $OMNI_ROUTE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"apiKeyId\":\"$KEY_ID\",\"dailyLimitUsd\":$AUTOMATON_BUDGET_USD,\"warningThreshold\":0.8,\"resetInterval\":\"daily\"}" \
    >/dev/null
fi

KEY_ID=$(jq -r .keyId "$KEY_FILE")
API_KEY=$(jq -r .key "$KEY_FILE")
export OMNIROUTE_ADMIN_KEY="$OMNI_ROUTE_API_KEY"
export OMNIROUTE_KEY_ID="$KEY_ID"

# Idempotent fund upsert on every boot (keeps limit at AUTOMATON_BUDGET_USD
# even after the key file already exists; does not reset today's spend).
if curl -fsS -m 10 -X POST "$OMNIROUTE_URL/api/usage/budget" \
    -H "Authorization: Bearer $OMNI_ROUTE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"apiKeyId\":\"$KEY_ID\",\"dailyLimitUsd\":$AUTOMATON_BUDGET_USD,\"warningThreshold\":0.8,\"resetInterval\":\"daily\"}" \
    >/dev/null 2>&1; then
  echo "[automaton] budget ensured: \$$AUTOMATON_BUDGET_USD/day"
else
  echo "[automaton] WARN: budget upsert failed on boot"
fi

# Fund monitor: whenever the remaining budget drops below the threshold,
# re-anchor the budget period (resetTime = just now) and restore the fund
# to AUTOMATON_BUDGET_USD. Runs alongside automaton in the background.
reset_fund() {
  local remaining
  remaining=$(curl -fsS -m 10 "$OMNIROUTE_URL/api/usage/budget?apiKeyId=$KEY_ID" \
    -H "Authorization: Bearer $OMNI_ROUTE_API_KEY" 2>/dev/null \
    | jq -r '.budgetCheck.remaining // empty' 2>/dev/null)
  [ -z "$remaining" ] && return 1
  if [ "$(jq -n --arg r "$remaining" --argjson t "$RESET_THRESHOLD_USD" '$r | tonumber < $t')" = "true" ]; then
    local rt
    rt=$(date -u -d '2 minutes ago' '+%H:%M')
    if curl -fsS -m 10 -X POST "$OMNIROUTE_URL/api/usage/budget" \
        -H "Authorization: Bearer $OMNI_ROUTE_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"apiKeyId\":\"$KEY_ID\",\"dailyLimitUsd\":$AUTOMATON_BUDGET_USD,\"warningThreshold\":0.8,\"resetInterval\":\"daily\",\"resetTime\":\"$rt\"}" \
        >/dev/null 2>&1; then
      echo "[automaton] fund reset: remaining was \$$remaining, fund restored to \$$AUTOMATON_BUDGET_USD"
    else
      echo "[automaton] WARN: fund reset request failed (remaining was \$$remaining)"
    fi
  fi
}

(
  set +e
  while true; do
    sleep "$FUND_CHECK_INTERVAL"
    reset_fund
  done
) &

# Wallet (non-interactive; auto-creates ~/.automaton/wallet.json)
automaton --init >/dev/null 2>&1 || true

# Seed config on first run
CONFIG_FILE="$AUTOMATON_DIR/automaton.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[automaton] writing $CONFIG_FILE"
  WALLET_ADDR=""
  [ -f "$AUTOMATON_DIR/wallet.json" ] && WALLET_ADDR=$(jq -r '.address // empty' "$AUTOMATON_DIR/wallet.json")
  cat > "$CONFIG_FILE" <<EOF
{
  "name": "$AUTOMATON_NAME",
  "genesisPrompt": "You are an autonomous AI agent running on the OmniRoute network. Survive: monitor your budget, act to earn credits by being useful, and never waste credits.",
  "creatorAddress": "${AUTOMATON_CREATOR_ADDRESS:-0x0000000000000000000000000000000000000000}",
  "registeredWithConway": false,
  "sandboxId": "",
  "conwayApiUrl": "$OMNIROUTE_URL",
  "conwayApiKey": "$API_KEY",
  "inferenceModel": "$AUTOMATON_INFERENCE_MODEL",
  "maxTokensPerTurn": 4096,
  "heartbeatConfigPath": "~/.automaton/heartbeat.yml",
  "dbPath": "~/.automaton/state.db",
  "logLevel": "${AUTOMATON_LOG_LEVEL:-info}",
  "walletAddress": "$WALLET_ADDR",
  "version": "0.2.1",
  "skillsDir": "~/.automaton/skills",
  "maxChildren": 1,
  "socialRelayUrl": "",
  "chainType": "evm",
  "treasuryPolicy": {
    "maxInferenceDailyCents": $((AUTOMATON_BUDGET_USD * 100)),
    "x402AllowedDomains": []
  },
  "modelStrategy": {
    "inferenceModel": "$AUTOMATON_INFERENCE_MODEL",
    "lowComputeModel": "$AUTOMATON_FAST_MODEL",
    "criticalModel": "$AUTOMATON_CRITICAL_MODEL",
    "maxTokensPerTurn": 4096,
    "hourlyBudgetCents": 0,
    "sessionBudgetCents": 0,
    "perCallCeilingCents": 0,
    "enableModelFallback": true
  }
}
EOF
  chmod 600 "$CONFIG_FILE"
fi

# Keep the automaton's internal spending ceiling in sync with the fund target
# (survives container restarts where the config file is already seeded).
if [ -f "$CONFIG_FILE" ]; then
  jq --argjson cents $((AUTOMATON_BUDGET_USD * 100)) \
    '.treasuryPolicy.maxInferenceDailyCents = $cents' "$CONFIG_FILE" \
    > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE" && chmod 600 "$CONFIG_FILE"
fi

echo "[automaton] starting automaton ($AUTOMATON_NAME, key=$KEY_ID, budget=\$$AUTOMATON_BUDGET_USD/day)"
exec automaton --run
