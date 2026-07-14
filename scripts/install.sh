#!/usr/bin/env bash
set -euo pipefail

# OAR Installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/SnowAIGirl/open-agent-router/master/scripts/install.sh)

OAR_HOME="${OAR_HOME:-$HOME/.open-agent-router}"

GITHUB_API="https://api.github.com/repos/SnowAIGirl/open-agent-router/releases/latest"
GITEE_API="https://gitee.com/api/v5/repos/SnowAIGirl/open-agent-router/releases?page=1&per_page=1"

# Detect platform
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) PLATFORM="linux-x64" ;;
  aarch64|arm64) PLATFORM="linux-arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-service) NO_SERVICE=1; shift ;;
    --help) echo "Usage: bash install.sh [--no-service]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Check existing installation ──
LOCAL_VER=""
if [[ -f "$OAR_HOME/manifest.json" ]]; then
  LOCAL_VER=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$OAR_HOME/manifest.json" | cut -d'"' -f4 || true)
fi

# ── Fetch latest release info ──
echo "Checking latest version..."
LATEST_JSON=$(curl -fsSL --connect-timeout 5 --max-time 10 "$GITHUB_API" 2>/dev/null || \
              curl -fsSL --connect-timeout 5 --max-time 10 "$GITEE_API" 2>/dev/null || true)

if [[ -z "$LATEST_JSON" ]]; then
  echo "Failed to check for latest version"
  echo "Check: https://github.com/SnowAIGirl/open-agent-router/releases"
  exit 1
fi

LATEST_VER=$(echo "$LATEST_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]*"' | sed 's/.*"v\([^"]*\)".*/\1/' || true)
ASSET_NAME="oar-update-${PLATFORM}.tar.gz"
DOWNLOAD_URL=$(echo "$LATEST_JSON" | grep -o "\"browser_download_url\":\"[^\"]*${ASSET_NAME}[^\"]*\"" | head -1 | cut -d'"' -f4 || true)

if [[ -z "$LATEST_VER" || -z "$DOWNLOAD_URL" ]]; then
  echo "Failed to find latest release asset for $PLATFORM"
fi

echo "  Current: ${LOCAL_VER:-not installed}"
echo "  Latest:  $LATEST_VER"

if [[ -n "$LOCAL_VER" && "$LOCAL_VER" == "$LATEST_VER" ]]; then
  echo "Already up to date."
  echo "Re-run to force reinstall, or run 'oar update' to update in-place."
  exit 0
fi

# ── Confirm upgrade ──
if [[ -n "$LOCAL_VER" ]]; then
  echo "Upgrade available: ${LOCAL_VER} → ${LATEST_VER}"
else
  echo "New installation: v${LATEST_VER}"
fi

# ── Download & extract ──
mkdir -p "$OAR_HOME"
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

echo "Downloading..."
curl -fSL --connect-timeout 5 --max-time 120 "$DOWNLOAD_URL" -o "$TMPDIR/update.tar.gz"

echo "Extracting..."
tar xzf "$TMPDIR/update.tar.gz" -C "$OAR_HOME"

# ── Add to PATH ──
OAR_BIN="$OAR_HOME/oar"
chmod +x "$OAR_BIN"

if ln -sf "$OAR_BIN" /usr/local/bin/oar 2>/dev/null; then
  echo "  Symlinked to /usr/local/bin/oar"
elif [[ -d "$HOME/.local/bin" ]] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
  ln -sf "$OAR_BIN" "$HOME/.local/bin/oar"
  echo "  Symlinked to ~/.local/bin/oar"
  case ":$PATH:" in
    *:"$HOME/.local/bin":*) ;;
    *)
      for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$rc" ]]; then
          echo "" >> "$rc"
          echo "# OAR" >> "$rc"
          echo "export PATH=\"\$PATH:$HOME/.local/bin\"" >> "$rc"
          echo "  Added ~/.local/bin to $rc"
          break
        fi
      done
      ;;
  esac
else
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]]; then
      echo "" >> "$rc"
      echo "# OAR" >> "$rc"
      echo "export PATH=\"\$PATH:$OAR_HOME/bin\"" >> "$rc"
      echo "  Added $OAR_HOME/bin to $rc"
      break
    fi
  done
fi

# ── Register systemd user service ──
if [[ -z "${NO_SERVICE:-}" ]] && command -v systemctl &>/dev/null; then
  echo "Registering systemd user service ..."
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/oar.service" <<EOF
[Unit]
Description=Open Agent Router
After=network-online.target

[Service]
Type=simple
ExecStart=${OAR_HOME}/oar start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable oar.service
  systemctl --user start oar.service
  echo "Service started"
else
  echo "Run 'oar start' to start the service"
fi

echo ""
echo "OAR v${LATEST_VER} installed."
echo "Open a new terminal or run:"
echo "  export PATH=\"\$PATH:${OAR_BIN%/*}\""
echo "  oar --help"
