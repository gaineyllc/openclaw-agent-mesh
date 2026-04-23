#!/bin/bash
# Service watchdog — checks all agent mesh services and restarts any that are down.
# Intended to be run via LaunchAgent on a schedule or after boot.
set -uo pipefail

LOG="/Users/gaineyllc/.openclaw/logs/watchdog.log"
mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1
echo "=== Watchdog run: $(date) ==="

# Wait for Docker Desktop to be ready (up to 120 seconds after boot)
DOCKER_WAIT=0
while ! docker info >/dev/null 2>&1; do
    if [ $DOCKER_WAIT -ge 120 ]; then
        echo "FAIL: Docker Desktop not responding after 120s"
        open -a Docker
        sleep 30
        break
    fi
    sleep 5
    DOCKER_WAIT=$((DOCKER_WAIT + 5))
done
echo "Docker ready after ${DOCKER_WAIT}s"

# Check Flux web container
if docker ps --filter name=flux-web --format '{{.Names}}' | grep -q flux-web; then
    echo "OK: flux-web running"
else
    echo "WARN: flux-web not running, starting..."
    docker start flux-web 2>/dev/null || \
    docker run -d --name flux-web --restart unless-stopped \
        -p 3000:3000 \
        -v /Users/gaineyllc/.flux-data:/app/packages/data \
        flux-mcp
    echo "flux-web started"
fi

# Verify Flux responds
sleep 2
if curl -sf http://127.0.0.1:3000 >/dev/null 2>&1; then
    echo "OK: Flux web responding on :3000"
else
    echo "WARN: Flux web not responding, restarting container..."
    docker restart flux-web
fi

# Check Ollama
if curl -sf http://127.0.0.1:11434/v1/models >/dev/null 2>&1; then
    echo "OK: Ollama responding on :11434"
else
    echo "WARN: Ollama not responding, restarting via brew..."
    brew services restart ollama
fi

# Check OpenClaw gateway
if curl -sf http://127.0.0.1:18789/health >/dev/null 2>&1; then
    echo "OK: OpenClaw gateway responding on :18789"
else
    echo "WARN: OpenClaw gateway not responding — launchd should auto-restart"
    launchctl kickstart -k gui/$(id -u)/ai.openclaw.gateway 2>/dev/null || true
fi

echo "=== Watchdog complete ==="
echo ""
