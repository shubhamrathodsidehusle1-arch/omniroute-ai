# Open Hermes Claw

AI agent infrastructure stack — a docker-compose deployment of agent orchestration, LLM routing, workflow automation, vector storage, and observability services.

## Services

| Service | Port | Description |
|---------|------|-------------|
| **OpenClaw** | `3333` / `18789` | AI agent orchestration platform with visual dashboard and WebSocket gateway |
| **Hermes Agent** | `9119` | Autonomous AI agent service for task routing and agent-to-agent communication |
| **LiteLLM Proxy** | `4001` | Universal LLM gateway — routes to OpenRouter, Anthropic, NVIDIA NIM, Cloudflare Workers AI, and more |
| **n8n** | `5678` | Visual workflow automation engine |
| **G0DM0D3** | `17777` | Multi-model AI chat interface with model racing and AutoTune |
| **Paperclip** | `3100` | AI task orchestration — agent management, tasks, routines, governance |
| **Qdrant** | `6333` | High-performance vector search engine for agent memory and RAG |
| **Prometheus** | `9090` | Time-series monitoring and alerting |
| **Grafana** | `3000` | Observability dashboards |
| **OmniRoute** | `20128` | AI provider aggregation gateway (231+ providers, MCP/A2A) |
| **cAdvisor** | `8081` | Container resource metrics |
| **node-exporter** | `9100` | Host metrics |
| **nginx** | `80` | Static dashboard reverse-proxy |

Access any service at `http://localhost:<PORT>`.

## Quick Start

```bash
# 1. Copy and populate environment variables
cp .env.example .env   # edit with your API keys

# 2. Start all services
docker compose up -d

# 3. Open the dashboard
open http://localhost:80
```

The dashboard gives you one-click links to every service.

## Environment Variables

Copy `.env.example` to `.env` and configure at minimum:

| Variable | Required | Purpose |
|----------|----------|---------|
| `OPENROUTER_API_KEY` | Yes | LLM routing via OpenRouter |
| `OMNI_ROUTE_API_KEY` | For OmniRoute | Provider gateway API key |

See `.env.example` for the full list of supported variables.

## Architecture

All services run on a shared `claws-network` bridge network and can communicate by container hostname. External access is through `localhost:<PORT>` directly.

```
┌───────────────────┐
│   nginx:80         │  static dashboard
└────────┬──────────┘
         │
    ┌────┼────────────────────┐
    │    │                    │
    ▼    ▼                    ▼
 openclaw         hermes              litellm
 :3333/18789      :9119               :4001

    ▼                ▼                    ▼
   n8n           godmode3            paperclip
  :5678           :17777              :3100

    ▼                ▼                    ▼
  qdrant        prometheus            grafana
  :6333           :9090               :3000

    ▼
 omniroute
  :20128
```

## Custom Images

- **OpenClaw** — built from `Dockerfile.openclaw`, started via `entrypoint-openclaw.sh`
- **Hermes** — built from `Dockerfile.hermes`, started via `entrypoint-hermes.sh`
- **Paperclip** — built from `Dockerfile.paperclip`
