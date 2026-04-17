#!/usr/bin/env bash
# uninstall-node-launchagent.sh
# 停止並卸載 OpenClaw Node LaunchAgent

set -euo pipefail

PLIST_DEST="$HOME/Library/LaunchAgents/com.openclaw.node.plist"
LABEL="com.openclaw.node"

# ── 顏色輸出 ────────────────────────────────────────────────
red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[0;33m%s\033[0m\n" "$*"; }
bold()  { printf "\033[1m%s\033[0m\n" "$*"; }

bold "=== OpenClaw Node LaunchAgent 卸載程式 ==="
echo ""

# ── Step 1: 停止服務 ─────────────────────────────────────────
if launchctl list | grep -q "$LABEL" 2>/dev/null; then
    yellow "⚠ 偵測到服務正在執行，準備停止..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    green "✓ 服務已停止"
else
    echo "  服務未在執行，略過"
fi

echo ""

# ── Step 2: 刪除 plist ───────────────────────────────────────
if [[ -f "$PLIST_DEST" ]]; then
    read -rp "  刪除 plist 設定檔？[$PLIST_DEST] [Y/n]: " CONFIRM
    CONFIRM="${CONFIRM:-Y}"
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        rm "$PLIST_DEST"
        green "✓ plist 已刪除"
    else
        yellow "⚠ plist 保留：$PLIST_DEST"
        echo "  若需重新載入：launchctl load $PLIST_DEST"
    fi
else
    echo "  plist 不存在，無需刪除"
fi

echo ""
green "✓ 卸載完成"
echo ""
echo "  重新安裝：bash scripts/install-node-launchagent.sh"
