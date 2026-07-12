#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source .env 2>/dev/null || true
unset DEBUG

CONFIG="${SCRIPT_DIR}/config-desktop.yaml"

if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" << 'YAML'
model_list:

  - model_name: claude-fable-5
    litellm_params:
      model: openai/moonshotai/kimi-k2.6
      api_base: https://integrate.api.nvidia.com/v1
      api_key: os.environ/NVIDIA_NIM_API_KEY
      timeout: 120
      stream_timeout: 120
      rpm: 30

  - model_name: claude-opus-4-8
    litellm_params:
      model: openai/minimaxai/minimax-m2.7
      api_base: https://integrate.api.nvidia.com/v1
      api_key: os.environ/NVIDIA_NIM_API_KEY
      timeout: 120
      stream_timeout: 120
      rpm: 30

  - model_name: claude-sonnet-5
    litellm_params:
      model: openai/moonshotai/kimi-k2.6
      api_base: https://api.cloudflare.com/client/v4/accounts/__CLOUDFLARE_ACCOUNT_ID__/ai/v1
      api_key: os.environ/CLOUDFLARE_WORKER_AI_API_KEY
      timeout: 120
      stream_timeout: 120
      rpm: 100

  - model_name: claude-sonnet-4-6
    litellm_params:
      model: openai/kilo-auto/free
      api_base: https://api.kilo.ai/api/gateway
      api_key: os.environ/KILO_API_KEY
      timeout: 90
      stream_timeout: 90
      rpm: 40

  - model_name: claude-haiku-4-5-20251001
    litellm_params:
      model: openai/kilo-auto/free
      api_base: https://api.kilo.ai/api/gateway
      api_key: os.environ/KILO_API_KEY_1
      timeout: 90
      stream_timeout: 90
      rpm: 40

  - model_name: claude-opus-4-7
    litellm_params:
      model: openai/kilo-auto/free
      api_base: https://api.kilo.ai/api/gateway
      api_key: os.environ/KILO_API_KEY_2
      timeout: 90
      stream_timeout: 90
      rpm: 40

  - model_name: claude-opus-4-6
    litellm_params:
      model: openai/kilo-auto/free
      api_base: https://api.kilo.ai/api/gateway
      api_key: os.environ/KILO_API_KEY_3
      timeout: 90
      stream_timeout: 90
      rpm: 40

  - model_name: claude-sonnet-4-5-20250929
    litellm_params:
      model: openrouter/openrouter/free
      api_key: os.environ/OPENROUTER_API_KEY_0
      timeout: 90
      stream_timeout: 90

  - model_name: claude-opus-4-5-20251101
    litellm_params:
      model: openrouter/openrouter/free
      api_key: os.environ/OPENROUTER_API_KEY_1
      timeout: 90
      stream_timeout: 90

  - model_name: claude-sonnet-4-7-20260710
    litellm_params:
      model: openai/deepseek-ai/deepseek-v4-flash
      api_base: https://integrate.api.nvidia.com/v1
      api_key: os.environ/NVIDIA_NIM_API_KEY
      timeout: 120
      stream_timeout: 120
      rpm: 30

  - model_name: claude-opus-4-9-20260710
    litellm_params:
      model: openai/deepseek-ai/deepseek-v4-pro
      api_base: https://integrate.api.nvidia.com/v1
      api_key: os.environ/NVIDIA_NIM_API_KEY
      timeout: 120
      stream_timeout: 120
      rpm: 30

  - model_name: claude-sonnet-4-8-20260710
    litellm_params:
      model: openai/z-ai/glm-5.2
      api_base: https://integrate.api.nvidia.com/v1
      api_key: os.environ/NVIDIA_NIM_API_KEY
      timeout: 120
      stream_timeout: 120
      rpm: 30

litellm_settings:
  drop_params: true
  set_verbose: false
  request_timeout: 120
  num_retries: 2
YAML
  sed -i "s/__CLOUDFLARE_ACCOUNT_ID__/${CLOUDFLARE_WORKER_AI_ACCOUNT_ID}/g" "$CONFIG"
  echo "  Created $CONFIG"
fi

VENV_DIR="${SCRIPT_DIR}/.venv"
if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install -q litellm
fi

ENV_JSON="${SCRIPT_DIR}/env.json"
echo "{" > "$ENV_JSON"
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" == "#"* ]] && continue
  printf '  "%s": "%s",\n' "$key" "$val"
done < "${SCRIPT_DIR}/.env" | sed '$ s/,$//' >> "$ENV_JSON"
echo "}" >> "$ENV_JSON"
echo "  Wrote $ENV_JSON"

echo "Starting Claude stack..."

nohup "$VENV_DIR/bin/litellm" --config "$CONFIG" --port 4001 &>/tmp/litellm.log &
echo "  4001: LiteLLM PID $!"

sleep 8

echo ""
echo "Done. Point Claude CLI/Desktop at http://localhost:4001"
echo "Env JSON: $ENV_JSON"
