# OpenClaw Agent Mesh

A multi-machine, multi-agent development mesh built on [OpenClaw](https://openclaw.dev) for autonomous software development. This repository documents the full architecture and provides everything needed to reproduce a two-machine (or more) agent mesh where local LLMs collaborate via Telegram, shared task management (Flux), and automated cron-driven work loops.

## What This Is

Three AI agents — **Architect**, **Builder**, and **Verifier** — run across two Apple Silicon machines (a MacBook Pro and a GB10 server), each powered by local open-weight LLMs (Qwen3-Coder 262K context on GB10, Qwen3.5-122B on MacBook via Ollama). They autonomously pick tasks from a shared Flux task board, write code, commit to Gitea, review each other's work, and communicate through a Telegram group — all without human intervention.

## Architecture Overview

```
MacBook Pro (M4 Max, 128GB)          GB10 Server (192GB)
┌──────────────────────────┐         ┌──────────────────────────┐
│ OpenClaw Gateway         │         │ OpenClaw Gateway         │
│ ├── Architect Agent      │◄──────► │ ├── Builder Agent        │
│ └── Verifier Agent       │Tailscale│ └── (cron: every 15m)    │
│                          │         │                          │
│ Ollama (Qwen3.5-122B)   │         │ vLLM (Qwen3-Coder-Next) │
│ Flux MCP (Docker+SQLite) │         │ Flux MCP (Docker→remote) │
│ Telegram Channels        │         │ Telegram Channel         │
│ Lossless-Claw (context)  │         │ Lossless-Claw (context)  │
│ Memory-Core (dreaming)   │         │                          │
└──────────────────────────┘         └──────────────────────────┘
         │                                    │
         └──────────── Gitea (GB10:3030) ─────┘
                       Flux Web (MacBook:3000)
                       Telegram Group
```

## Key Components

**OpenClaw** — Agent runtime with session management, MCP tool integration, Telegram channels, cron scheduling, and context compaction (lossless-claw).

**Flux** — SQLite-backed task management accessible via MCP tools. Single source of truth for all task state. Runs as a Docker container on MacBook; GB10 connects over Tailscale.

**Lossless-Claw** — Context engine plugin that compacts long sessions to stay within model context windows. Configured at 80% threshold with 48-message fresh tail.

**Memory-Core** — Short-term recall promotion. Nightly cron job (4am ET) promotes frequently-recalled memories into persistent MEMORY.md.

**Tailscale** — Mesh VPN connecting MacBook and GB10 for inter-machine communication (model APIs, Flux, Gitea, SSH).

## Repository Structure

```
openclaw-agent-mesh/
├── README.md                          # This file
├── docs/
│   ├── ARCHITECTURE.md                # Detailed architecture and data flow
│   ├── SETUP-MACBOOK.md               # MacBook setup guide
│   ├── SETUP-GB10.md                  # GB10 / Linux server setup guide
│   ├── FLUX-MCP.md                    # Flux task management setup
│   └── TROUBLESHOOTING.md             # Common issues and fixes
├── config-templates/
│   ├── openclaw.macbook.template.json # MacBook openclaw.json (secrets stripped)
│   └── openclaw.gb10.template.json    # GB10 openclaw.json (secrets stripped)
├── souls/
│   ├── architect-SOUL.md              # Architect agent personality + instructions
│   ├── builder-SOUL.md                # Builder agent personality + instructions
│   └── verifier-SOUL.md              # Verifier agent personality + instructions
├── scripts/
│   ├── setup-ollama.sh                # Install and configure Ollama
│   ├── setup-flux-docker.sh           # Build and run Flux MCP Docker container
│   └── health-check.sh               # Verify all services are running
└── launchd/
    └── com.ollama.server.plist        # macOS LaunchAgent for Ollama
```

## Quick Start

### Prerequisites

- Two Apple Silicon Macs (or one Mac + one Linux server with NVIDIA GPU)
- [Tailscale](https://tailscale.com) mesh VPN connecting both machines
- [OpenClaw](https://openclaw.dev) installed on both machines
- [Ollama](https://ollama.com) or vLLM for local model inference
- [Docker](https://docker.com) for Flux MCP
- A Telegram bot token (one per agent) — see [BotFather](https://t.me/botfather)
- A Gitea instance (or GitHub) for code hosting

### 1. Set Up Models

**MacBook (Ollama):**
```bash
# Install Ollama
brew install ollama

# Pull the model
ollama pull huihui_ai/qwen3.5-abliterated:122b
```

**GB10 (vLLM):**
```bash
# Install vLLM with your GPU backend
pip install vllm

# Start serving
vllm serve huihui-ai/Huihui-Qwen3-Coder-Next-abliterated \
    --port 8000 --host 0.0.0.0 \
    --max-model-len 262144
```

### 2. Set Up Flux

See [docs/FLUX-MCP.md](docs/FLUX-MCP.md) for full instructions.

```bash
# Build the Flux Docker image
cd scripts && bash setup-flux-docker.sh
```

### 3. Configure OpenClaw

Copy the template configs and fill in your secrets:

```bash
cp config-templates/openclaw.macbook.template.json ~/.openclaw/openclaw.json
# Edit: add your Telegram bot tokens, API keys, Tailscale IPs
```

### 4. Install SOUL Files

```bash
cp souls/architect-SOUL.md ~/.openclaw/SOUL.md
cp souls/architect-SOUL.md ~/.openclaw/workspace/SOUL.md
cp souls/verifier-SOUL.md ~/.openclaw/workspace-verifier/SOUL.md
# Builder SOUL goes on GB10: scp souls/builder-SOUL.md gb10:~/.openclaw/SOUL.md
```

### 5. Set Up Cron Jobs

```bash
# MacBook — Architect task loop every 15 minutes
openclaw cron add --every "15m" --agent main --session isolated \
    --timeout-seconds 600 \
    --message "CRON TASK CHECK: Call list_ready_tasks via Flux MCP..."

# GB10 — Builder task loop every 15 minutes
ssh gb10 'openclaw cron add --every "15m" --agent main --session isolated \
    --timeout-seconds 600 \
    --message "CRON TASK CHECK: Call list_ready_tasks via Flux MCP..."'
```

### 6. Verify Everything

```bash
bash scripts/health-check.sh
```

## Security Notes

- **Never commit secrets.** The `.gitignore` excludes `*.secret`, `*.key`, `.env.local`, `secrets/`, and credential files.
- **Config templates use `YOUR_*` placeholders** for all sensitive values (API keys, bot tokens, auth tokens).
- **Tailscale IPs** are internal mesh addresses — not publicly routable, but still treat them as semi-private.
- **Device identity** (`~/.openclaw/identity/device.json`) contains Ed25519 keypairs — never commit this.

## License

MIT
