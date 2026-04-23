# MacBook Setup Guide

This guide covers setting up the MacBook as the primary node running the Architect and Verifier agents.

## Prerequisites

- Apple Silicon Mac with 128GB+ unified memory (M4 Max recommended)
- macOS 14+ (Sonoma or later)
- Homebrew installed
- Tailscale installed and connected to your mesh
- Docker Desktop installed

## 1. Install OpenClaw

```bash
# Install via npm (or follow openclaw.dev instructions)
npm install -g openclaw

# Initialize workspace
openclaw init
```

This creates `~/.openclaw/` with default configuration.

## 2. Install Ollama

```bash
brew install ollama

# Pull the model (this will download ~76GB)
ollama pull huihui_ai/qwen3.5-abliterated:122b

# Verify it's running
curl http://127.0.0.1:11434/v1/models
```

Ollama runs as a background service automatically after `brew install`. If you need to manage it manually:

```bash
brew services start ollama
brew services stop ollama
brew services restart ollama
```

## 3. Configure OpenClaw

Copy the template config:

```bash
cp config-templates/openclaw.macbook.template.json ~/.openclaw/openclaw.json
```

Edit `~/.openclaw/openclaw.json` and replace all `YOUR_*` placeholders:

- `YOUR_VLLM_API_KEY` — API key for vLLM on GB10
- `YOUR_GATEWAY_TOKEN` — generate with `openssl rand -hex 24`
- `YOUR_TELEGRAM_BOT_TOKEN` — from BotFather for the Architect bot
- `YOUR_VERIFIER_BOT_TOKEN` — from BotFather for the Verifier bot
- `YOUR_TELEGRAM_USER_ID` — your Telegram numeric user ID
- `YOUR_TELEGRAM_GROUP_ID` — your Telegram group chat ID
- `YOUR_FASTIO_API_KEY` — Fast.io API key (if using)
- `YOUR_TAVILY_API_KEY` — Tavily web search API key
- `YOUR_GB10_TAILSCALE_IP` — Tailscale IP of your GB10 server

## 4. Install SOUL Files

```bash
# Architect SOUL (read by the main agent)
cp souls/architect-SOUL.md ~/.openclaw/SOUL.md
cp souls/architect-SOUL.md ~/.openclaw/workspace/SOUL.md

# Verifier SOUL (read by the verifier agent)
cp souls/verifier-SOUL.md ~/.openclaw/workspace-verifier/SOUL.md
```

## 5. Set Up Flux (Task Management)

See [FLUX-MCP.md](FLUX-MCP.md) for full details. Quick version:

```bash
# Build the Docker image
bash scripts/setup-flux-docker.sh

# Create data directory
mkdir -p ~/.flux-data

# Start the web server (for GB10 remote access)
docker run -d --name flux-web \
    -p 3000:3000 \
    -v ~/.flux-data:/app/packages/data \
    flux-mcp

# Verify MCP works (should see JSON-RPC response)
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | \
    docker run -i --rm \
    -v ~/.flux-data:/app/packages/data \
    -v ~/.flux-data/blobs:/home/flux \
    -e FLUX_DATA=/app/packages/data/flux.sqlite \
    -e HOME=/app/packages/data \
    flux-mcp bun packages/mcp/dist/index.js
```

## 6. Install Lossless-Claw

```bash
openclaw plugin install @martian-engineering/lossless-claw
```

The plugin config is already in the template `openclaw.json`. Key settings:

- `contextThreshold: 0.8` — compact at 80% context usage
- `freshTailCount: 48` — preserve last 48 messages
- `summaryModel` — uses the primary model for compaction summaries

## 7. Set Up Cron Jobs

```bash
# Architect task loop — fires every 15 minutes
openclaw cron add \
    --every "15m" \
    --agent main \
    --session isolated \
    --timeout-seconds 600 \
    --message "CRON TASK CHECK: Call list_ready_tasks via Flux MCP. Pick the highest priority P0 task in your domain (frontend/UI/architecture) not in doing status. Move it to doing, execute the work on a feature branch, commit, push, move to done. If you fail 3 edits on a file, skip it and add a note. If all your tasks are done or blocked, post a status to Telegram."
```

## 8. Start the Gateway

```bash
openclaw gateway start
```

The gateway runs on port 18789 by default and handles Telegram channels, cron scheduling, and agent sessions.

## 9. Verify Everything

```bash
bash scripts/health-check.sh
```

This checks: Ollama responsiveness, Flux MCP connectivity, OpenClaw gateway status, Tailscale connectivity to GB10, and cron job registration.

## Maintenance

### Session Cleanup

Large session files (1MB+) slow down local models. Archive old sessions periodically:

```bash
# Check session sizes
du -sh ~/.openclaw/agents/main/sessions/*.jsonl | sort -rh | head -10

# Archive bloated sessions
mkdir -p ~/.openclaw/sessions-archive
mv ~/.openclaw/agents/main/sessions/OLD_SESSION_ID.jsonl ~/.openclaw/sessions-archive/
```

### Log Locations

- Ollama: `~/.ollama/logs/server.log`
- OpenClaw: `~/.openclaw/gateway.log` (if configured)
- Flux web: `docker logs flux-web`

### Restarting Services

```bash
# Restart Ollama
brew services restart ollama

# Restart OpenClaw gateway
openclaw gateway restart

# Restart Flux web server
docker restart flux-web
```
