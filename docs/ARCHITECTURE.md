# Architecture

## Overview

The agent mesh is a distributed system where multiple AI agents collaborate autonomously across machines. Each agent runs inside an OpenClaw gateway, uses local LLMs for inference, communicates via Telegram, and tracks work in a shared Flux task board.

## Machines

### MacBook Pro (M4 Max, 128GB Unified Memory)

Runs two agents: **Architect** (main) and **Verifier**.

- **Inference**: Ollama serving `huihui_ai/qwen3.5-abliterated:122b` (Qwen3.5-122B-A10B, ~76GB in memory)
- **Port 11434**: Ollama API (OpenAI-compatible)
- **Flux**: Docker container with SQLite DB at `~/.flux-data/flux.sqlite`. Web UI on port 3000, MCP via stdio Docker transport.
- **Tailscale hostname**: `neils-macbook-pro`

### GB10 Server (192GB RAM, NVIDIA GPU)

Runs one agent: **Builder**.

- **Inference**: vLLM serving `huihui-ai/Huihui-Qwen3-Coder-Next-abliterated` (Qwen3-Coder, 262K context)
- **Port 8000**: vLLM API (OpenAI-compatible)
- **Tailscale IP**: `100.69.118.20`
- **Gitea**: Port 3030 — `http://100.69.118.20:3030`
- **Flux MCP**: Docker container connecting to MacBook's Flux web server over Tailscale

## Data Flow

### Task Lifecycle

```
1. Architect creates tasks in Flux (via MCP tools)
   └── Flux SQLite DB on MacBook

2. Cron fires every 15 minutes on both machines
   ├── MacBook: Architect calls list_ready_tasks → picks frontend/arch task
   └── GB10:    Builder calls list_ready_tasks → picks backend task

3. Agent works on task
   ├── Reads/writes code in workspace
   ├── Commits to Gitea with "done #N: description"
   └── Posts status to Telegram group

4. Verifier detects new commits
   ├── Pulls latest code
   ├── Runs tests, linting, API contract checks
   ├── Reports findings to Telegram
   └── Promotes to staging if all passes

5. Agents pick next task (loop)
```

### Flux MCP Transport

Flux uses an MCP (Model Context Protocol) server inside a Docker container. The key insight: the Docker image's default CMD starts the **web server**, but MCP needs the **MCP server entrypoint**.

**MacBook (local, direct SQLite access):**
```
Docker run → mounts ~/.flux-data → bun packages/mcp/dist/index.js
                                    ↑ explicit MCP entrypoint
Reads/writes SQLite directly via volume mount
```

**GB10 (remote, connects to MacBook web API):**
```
Docker run → FLUX_SERVER=http://neils-macbook-pro:3000
           → bun packages/mcp/dist/index.js
                ↑ explicit MCP entrypoint
Proxies all operations through MacBook's Flux web server over Tailscale
```

### Model Routing

OpenClaw supports primary + fallback model chains:

```
Request → Primary: vllm/Qwen3-Coder-Next (GB10, 262K context)
       → Fallback: ollama/Qwen3.5-122B (MacBook, 131K context)
```

The `agents.defaults.model` section in `openclaw.json` defines this chain. Each provider maps to a `baseUrl` in the `models.providers` section.

### Context Management (Lossless-Claw)

Lossless-Claw prevents context overflow by compacting old messages when the session approaches the model's context window:

- **contextThreshold: 0.8** — trigger compaction at 80% of context window
- **freshTailCount: 48** — always preserve the last 48 messages verbatim
- **incrementalMaxDepth: 1** — single-level DAG cascade for compaction
- **summaryModel** — uses the same primary model for generating summaries
- **ignoreSessionPatterns** — skips cron and subagent sessions (they're ephemeral)

### Memory (Memory-Core)

Memory-Core tracks patterns across sessions:

- Short-term recalls are stored per-session
- A nightly cron job (4am ET) promotes frequently-recalled memories (minScore >= 0.8, minRecallCount >= 3, minUniqueQueries >= 3) into MEMORY.md
- MEMORY.md persists across sessions — it's how agents "remember" across restarts

### Telegram Channels

Each agent has its own Telegram bot identity:

| Agent      | Bot Username       | Machine  |
|------------|--------------------|----------|
| Architect  | @gaineybot         | MacBook  |
| Builder    | @gaineydevbot      | GB10     |
| Verifier   | @gaineyverifierbot | MacBook  |

All three post to the same Telegram group (`-5285627178`). The Architect and Builder respond to all messages; the Verifier requires @mention (`requireMention: true`).

DM and group access is restricted to Neil's Telegram user ID (`5824139677`).

## Cron-Driven Autonomy

Each machine runs an OpenClaw cron job that fires every 15 minutes:

```
Every 15m → OpenClaw creates isolated session
         → Injects task-check message
         → Agent calls list_ready_tasks (Flux MCP)
         → Picks highest-priority unblocked task
         → Moves to "doing", works on it
         → Commits, pushes, moves to "done"
         → Session ends (timeout: 10 min)
```

Key design decisions:
- **Isolated sessions** prevent context buildup across cron runs
- **10-minute timeout** prevents runaway sessions from consuming resources
- **The cron message includes failure handling**: skip after 3 consecutive edit failures, add a note, move on
- **Agents post to Telegram** whether they completed work or found nothing to do

## Network Topology

```
MacBook ◄──Tailscale──► GB10
  │                       │
  ├── :11434 Ollama       ├── :8000 vLLM
  ├── :3000  Flux Web     ├── :3030 Gitea
  ├── :18789 OC Gateway   ├── :18789 OC Gateway
  └── :8001  Embeddings   └── :8001 Embeddings
```

All inter-machine traffic goes through Tailscale (WireGuard). No ports are exposed to the public internet.

## Embedding Search

Both machines run a local embedding server for memory search:

- **Model**: `sentence-transformers/all-MiniLM-L6-v2`
- **Endpoint**: `http://100.69.118.20:8001/v1` (GB10 — used by both machines)
- **Provider**: OpenAI-compatible API
