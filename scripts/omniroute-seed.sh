#!/bin/sh
set -e

DB=/app/data/storage.sqlite
ENV=/app/data/server.env

wait_for_db() {
  echo "Waiting for OmniRoute database..."
  for i in $(seq 1 30); do
    if [ -f "$DB" ] && sqlite3 "$DB" ".tables" 2>/dev/null | grep -q provider_connections; then
      echo "Database ready."
      return 0
    fi
    sleep 2
  done
  echo "ERROR: Database not ready after 60s"
  exit 1
}

encrypt_key() {
  local key="$1"
  node -e "
    const crypto = require('crypto');
    const storageKey = require('fs').readFileSync('/app/data/server.env','utf8')
      .split('\n').find(l=>l.startsWith('STORAGE_ENCRYPTION_KEY='))
      .split('=')[1].trim();
    const salt = crypto.createHash('sha256').update(storageKey).digest('hex').slice(0,16);
    const derivedKey = crypto.scryptSync(storageKey, salt, 32);
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', derivedKey, iv);
    const enc = Buffer.concat([cipher.update('$key','utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    console.log('enc:v1:' + iv.toString('hex') + ':' + enc.toString('hex') + ':' + tag.toString('hex'));
  "
}

seed_if_missing() {
  local id="$1"
  local e_id=$(sqlesc "$id")
  local exists=$(sqlite3 "$DB" "SELECT COUNT(*) FROM provider_connections WHERE id='$e_id';" 2>/dev/null)
  [ "$exists" -gt 0 ] && return 1
  return 0
}

NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
COLS="id,provider,auth_type,name,priority,is_active,test_status,proxy_enabled,per_key_proxy_enabled,provider_specific_data,access_token,created_at,updated_at"
BASE="1,1,'active',1,0"

sqlesc() { printf "%s" "$1" | sed "s/'/''/g"; }

seed_single() {
  local id="$1" provider="$2" name="$3" key="$4" extra="$5"
  seed_if_missing "$id" || return 0
  JSON="{\"name\":\"${name}\",\"apiKey\":\"${key}\",\"baseUrl\":\"${extra}\""
  [ -n "$6" ] && JSON="$JSON,\"accountId\":\"$6\",\"region\":\"us-east-1\""
  JSON="$JSON,\"apiKeyHealth\":{}}"
  local e_id=$(sqlesc "$id") e_provider=$(sqlesc "$provider") e_name=$(sqlesc "$name") e_json=$(sqlesc "$JSON") e_key=$(sqlesc "$key")
  sqlite3 "$DB" "INSERT INTO provider_connections ($COLS) VALUES ('$e_id','$e_provider','apikey','$e_name',$BASE,'$e_json','$e_key','$NOW','$NOW');" && echo "  + $name"
}

seed_providers() {
  echo "Seeding provider connections..."

  # Cloudflare Workers AI
  if [ -n "$CLOUDFLARE_API_KEY" ] && [ -n "$CLOUDFLARE_ACCOUNT_ID" ]; then
    seed_single "seed-cloudflare-ai" "cloudflare-ai" "Cloudflare Workers AI" "$CLOUDFLARE_API_KEY" "https://api.cloudflare.com/client/v4/${CLOUDFLARE_ACCOUNT_ID}/ai/v1" "$CLOUDFLARE_ACCOUNT_ID"
  fi

  # NVIDIA NIM
  if [ -n "$NVIDIA_API_KEY" ]; then
    seed_single "seed-nvidia" "nvidia" "NVIDIA NIM" "$NVIDIA_API_KEY" "https://integrate.api.nvidia.com/v1"
  fi

  # OpenRouter (OPENROUTER_API_KEY_0..9)
  OR_BASE="https://openrouter.ai/api/v1"
  for i in $(seq 0 9); do
    var="OPENROUTER_API_KEY_$i"; key="${!var}"
    [ -z "$key" ] && continue
    seed_single "seed-openrouter-$i" "openrouter" "OpenRouter-$i" "$key" "$OR_BASE"
  done

  # KiloCode (KILO_API_KEY_1..3)
  KC_BASE="https://api.kilo.ai/api/gateway"
  for i in $(seq 1 3); do
    var="KILO_API_KEY_$i"; key="${!var}"
    [ -z "$key" ] && continue
    seed_single "seed-kilo-gateway-$i" "kilo-gateway" "KiloCode-$i" "$key" "$KC_BASE"
  done

  echo "Seeding complete."
}

wait_for_db
seed_providers
