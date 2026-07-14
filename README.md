
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img alt="Open Agent Router" src="assets/logo-light.svg" width="480">
  </picture>
</p>

<p align="center">
  <strong>One Port. All Agents.</strong><br>
  A local proxy that lets any AI coding agent use any upstream LLM account
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#download">Download</a>
</p>

---

## Features

- **Unified Proxy** — Claude Code, Codex, Gemini CLI, OpenClaw, Kimi Code, Qwen Code — all point to `localhost:26969`
- **Multi-Key Pools** — Multiple API keys per platform with automatic load balancing and failover
- **Model Groups** — Route requests by strategy: sequential, weighted random, or lowest latency
- **Protocol Conversion** — Anthropic ↔ OpenAI ↔ Responses ↔ Gemini, auto-detected and converted
- **Cross-Model Retry** — Failed model automatically falls back to the next, no client retry needed
- **Per-Model Cooldown** — 429 / 401 errors trigger automatic cooldown without affecting other models
- **Auto-Update** — `oar update` checks, downloads, and restarts in one command

## Quick Start

```bash
# Download the oar binary and add it to your PATH
# macOS ARM64:
curl -Lo /usr/local/bin/oar https://github.com/SnowAIGirl/open-agent-router/releases/latest/download/oar-darwin-arm64

chmod +x /usr/local/bin/oar

# Start the service
oar start

# Check status
oar status
```

### Add an account

```bash
oar account create \
  --name my-deepseek \
  --platform deepseek \
  --base-url https://api.deepseek.com \
  --key sk-xxxxxxxx
```

### Point your agent to OAR

```bash
# Claude Code / Claude CLI
export ANTHROPIC_BASE_URL=http://127.0.0.1:26969
claude

# Codex
export OPENAI_BASE_URL=http://127.0.0.1:26969
codex

# See all supported agents
oar agent list
```

## How It Works

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│  Claude Code │     │                  │     │   DeepSeek   │
│     Codex    │────▶│   OAR Proxy      │────▶│   OpenAI     │
│  Gemini CLI  │     │   localhost:     │     │   Anthropic  │
│  Kimi Code   │     │   26969          │     │   Gemini     │
│  Qwen Code   │     │                  │     │   Self-Hosted│
└──────────────┘     └──────────────────┘     └──────────────┘
                          │
                     ┌────┴────┐
                     │  SQLite │
                     │  config │
                     └─────────┘
```

All agents connect to the same local port. OAR routes requests through a four-layer chain — project → agent → group → model — with automatic protocol conversion and failover.

## Download

| Platform | Download |
|---|---|
| macOS ARM64 | [oar-darwin-arm64](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| macOS x64 | [oar-darwin-x64](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| Linux x64 | [oar-linux-x64](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| Windows x64 | [oar-win-x64.exe](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| macOS .dmg | [Open Agent Router.dmg](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| Linux .deb / .rpm | [GitHub Releases](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |

> Already installed? Run `oar update` to upgrade.

## Requirements

- macOS 14+ / Linux / Windows
- Node.js 22+ (build only)
- Bun (build only)

## Architecture

```
oar                          Single binary, three modes
├── start                    Long-running proxy service
├── update                   Self-update
├── status / account / ...   Management CLI

Core (TypeScript → Bun compile):
├── proxy/                   Request proxying + protocol conversion
│   ├── adapters/           a2o, o2o, r2o, g2o ...
│   └── protocol.ts         Protocol matrix
├── server/                 Express HTTP server
│   └── routes/
│       ├── admin.ts        Management API
│       └── proxy.ts        Proxy routes
├── config-manager/         Generate agent connection configs
├── service/                Service management + auto-update
└── db/                     SQLite config store
```

## License

MIT
