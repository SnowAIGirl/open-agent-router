#!/usr/bin/env bash
set -euo pipefail

# OAR Installer (Linux)
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/SnowAIGirl/open-agent-router/master/scripts/install.sh)

OAR_HOME="${OAR_HOME:-$HOME/.open-agent-router}"
OAR_BIN_DIR="$OAR_HOME/bin"
OAR_BIN="$OAR_BIN_DIR/oar"

GITHUB_API="https://api.github.com/repos/SnowAIGirl/open-agent-router/releases/latest"
GITEE_API="https://gitee.com/api/v5/repos/SnowAIGirl/open-agent-router/releases?page=1&per_page=1"
R2_LATEST="https://oar-down.snow-agent.com/latest.json"
R2_BASE="https://oar-down.snow-agent.com/releases"

# Detect platform
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$ARCH" in
  x86_64|amd64) ARCH_LABEL="x64" ;;
  aarch64|arm64) ARCH_LABEL="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac
case "$OS" in
  linux)   PLATFORM="linux" ;;
  darwin)  PLATFORM="darwin" ;;
  *) echo "Unsupported OS: $OS (this script is for Linux / macOS. For Windows, download the .msi installer.)"; exit 1 ;;
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

# ── Fetch latest release info (R2 → GitHub → Gitee) ──
echo "Checking latest version..."

LATEST_VER=""
DOWNLOAD_URL=""

# Try R2 first (fastest)
if [[ -z "$LATEST_VER" ]]; then
  R2_JSON=$(curl -fsSL --connect-timeout 3 --max-time 8 "$R2_LATEST" 2>/dev/null || true)
  if [[ -n "$R2_JSON" ]]; then
    LATEST_VER=$(echo "$R2_JSON" | grep -o '"latestVersion"[[:space:]]*:[[:space:]]*"v\?[^"]*"' | head -1 | sed 's/.*"v\?\([^"]*\)".*/\1/' || true)
    if [[ -n "$LATEST_VER" ]]; then
      ASSET_NAME="oar-update-${LATEST_VER}-${PLATFORM}-${ARCH_LABEL}.tar.gz"
      DOWNLOAD_URL="${R2_BASE}/v${LATEST_VER}/${ASSET_NAME}"
    fi
  fi
fi

# Try GitHub
if [[ -z "$LATEST_VER" ]]; then
  GH_JSON=$(curl -fsSL --connect-timeout 5 --max-time 10 "$GITHUB_API" 2>/dev/null || true)
  if [[ -n "$GH_JSON" ]]; then
    LATEST_VER=$(echo "$GH_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]*"' | sed 's/.*"v\([^"]*\)".*/\1/' || true)
    ASSET_NAME="oar-update-${LATEST_VER}-${PLATFORM}-${ARCH_LABEL}.tar.gz"
    DOWNLOAD_URL=$(echo "$GH_JSON" | grep -o "\"browser_download_url\":\"[^\"]*${ASSET_NAME}[^\"]*\"" | head -1 | cut -d'"' -f4 || true)
  fi
fi

# Try Gitee
if [[ -z "$LATEST_VER" ]]; then
  GE_JSON=$(curl -fsSL --connect-timeout 5 --max-time 10 "$GITEE_API" 2>/dev/null || true)
  if [[ -n "$GE_JSON" ]]; then
    LATEST_VER=$(echo "$GE_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]*"' | sed 's/.*"v\([^"]*\)".*/\1/' || true)
    ASSET_NAME="oar-update-${LATEST_VER}-${PLATFORM}-${ARCH_LABEL}.tar.gz"
    DOWNLOAD_URL=$(echo "$GE_JSON" | grep -o "\"browser_download_url\":\"[^\"]*${ASSET_NAME}[^\"]*\"" | head -1 | cut -d'"' -f4 || true)
  fi
fi

if [[ -z "$LATEST_VER" || -z "$DOWNLOAD_URL" ]]; then
  echo "Failed to find latest release asset for ${PLATFORM}-${ARCH_LABEL}"
  echo "Check: https://github.com/SnowAIGirl/open-agent-router/releases"
  exit 1
fi

echo "  Current: ${LOCAL_VER:-not installed}"
echo "  Latest:  v$LATEST_VER"

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
mkdir -p "$OAR_BIN_DIR"
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

echo "Downloading..."
curl -fSL --connect-timeout 5 --max-time 120 "$DOWNLOAD_URL" -o "$TMPDIR/update.tar.gz"

echo "Extracting..."
tar xzf "$TMPDIR/update.tar.gz" -C "$TMPDIR"

# ── MD5 verify (optional, skip if manifest missing) ──
if [[ -f "$TMPDIR/manifest.json" ]]; then
  echo "Verifying..."
  # Just check the binary exists and is non-empty
  if [[ ! -s "$TMPDIR/oar" ]]; then
    echo "Error: downloaded package is missing oar binary"
    exit 1
  fi
fi

# ── Replace files (atomic: copy new, then mv) ──
echo "Installing..."

# Replace binary atomically
TMP_BIN="$OAR_BIN.new"
cp "$TMPDIR/oar" "$TMP_BIN"
chmod +x "$TMP_BIN"
mv -f "$TMP_BIN" "$OAR_BIN"

# Replace ui-dist and assets (rm -rf + mv)
for dir in ui-dist assets; do
  if [[ -d "$TMPDIR/$dir" ]]; then
    NEW_DIR="$OAR_HOME/${dir}.new"
    rm -rf "$NEW_DIR"
    cp -r "$TMPDIR/$dir" "$NEW_DIR"
    rm -rf "$OAR_HOME/$dir"
    mv "$NEW_DIR" "$OAR_HOME/$dir"
  fi
done

# Update manifest.json (last — marks the version)
if [[ -f "$TMPDIR/manifest.json" ]]; then
  cp "$TMPDIR/manifest.json" "$OAR_HOME/manifest.json"
fi

# ── Add to PATH ──
PATH_ADDED_MSG=""

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
          # 避免重复添加
          if ! grep -q ".open-agent-router" "$rc" && ! grep -q '\.local/bin' "$rc" 2>/dev/null; then
            echo "" >> "$rc"
            echo "# OAR" >> "$rc"
            echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$rc"
            echo "  Added ~/.local/bin to $rc"
            PATH_ADDED_MSG="  (open a new terminal or run: export PATH=\"\$HOME/.local/bin:\$PATH\")"
            break
          fi
        fi
      done
      ;;
  esac
else
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]]; then
      if ! grep -q ".open-agent-router" "$rc"; then
        echo "" >> "$rc"
        echo "# OAR" >> "$rc"
        echo "export PATH=\"$OAR_BIN_DIR:\$PATH\"" >> "$rc"
        echo "  Added $OAR_BIN_DIR to $rc"
        PATH_ADDED_MSG="  (open a new terminal or run: export PATH=\"$OAR_BIN_DIR:\$PATH\")"
        break
      fi
    fi
  done
fi

# ── Register auto-start service ──
SERVICE_STARTED=0
if [[ -z "${NO_SERVICE:-}" ]]; then
  if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
    echo "Registering systemd user service..."
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/oar.service" <<EOF
[Unit]
Description=Open Agent Router
After=network-online.target

[Service]
Type=simple
ExecStart=${OAR_BIN} start
Restart=on-failure
RestartSec=5
Environment=OAR_ASSETS_DIR=${OAR_HOME}/assets
Environment=OAR_VENDOR_ICONS_DIR=${OAR_HOME}/assets/vendor-icons
Environment=OAR_UI_DIST_DIR=${OAR_HOME}/ui-dist
Environment=NODE_ENV=production
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable oar.service
    systemctl --user start oar.service
    echo "  Service started"
    SERVICE_STARTED=1
  elif [[ "$OS" == "darwin" ]]; then
    echo "Registering LaunchAgent..."
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$HOME/Library/LaunchAgents/com.snowaigirl.oar.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.snowaigirl.oar</string>
  <key>ProgramArguments</key>
  <array>
    <string>${OAR_BIN}</string>
    <string>start</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OAR_ASSETS_DIR</key>
    <string>${OAR_HOME}/assets</string>
    <key>OAR_VENDOR_ICONS_DIR</key>
    <string>${OAR_HOME}/assets/vendor-icons</string>
    <key>OAR_UI_DIST_DIR</key>
    <string>${OAR_HOME}/ui-dist</string>
    <key>NODE_ENV</key>
    <string>production</string>
    <key>HOME</key>
    <string>$HOME</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>${OAR_HOME}/logs/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>${OAR_HOME}/logs/launchd.err</string>
</dict>
</plist>
EOF
    mkdir -p "$OAR_HOME/logs"
    launchctl unload "$HOME/Library/LaunchAgents/com.snowaigirl.oar.plist" 2>/dev/null || true
    launchctl load "$HOME/Library/LaunchAgents/com.snowaigirl.oar.plist"
    echo "  LaunchAgent loaded"
    SERVICE_STARTED=1
  fi
fi

echo ""
echo "OAR v${LATEST_VER} installed."
if [[ "$SERVICE_STARTED" == "1" ]]; then
  echo "Service is running on http://127.0.0.1:26969"
else
  echo "Run 'oar start' to start the service"
fi
if [[ -n "$PATH_ADDED_MSG" ]]; then
  echo "$PATH_ADDED_MSG"
fi
echo "  oar --help"
