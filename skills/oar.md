# Open Agent Router (OAR) — Skill for AI Agents

> **One Port. All Agents.**  
> Local AI agent proxy/router. Single port (26969) routes to multiple upstream providers with protocol conversion, load balancing, cooldown/retry, and project-scoped agent routing.

## Quick Start

```bash
# Start the service
oar start

# Check status
oar status

# Stop
oar stop
```

## Architecture

```
oar CLI (short-lived commands)  ←→  oar service (long-lived daemon on :26969)
                                         │
                                    ┌─────┴─────┐
                                    │  Proxy      │  ←  Convert + route requests
                                    │  Admin API  │  ←  Manage accounts/models/groups
                                    └─────────────┘
```

- **Single binary** — `oar` handles both CLI and service modes
- **Single port** — admin API (`/api/*`) and proxy (`/`) share port 26969
- **Data dir** — `~/.open-agent-router/` (DB, config, assets)
- **DB** — SQLite at `~/.open-agent-router/oar.db`

## CLI Commands

### Service Management

| Command | Description |
|---------|-------------|
| `oar start` | Start long-lived service (EADDRINUSE → exit 0, safe to call multiple times) |
| `oar stop` | Kill process holding port 26969 |
| `oar restart` | Kill + restart |
| `oar status` | Show service status (running/stopped) |
| `oar init --from-app` | First-time setup (Tauri shell calls this) — copies binaries, registers launchd |
| `oar service install` | Register as system service (launchd on macOS) |
| `oar service uninstall` | Remove system service |

### Account Management

Manage upstream provider accounts (OpenAI, Anthropic, DeepSeek, etc.).

```bash
oar account list                              # List all accounts
oar account get <id>                          # Show account details
oar account create --name my-acc --platform openai --base-url https://api.openai.com/v1 --key sk-...
oar account update <id> --name new-name --active false
oar account delete <id>
oar account models <id>                       # List models from this account
oar account sync <id>                         # Sync latest models from provider's /v1/models
```

**Parameters for create:**
- `--name` — display name
- `--platform` — vendor slug (openai, anthropic, deepseek, gemini, kimi, etc.)
- `--base-url` — API endpoint URL
- `--key` — API key (optional, can be set later via UI)
- `--protocol` — API protocol: `openai` (default), `anthropic`, `gemini`

**Update flags:** `--name`, `--platform`, `--base-url`, `--key` (empty = clear), `--protocol`, `--active` (true/false)

### Model Groups

Groups bundle models with routing strategy and cooldown/retry config.

```bash
oar group list                                # List all groups
oar group get <id|name>                       # Show group + its models
oar group create --name my-group
oar group update <id|name> [flags]            # Update group config
oar group delete <id|name>
oar group recover <id|name>                   # Recover all cooled-down models in group
oar group add-model <id|name> --model-id <id> [--priority 0] [--account-id <id>]
oar group remove-model <id|name> --gm-id <id>
```

**Update flags:** `--name`, `--strategy` (sequential/weighted_random/lowest_latency), `--max-retries`, `--cooldown` (seconds), `--cross-model-retry` (true/false), `--aliases` (comma-separated)

### Agent Routing

An **agent** is a tool that talks to LLMs (Claude Code, Codex, Gemini CLI, etc.). Each agent has a default group.

```bash
oar agent list                                # List all agents + their default groups
oar agent check <slug>                        # Run preflight check for an agent
oar agent regenerate <slug>                   # Regenerate agent config file
oar agent set-group <slug> --group-id <id>    # Set default group for agent
```

Built-in agents: `claude-cli`, `codex`, `gemini`, `hermes`, `openclaw`, `opencode`, `kimi-code`, `qwen-code`, `copilot-cli`, `claude-desktop`.

### Project Routing

Projects bind agents to scoped groups with per-project config generation.

```bash
oar project list                              # List all projects
oar project get <id|name>                     # Show project details
oar project create --name my-proj [--path /path/to/project]
oar project delete <id|name>
oar project add-agent <id|name> --slug claude-cli [--group-id <id>]
oar project remove-agent <id|name> --slug claude-cli
oar project gen-config <id|name> [--slug claude-cli]  # Generate config for all/specific agent
```

### `oar open` — Launch Agent in Project Context

```bash
oar open                                    # Auto-detect project from cwd
oar open --project my-proj                  # Specify project
oar open --agent claude-cli                 # Specify agent (optional)
oar open -- --extra-args                    # Pass args to agent CLI
```

Detects the project by matching `cwd` against project paths. Spawns the agent CLI with `OAR_PROJECT_DIR` env var set.

### Settings & Monitoring

```bash
oar settings list                           # Show all settings
oar settings set locale zh-CN               # Change a setting (e.g. locale)
oar usage [--start-time TS] [--end-time TS] # Query token/cost usage
oar activity                                # Show recent proxy activity
oar vendor                                  # List known vendors
oar capture                                 # Capture/debug proxy traffic

oar update check                            # Check for new version
oar update apply                            # Download and apply update (auto-restarts)
oar version / -v / --version                # Show version

oar help / -h / --help                      # Show help
```

## Typical Workflow

### 1. First time setup

```bash
oar start              # Start the service
oar status             # Verify running
```

### 2. Add an upstream provider

```bash
oar account create --name my-deepseek --platform deepseek --base-url https://api.deepseek.com --key sk-xxx
oar account sync my-deepseek                          # Pull available models
```

### 3. Create a group

```bash
oar group create --name my-group
oar group add-model my-group --model-id deepseek-chat --priority 1
oar group add-model my-group --model-id deepseek-reasoner --priority 2
```

### 4. Point an agent at it

```bash
oar agent set-group claude-cli --group-id my-group
oar agent regenerate claude-cli     # Generate config → Claude Code now talks through OAR
```

### 5. Or use project-scoped routing

```bash
oar project create --name my-project --path /Users/me/my-project
oar project add-agent my-project --slug claude-cli --group-id my-group
oar project gen-config my-project
# Then inside the project dir:
cd /Users/me/my-project && oar open --agent claude-cli
```

## Architecture Details

### Protocol Conversion

OAR converts between 4 protocols transparently: OpenAI (`o`), Anthropic (`a`), Responses API (`r`), Gemini (`g`). Supported conversions:

- `anthropic → openai` (a2o)
- `anthropic → responses` (a2r)
- `responses → openai` (r2o)
- `responses → anthropic` (r2a)
- `gemini → anthropic` (g2a)
- `gemini → openai` (g2o)

Auto-detected from client request path. Fallback: anthropic → openai, responses → openai/anthropic, gemini → anthropic/openai.

### Model Selection

Groups use one of 3 strategies:
- `sequential` — try models in priority order
- `weighted_random` — pick by weight distribution
- `lowest_latency` — pick the fastest responding model

On failure (rate_limited, auth_error, timeout, server_error), OAR marks the model as cooled down and tries the next model (`crossModelRetry`).

### Cache Architecture

`routeCache` loads all accounts/models/groups/projects/agents into memory at startup. **Proxy requests do zero SQLite reads.** Mutations update cache in-place + persist to DB.

## Tips & Common Issues

- **Port in use?** `oar start` exits 0 on EADDRINUSE — the running service is fine
- **Models not showing?** Run `oar account sync <id>` to pull latest from provider
- **Agent can't connect?** Check `oar status` first, then `oar agent check <slug>`
- **Config not taking effect?** `oar agent regenerate <slug>` rewrites the agent config file
- **All models cooled down?** `oar group recover <name>` resets all models in a group
- **Data dir**: `~/.open-agent-router/` — delete DB to factory reset
- **JSON output**: Append `--json` to any command for machine-readable output

## CLI Style Convention

When generating CLI examples or help output for this project:

- `oar <command>` is the entry point (not `npx oar` or `bun oar`)
- Flags use `--name` format (not short flags like `-n`)
- Boolean flags take `true`/`false` as values, not bare flags
- `--json` appended to any command switches to JSON output mode
