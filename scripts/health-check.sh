#!/bin/bash
# Health check for the OpenClaw agent mesh
# Run this to verify all services are operational
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${NC}  $name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC}  $name"
        ((FAIL++))
    fi
}

warn_check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${NC}  $name"
        ((PASS++))
    else
        echo -e "  ${YELLOW}WARN${NC}  $name"
        ((WARN++))
    fi
}

echo "====================================="
echo "  OpenClaw Agent Mesh Health Check"
echo "====================================="
echo ""

# --- Local Services ---
echo "Local Services:"
check "Ollama responding" "curl -sf http://127.0.0.1:11434/v1/models"
check "Ollama model loaded" "curl -sf http://127.0.0.1:11434/v1/models | grep -q qwen"
check "Flux web server" "curl -sf http://127.0.0.1:3000"
check "Flux Docker running" "docker ps | grep -q flux-web"
check "OpenClaw gateway" "curl -sf http://127.0.0.1:18789/health || openclaw status 2>&1 | grep -qi running"
echo ""

# --- Flux MCP ---
echo "Flux MCP:"
check "MCP stdio responds" "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"capabilities\":{}}}' | timeout 10 docker run -i --rm -v ~/.flux-data:/app/packages/data -v ~/.flux-data/blobs:/home/flux -e FLUX_DATA=/app/packages/data/flux.sqlite -e HOME=/app/packages/data flux-mcp bun packages/mcp/dist/index.js 2>/dev/null | head -1 | grep -q result"
echo ""

# --- Remote (GB10) ---
echo "GB10 (Remote):"

# Try to detect GB10 IP from openclaw config
GB10_IP=$(grep -o '100\.[0-9]*\.[0-9]*\.[0-9]*' ~/.openclaw/openclaw.json 2>/dev/null | head -1)
if [ -z "$GB10_IP" ]; then
    GB10_IP="100.69.118.20"  # fallback
fi

warn_check "Tailscale to GB10" "ping -c 1 -W 2 $GB10_IP"
warn_check "vLLM on GB10" "curl -sf http://$GB10_IP:8000/v1/models"
warn_check "Gitea on GB10" "curl -sf http://$GB10_IP:3030"
warn_check "Embedding server" "curl -sf http://$GB10_IP:8001/v1/models"
echo ""

# --- OpenClaw Config ---
echo "Configuration:"
check "openclaw.json exists" "test -f ~/.openclaw/openclaw.json"
check "SOUL.md exists" "test -f ~/.openclaw/SOUL.md"
check "Cron jobs configured" "test -f ~/.openclaw/cron/jobs.json && grep -q 'Task Loop' ~/.openclaw/cron/jobs.json"
check "Lossless-claw installed" "test -d ~/.openclaw/extensions/lossless-claw"
echo ""

# --- Session Health ---
echo "Session Health:"
LARGE_SESSIONS=$(find ~/.openclaw/agents/main/sessions/ -name "*.jsonl" -size +1M 2>/dev/null | wc -l | tr -d ' ')
if [ "$LARGE_SESSIONS" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC}  No bloated sessions (>1MB)"
    ((PASS++))
else
    echo -e "  ${YELLOW}WARN${NC}  $LARGE_SESSIONS session(s) over 1MB — consider archiving"
    ((WARN++))
fi
echo ""

# --- Summary ---
echo "====================================="
echo -e "  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}"
echo "====================================="

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Some checks failed. See docs/TROUBLESHOOTING.md for help."
    exit 1
fi
