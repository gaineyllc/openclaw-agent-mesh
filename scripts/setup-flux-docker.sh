#!/bin/bash
# Build the Flux MCP Docker image and set up data directories
set -euo pipefail

echo "=== Flux MCP Docker Setup ==="

# Check Docker
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not found. Install Docker Desktop from https://docker.com"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon not running. Start Docker Desktop."
    exit 1
fi

# Create data directory
FLUX_DATA="$HOME/.flux-data"
mkdir -p "$FLUX_DATA/blobs"
echo "Data directory: $FLUX_DATA"

# Check if image already exists
if docker image inspect flux-mcp >/dev/null 2>&1; then
    echo "flux-mcp image already exists."
    read -p "Rebuild? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping build."
        exit 0
    fi
fi

# Clone and build
TMPDIR=$(mktemp -d)
echo "Cloning Flux source..."
echo ""
echo "NOTE: You need access to the Flux repository."
echo "If you have a local copy, set FLUX_SOURCE_DIR and re-run."
echo ""

if [ -n "${FLUX_SOURCE_DIR:-}" ] && [ -d "$FLUX_SOURCE_DIR" ]; then
    echo "Building from $FLUX_SOURCE_DIR..."
    cd "$FLUX_SOURCE_DIR"
    docker build -t flux-mcp .
else
    echo "Set FLUX_SOURCE_DIR to your local Flux repo checkout, then re-run:"
    echo "  FLUX_SOURCE_DIR=/path/to/flux bash $0"
    exit 1
fi

echo ""
echo "=== Docker image built: flux-mcp ==="

# Start web server
echo ""
read -p "Start Flux web server on port 3000? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker run -d \
        --name flux-web \
        -p 3000:3000 \
        -v "$FLUX_DATA:/app/packages/data" \
        flux-mcp
    echo "Flux web server running on http://localhost:3000"
fi

# Test MCP
echo ""
echo "Testing MCP server..."
RESULT=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | \
    docker run -i --rm \
    -v "$FLUX_DATA:/app/packages/data" \
    -v "$FLUX_DATA/blobs:/home/flux" \
    -e "FLUX_DATA=/app/packages/data/flux.sqlite" \
    -e "HOME=/app/packages/data" \
    flux-mcp bun packages/mcp/dist/index.js 2>/dev/null | head -1)

if echo "$RESULT" | grep -q '"result"'; then
    echo "MCP server responding correctly!"
else
    echo "WARNING: MCP server did not return expected response."
    echo "Response: $RESULT"
fi

echo ""
echo "=== Flux setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Add the Flux MCP config to ~/.openclaw/openclaw.json"
echo "  2. See docs/FLUX-MCP.md for the config snippet"
