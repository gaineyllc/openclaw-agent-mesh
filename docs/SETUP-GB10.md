# GB10 Server Setup Guide

This guide covers setting up a secondary server (GB10 or similar) as the Builder agent node.

## Prerequisites

- Server with 192GB+ RAM and NVIDIA GPU (or Apple Silicon with 192GB+)
- Ubuntu 22.04+ (or equivalent)
- NVIDIA drivers + CUDA toolkit installed (for GPU inference)
- Tailscale installed and connected to your mesh
- Docker installed
- SSH access from MacBook

## 1. Install OpenClaw

```bash
npm install -g openclaw
openclaw init
```

## 2. Install vLLM

```bash
pip install vllm

# Start serving the model
vllm serve huihui-ai/Huihui-Qwen3-Coder-Next-abliterated \
    --port 8000 \
    --host 0.0.0.0 \
    --max-model-len 262144 \
    --api-key YOUR_VLLM_API_KEY
```

For production, create a systemd service:

```ini
# /etc/systemd/system/vllm.service
[Unit]
Description=vLLM Inference Server
After=network.target

[Service]
User=gaineyllc
ExecStart=/usr/local/bin/vllm serve huihui-ai/Huihui-Qwen3-Coder-Next-abliterated \
    --port 8000 --host 0.0.0.0 --max-model-len 262144 \
    --api-key YOUR_VLLM_API_KEY
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable vllm
sudo systemctl start vllm
```

## 3. Install Gitea

```bash
# Docker is the easiest path
docker run -d \
    --name gitea \
    -p 3030:3000 \
    -p 2222:22 \
    -v /data/gitea:/data \
    gitea/gitea:latest
```

Create a repository for your project (e.g., `neil/skymechanics-dev`).

## 4. Configure OpenClaw

Copy the template:

```bash
cp config-templates/openclaw.gb10.template.json ~/.openclaw/openclaw.json
```

Replace all `YOUR_*` placeholders:

- `YOUR_VLLM_API_KEY` — same key you set for the vLLM server
- `YOUR_GATEWAY_TOKEN` — generate with `openssl rand -hex 24`
- `YOUR_BUILDER_BOT_TOKEN` — from BotFather for the Builder bot
- `YOUR_TELEGRAM_USER_ID` — your Telegram numeric user ID
- `YOUR_TELEGRAM_GROUP_ID` — your Telegram group chat ID
- `YOUR_MACBOOK_TAILSCALE_HOSTNAME` — Tailscale hostname of your MacBook

## 5. Install Builder SOUL

```bash
cp souls/builder-SOUL.md ~/.openclaw/SOUL.md
cp souls/builder-SOUL.md ~/.openclaw/workspace/SOUL.md
```

## 6. Set Up Flux MCP (Remote)

The GB10 connects to MacBook's Flux instance over Tailscale. No local SQLite needed.

The Flux MCP config in `openclaw.json` should point to:

```json
"flux": {
    "command": "docker",
    "args": [
        "run", "-i", "--rm", "--network", "host",
        "-e", "FLUX_DATA=/tmp/flux-mcp.sqlite",
        "-e", "HOME=/tmp",
        "-e", "FLUX_SERVER=http://YOUR_MACBOOK_TAILSCALE_HOSTNAME:3000",
        "flux-mcp", "bun", "packages/mcp/dist/index.js"
    ]
}
```

Build the Docker image on GB10 too (see [FLUX-MCP.md](FLUX-MCP.md)), or pull from a registry if you've pushed it.

Test connectivity:

```bash
curl http://YOUR_MACBOOK_TAILSCALE_HOSTNAME:3000/api/projects
```

## 7. Install Lossless-Claw

```bash
openclaw plugin install @martian-engineering/lossless-claw
```

## 8. Set Up Cron Jobs

```bash
openclaw cron add \
    --every "15m" \
    --agent main \
    --session isolated \
    --timeout-seconds 600 \
    --message "CRON TASK CHECK: Call list_ready_tasks via Flux MCP. Pick the highest priority P0 task in your domain (backend/API/database/k8s) not in doing status. Move it to doing, execute the work on a feature branch, commit, push, move to done. If you fail 3 edits on a file, skip it and add a note. If all your tasks are done or blocked, post a status to Telegram."
```

## 9. Start the Gateway

```bash
openclaw gateway start
```

## 10. Verify

From GB10:

```bash
# Check vLLM
curl http://127.0.0.1:8000/v1/models

# Check Flux connectivity (via MacBook)
curl http://YOUR_MACBOOK_TAILSCALE_HOSTNAME:3000/api/projects

# Check Flux MCP
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | \
    docker run -i --rm --network host \
    -e FLUX_DATA=/tmp/flux-mcp.sqlite \
    -e HOME=/tmp \
    -e FLUX_SERVER=http://YOUR_MACBOOK_TAILSCALE_HOSTNAME:3000 \
    flux-mcp bun packages/mcp/dist/index.js

# Check OpenClaw
openclaw status
```

## Session Bloat Prevention

GB10 sessions can grow large (22MB+) and choke the model. Monitor and archive:

```bash
# Check sizes
du -sh ~/.openclaw/agents/main/sessions/*.jsonl | sort -rh | head -5

# Archive anything over 1MB
for f in $(find ~/.openclaw/agents/main/sessions/ -name "*.jsonl" -size +1M); do
    mv "$f" ~/.openclaw/sessions-archive/
done
```

Consider adding this as a cron job on the host OS:

```bash
# /etc/cron.d/openclaw-cleanup
0 */6 * * * gaineyllc find /home/gaineyllc/.openclaw/agents/main/sessions/ -name "*.jsonl" -size +2M -exec mv {} /home/gaineyllc/.openclaw/sessions-archive/ \;
```
