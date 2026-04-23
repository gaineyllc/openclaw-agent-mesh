# Troubleshooting

## Model Inference Issues

### Ollama not responding

```bash
# Check if running
brew services list | grep ollama

# Restart
brew services restart ollama

# Test
curl http://127.0.0.1:11434/v1/models
```

### vLLM Metal stream error (Apple Silicon)

`RuntimeError: There is no Stream(gpu, 3) in current thread.`

This is a known incompatibility between Python 3.14, MLX, and vllm-mlx. The Metal GPU stream management breaks under concurrent threading. There is no fix — downgrade to Python 3.12 or use Ollama instead.

### vLLM MLLM misdetection (Qwen3.5)

vllm-mlx hardcodes `"Qwen3.5-"` as a multimodal model pattern. Text-only Qwen3.5 models get misrouted through the multimodal loader and fail. Workaround: use Ollama, or patch `vllm_mlx/api/utils.py` to remove the pattern (will break on updates).

### Out of memory

Running a 122B model (~76GB) on a 128GB machine leaves little headroom. Never run two model instances simultaneously (e.g., a test script while the server is loaded).

```bash
# Check memory pressure
memory_pressure

# Find and kill memory hogs
ps aux | sort -k4 -rn | head -10
```

## Flux MCP Issues

### "Connection closed" on initialization

The Docker container is running the web server (default CMD) instead of the MCP server. Fix: add explicit entrypoint `"bun", "packages/mcp/dist/index.js"` to your Docker args in `openclaw.json`.

### GB10 can't reach Flux

```bash
# Verify Tailscale
tailscale status

# Test web API
curl http://YOUR_MACBOOK_HOSTNAME:3000/api/projects

# Check Docker container on MacBook
docker ps | grep flux-web
docker restart flux-web
```

### `flux-tasks` npm package

`flux-tasks` is a CLI tool, NOT an MCP server. `npx -y flux-tasks mcp` does not work. Always use the Docker transport with `bun packages/mcp/dist/index.js`.

## OpenClaw Issues

### Agent not picking up tasks

1. Check cron jobs are registered:
   ```bash
   openclaw cron list
   ```

2. Check if cron is actually firing — look for new session files:
   ```bash
   ls -lt ~/.openclaw/agents/main/sessions/*.jsonl | head -5
   ```

3. Check gateway is running:
   ```bash
   openclaw status
   ```

### Session bloat (slow responses, timeouts)

Session files grow over time. Files >1MB significantly slow local models.

```bash
# Find large sessions
du -sh ~/.openclaw/agents/main/sessions/*.jsonl | sort -rh | head -10

# Archive bloated ones
mkdir -p ~/.openclaw/sessions-archive
mv ~/.openclaw/agents/main/sessions/LARGE_SESSION.jsonl ~/.openclaw/sessions-archive/
```

### Cron job flags

Common flag errors:
- `--tz` is only valid with `--cron` or offset-less `--at`, not with `--every`
- `--stagger`/`--exact` are only valid for cron schedules, not `--every`
- Use `--session isolated` to prevent context buildup across runs

### Gateway crashes after MacBook sleep

The gateway's Telegram connection drops when the MacBook locks/sleeps. The health-monitor (runs every 300s) auto-restarts broken channel connections, but completed sessions are NOT auto-restarted.

After wake, verify:
```bash
openclaw status
# If agents are idle, manually trigger:
openclaw cron trigger CRON_JOB_ID
```

## Telegram Issues

### Bot not responding

1. Verify bot token is correct in `openclaw.json`
2. Check gateway is running and channel is connected
3. Verify `allowFrom` includes your Telegram user ID
4. For group messages, check `requireMention` setting

### Messages going to wrong bot

Each agent has its own bot identity. Check the `channels.telegram.accounts` section in `openclaw.json` to verify which agent maps to which bot token.

## Gitea Issues

### Can't push from MacBook to GB10

```bash
# Test SSH
ssh gaineyllc@100.69.118.20 echo ok

# Test HTTP
curl http://100.69.118.20:3030

# Check Gitea container
ssh gaineyllc@100.69.118.20 'docker ps | grep gitea'
```

### Merge conflicts

The Flux-based task system eliminates most conflicts (no more `.taskboard.md` edits). If code conflicts occur, the agent should:
1. `git stash`
2. `git pull --rebase origin master`
3. `git stash pop`
4. Resolve conflicts
5. If unable to resolve after 3 attempts, skip and post to Telegram

## Network Issues

### Tailscale not connected

```bash
tailscale status
# If disconnected:
sudo tailscale up
```

### Port conflicts

Default ports:
- 11434: Ollama (MacBook)
- 8000: vLLM (GB10)
- 3000: Flux Web (MacBook)
- 3030: Gitea (GB10)
- 18789: OpenClaw Gateway (both)
- 8001: Embedding server

If a port is in use:
```bash
lsof -i :PORT_NUMBER
```
