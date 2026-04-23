#!/bin/bash
# Setup Ollama on macOS with Qwen3.5-122B model
set -euo pipefail

echo "=== Ollama Setup ==="

# Check if Homebrew is installed
if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found. Install from https://brew.sh"
    exit 1
fi

# Install Ollama
if ! command -v ollama &>/dev/null; then
    echo "Installing Ollama..."
    brew install ollama
else
    echo "Ollama already installed: $(ollama --version)"
fi

# Start the service
echo "Starting Ollama service..."
brew services start ollama
sleep 3

# Verify it's running
if curl -s http://127.0.0.1:11434/v1/models >/dev/null 2>&1; then
    echo "Ollama is running on port 11434"
else
    echo "WARNING: Ollama doesn't seem to be responding. Check 'brew services list'"
fi

# Pull the model
MODEL="huihui_ai/qwen3.5-abliterated:122b"
echo ""
echo "Pulling model: $MODEL"
echo "This will download ~76GB. Make sure you have enough disk space and memory."
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ollama pull "$MODEL"
    echo ""
    echo "Model pulled successfully."
    echo "Test with: curl http://127.0.0.1:11434/v1/chat/completions -d '{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}'"
else
    echo "Skipped model pull."
fi

echo ""
echo "=== Ollama setup complete ==="
