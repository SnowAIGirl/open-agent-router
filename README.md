
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/SnowAIGirl/open-agent-router/main/assets/logo-dark.svg">
    <img alt="Open Agent Router" src="https://raw.githubusercontent.com/SnowAIGirl/open-agent-router/main/assets/logo-light.svg" width="480">
  </picture>
</p>

<p align="center">
  <strong>One Port. All Agents.</strong><br>
  一个本地代理，让所有 AI coding agent 共享任意上游 LLM 账号
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#download">Download</a>
</p>

---

## Features

- **Unified Proxy** — Claude Code, Codex, Gemini CLI, OpenClaw, Kimi Code, Qwen Code — all connect to `localhost:26969`
- **Multi-Key Pools** — 同一个平台挂多个 API Key，自动负载均衡和故障转移
- **Model Groups** — 按策略（sequential / weighted random / lowest latency）路由请求
- **Protocol Conversion** — Anthropic ↔ OpenAI ↔ Responses ↔ Gemini 自动互转
- **Cross-Model Retry** — 一个模型失败自动换下一个，无需客户端重试
- **Per-Model Cooldown** — 429 / 401 自动冷却，不影响其他模型
- **Auto-Update** — `oar update` 一键更新，自动重启

## Quick Start

```bash
# 下载 oar 二进制，放到 PATH 里
# macOS ARM64:
curl -Lo /usr/local/bin/oar https://github.com/SnowAIGirl/open-agent-router/releases/latest/download/oar-darwin-arm64

chmod +x /usr/local/bin/oar

# 启动服务
oar start

# 查看状态
oar status
```

### 添加一个账号

```bash
oar account create \
  --name my-deepseek \
  --platform deepseek \
  --base-url https://api.deepseek.com \
  --key sk-xxxxxxxx
```

### 让 agent 连上来

```bash
# Claude Code
export ANTHROPIC_BASE_URL=http://127.0.0.1:26969
claude

# Codex / Claude CLI
export OPENAI_BASE_URL=http://127.0.0.1:26969
codex

# 更多 agent 配置见 oar agent list
oar agent list
```

## How It Works

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│  Claude Code │     │                  │     │   DeepSeek   │
│     Codex    │────▶│   OAR Proxy      │────▶│   OpenAI     │
│  Gemini CLI  │     │   localhost:     │     │   Anthropic  │
│  Kimi Code   │     │   26969          │     │   Gemini     │
│  Qwen Code   │     │                  │     │   自托管 LLM  │
└──────────────┘     └──────────────────┘     └──────────────┘
                          │
                     ┌────┴────┐
                     │  SQLite │
                     │  config │
                     └─────────┘
```

所有 agent 指向同一个本地端口，OAR 根据请求路径按 project → agent → group → model 四层路由，自动做协议转换和故障转移。

## Download

| Platform | Download |
|---|---|
| macOS ARM64 | [oar-darwin-arm64](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| macOS x64 | [oar-darwin-x64](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| Linux x64 | [oar-linux-x64](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| Windows x64 | [oar-win-x64.exe](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| macOS .dmg | [Open Agent Router.dmg](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |
| Linux .deb / .rpm | [GitHub Releases](https://github.com/SnowAIGirl/open-agent-router/releases/latest) |

> 也可用 `oar update` 在已有安装上自动更新。

## Requirements

- macOS 14+ / Linux / Windows
- Node.js 22+（仅构建时需要）
- Bun（仅构建时需要）

## Architecture

```
oar                         单个二进制，三个模式：
├── start                   长驻代理服务
├── update                  自更新
├── status / account / ...  管理 CLI

Core (TypeScript → Bun compile):
├── proxy/                  请求代理 + 协议转换
│   ├── adapters/           a2o, o2o, r2o, g2o ...
│   └── protocol.ts         协议矩阵
├── server/                 Express HTTP 服务
│   └── routes/
│       ├── admin.ts        管理 API
│       └── proxy.ts        代理路由
├── config-manager/         为 agent 生成连接配置
├── service/                服务管理 + 自更新
└── db/                     SQLite 配置存储
```

## License

MIT
