# Flux MCP Setup

Flux is the task management system for the agent mesh. It uses a SQLite database and exposes both a web UI and an MCP (Model Context Protocol) server for agent interaction.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                MacBook (Primary)                 │
│                                                  │
│  flux-web (Docker)          flux-mcp (Docker)    │
│  ├── Web UI on :3000        ├── stdio transport  │
│  ├── REST API on :3000      ├── reads SQLite     │
│  └── SQLite at              │   directly via      │
│      ~/.flux-data/          │   volume mount      │
│      flux.sqlite            └────────────────────│
└──────────────┬───────────────────────────────────┘
               │ Tailscale (:3000)
┌──────────────▼───────────────────────────────────┐
│                GB10 (Remote)                      │
│                                                   │
│  flux-mcp (Docker)                                │
│  ├── stdio transport                              │
│  ├── FLUX_SERVER=http://neils-macbook-pro:3000    │
│  └── proxies via web API (no local SQLite needed) │
└───────────────────────────────────────────────────┘
```

## Critical: MCP vs Web Server

The Flux Docker image has TWO entrypoints:

1. **Default CMD** — starts the **web server** (UI + REST API)
2. **`bun packages/mcp/dist/index.js`** — starts the **MCP server** (stdio JSON-RPC)

OpenClaw needs the MCP server. If you use the default CMD, the MCP connection will fail with "Connection closed" because the web server doesn't speak JSON-RPC over stdio.

## Building the Docker Image

```bash
# Clone the Flux repository
git clone https://github.com/fluxproject/flux.git  # or wherever the source lives
cd flux

# Build the image
docker build -t flux-mcp .
```

Or use the setup script:

```bash
bash scripts/setup-flux-docker.sh
```

## MacBook Configuration

### Web Server (for UI and GB10 remote access)

```bash
docker run -d \
    --name flux-web \
    -p 3000:3000 \
    -v ~/.flux-data:/app/packages/data \
    flux-mcp
# Uses default CMD → web server
```

### MCP Server (for OpenClaw agent access)

In `~/.openclaw/openclaw.json`:

```json
{
    "mcp": {
        "servers": {
            "flux": {
                "command": "docker",
                "args": [
                    "run", "-i", "--rm",
                    "-v", "/Users/YOU/.flux-data:/app/packages/data",
                    "-v", "/Users/YOU/.flux-data/blobs:/home/flux",
                    "-e", "FLUX_DATA=/app/packages/data/flux.sqlite",
                    "-e", "HOME=/app/packages/data",
                    "flux-mcp",
                    "bun", "packages/mcp/dist/index.js"
                ]
            }
        }
    }
}
```

Key points:
- `-i` enables interactive stdin (required for stdio MCP transport)
- `--rm` cleans up containers after each session
- Volume mounts give MCP direct access to the SQLite database
- The explicit `bun packages/mcp/dist/index.js` overrides the default CMD

### Verify MacBook MCP

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | \
    docker run -i --rm \
    -v ~/.flux-data:/app/packages/data \
    -v ~/.flux-data/blobs:/home/flux \
    -e FLUX_DATA=/app/packages/data/flux.sqlite \
    -e HOME=/app/packages/data \
    flux-mcp bun packages/mcp/dist/index.js
```

You should see a JSON-RPC response with `"result"` containing server capabilities.

## GB10 Configuration

The GB10 doesn't have the SQLite file locally. It connects through the MacBook's web server.

In `~/.openclaw/openclaw.json` on GB10:

```json
{
    "mcp": {
        "servers": {
            "flux": {
                "command": "docker",
                "args": [
                    "run", "-i", "--rm", "--network", "host",
                    "-e", "FLUX_DATA=/tmp/flux-mcp.sqlite",
                    "-e", "HOME=/tmp",
                    "-e", "FLUX_SERVER=http://YOUR_MACBOOK_TAILSCALE_HOSTNAME:3000",
                    "flux-mcp",
                    "bun", "packages/mcp/dist/index.js"
                ]
            }
        }
    }
}
```

Key differences from MacBook:
- `--network host` allows reaching MacBook over Tailscale
- `FLUX_SERVER` tells the MCP to proxy through the web API instead of reading SQLite directly
- `FLUX_DATA` is set to a dummy path (MCP needs it defined but won't use it when `FLUX_SERVER` is set)

### Verify GB10 MCP

First verify web API access:

```bash
curl http://YOUR_MACBOOK_TAILSCALE_HOSTNAME:3000/api/projects
```

Then verify MCP:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | \
    docker run -i --rm --network host \
    -e FLUX_DATA=/tmp/flux-mcp.sqlite \
    -e HOME=/tmp \
    -e FLUX_SERVER=http://YOUR_MACBOOK_TAILSCALE_HOSTNAME:3000 \
    flux-mcp bun packages/mcp/dist/index.js
```

## Available MCP Tools

Once connected, agents have these Flux tools:

| Tool | Description |
|------|-------------|
| `list_projects` | List all projects with stats |
| `list_tasks` | List tasks with optional filters (status, epic, project) |
| `list_ready_tasks` | Show unblocked tasks sorted by priority |
| `create_task` | Create task with title, description, priority, epic, dependencies |
| `update_task` | Update task details, status, priority, or add notes |
| `move_task_status` | Quick status change: `todo` → `doing` → `done` |
| `list_epics` | List epics/sprints in a project |
| `create_epic` | Create a new epic/sprint |

## Troubleshooting

### "Connection closed" on MCP init

The Docker container is running the web server instead of the MCP server. Make sure your args include the explicit entrypoint: `"bun", "packages/mcp/dist/index.js"`.

### "bun: not found"

The Docker image must have `bun` installed. If using a custom image, ensure `bun` is in the PATH.

### GB10 can't reach MacBook Flux

1. Verify Tailscale is connected: `tailscale status`
2. Test connectivity: `curl http://YOUR_MACBOOK_HOSTNAME:3000`
3. Check if `flux-web` container is running on MacBook: `docker ps | grep flux-web`
4. Check MacBook firewall isn't blocking port 3000

### SQLite lock errors

Only one writer at a time. If the web server and MCP are both writing, you may see lock errors. The MCP uses WAL mode which helps, but under heavy load you may need to restart the web container.
