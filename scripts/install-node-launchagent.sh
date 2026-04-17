#!/usr/bin/env bash
# install-node-launchagent.sh
# 自動偵測環境並安裝 OpenClaw Node LaunchAgent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_TEMPLATE="$SCRIPT_DIR/com.openclaw.node.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.openclaw.node.plist"
LABEL="com.openclaw.node"

# ── 顏色輸出 ────────────────────────────────────────────────
red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[0;33m%s\033[0m\n" "$*"; }
bold()  { printf "\033[1m%s\033[0m\n" "$*"; }

# ── 偵測 openclaw binary 路徑 ────────────────────────────────
detect_openclaw_bin() {
    # 1. 先試 PATH（如 nvm 已載入）
    if command -v openclaw &>/dev/null; then
        command -v openclaw
        return
    fi

    # 2. 嘗試載入 nvm 再找
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$nvm_dir/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        source "$nvm_dir/nvm.sh" --no-use 2>/dev/null || true
        if command -v openclaw &>/dev/null; then
            command -v openclaw
            return
        fi
    fi

    # 3. 掃描 nvm 所有版本目錄
    local match
    match=$(find "$HOME/.nvm/versions/node" -name "openclaw" -type f 2>/dev/null | sort -V | tail -1)
    if [[ -n "$match" ]]; then
        echo "$match"
        return
    fi

    # 4. 找不到
    echo ""
}

# ── 偵測 Gateway Token ───────────────────────────────────────
detect_token() {
    local config="$HOME/.openclaw/openclaw.json"
    if [[ -f "$config" ]]; then
        # 嘗試用 jq 解析
        if command -v jq &>/dev/null; then
            jq -r '.gatewayToken // empty' "$config" 2>/dev/null || true
            return
        fi
        # fallback: grep 簡單解析
        grep -o '"gatewayToken"[[:space:]]*:[[:space:]]*"[^"]*"' "$config" 2>/dev/null \
            | sed 's/.*: *"\(.*\)"/\1/' || true
    fi
}

# ════════════════════════════════════════════════════════════
bold "=== OpenClaw Node LaunchAgent 安裝程式 ==="
echo ""

# ── Step 1: openclaw 路徑 ────────────────────────────────────
OPENCLAW_BIN=$(detect_openclaw_bin)

if [[ -n "$OPENCLAW_BIN" ]]; then
    green "✓ 偵測到 openclaw：$OPENCLAW_BIN"
else
    yellow "⚠ 找不到 openclaw binary，請手動輸入完整路徑"
    yellow "  (例：/Users/$USER/.nvm/versions/node/v22.22.1/bin/openclaw)"
fi

read -rp "  openclaw 路徑 [${OPENCLAW_BIN:-請輸入}]: " INPUT_BIN
OPENCLAW_BIN="${INPUT_BIN:-$OPENCLAW_BIN}"

if [[ -z "$OPENCLAW_BIN" || ! -f "$OPENCLAW_BIN" ]]; then
    red "✗ 找不到此路徑的 openclaw，請確認後再執行"
    exit 1
fi

echo ""

# ── Step 2: Gateway Token ────────────────────────────────────
DETECTED_TOKEN=$(detect_token)

if [[ -n "$DETECTED_TOKEN" ]]; then
    green "✓ 偵測到 Gateway Token（來自 ~/.openclaw/openclaw.json）"
    DISPLAY_TOKEN="${DETECTED_TOKEN:0:8}..."
    echo "  Token 前 8 碼：$DISPLAY_TOKEN"
else
    yellow "⚠ 找不到 Gateway Token，請手動輸入"
fi

read -rp "  Gateway Token [${DETECTED_TOKEN:+偵測到，直接 Enter 使用}]: " INPUT_TOKEN
GATEWAY_TOKEN="${INPUT_TOKEN:-$DETECTED_TOKEN}"

if [[ -z "$GATEWAY_TOKEN" ]]; then
    red "✗ Gateway Token 不可為空"
    exit 1
fi

echo ""

# ── Step 3: 顯示名稱 ─────────────────────────────────────────
DEFAULT_NAME="Mac Mini Node"
read -rp "  Node 顯示名稱 [$DEFAULT_NAME]: " INPUT_NAME
DISPLAY_NAME="${INPUT_NAME:-$DEFAULT_NAME}"

echo ""

# ── Step 4: 寫入 plist ───────────────────────────────────────
bold "=== 即將安裝 ==="
echo "  binary    : $OPENCLAW_BIN"
echo "  token     : ${GATEWAY_TOKEN:0:8}..."
echo "  名稱      : $DISPLAY_NAME"
echo "  安裝位置  : $PLIST_DEST"
echo ""
read -rp "確認安裝？[Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

NODE_BIN_DIR="$(dirname "$OPENCLAW_BIN")"

sed \
    -e "s|__OPENCLAW_BIN__|${OPENCLAW_BIN}|g" \
    -e "s|__NODE_BIN_DIR__|${NODE_BIN_DIR}|g" \
    -e "s|__DISPLAY_NAME__|${DISPLAY_NAME}|g" \
    -e "s|__GATEWAY_TOKEN__|${GATEWAY_TOKEN}|g" \
    "$PLIST_TEMPLATE" > "$PLIST_DEST"

# ── Step 5: 載入 ─────────────────────────────────────────────
# 如果已載入過，先卸載再重新載入
if launchctl list | grep -q "$LABEL" 2>/dev/null; then
    yellow "⚠ 已有舊服務，先卸載..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

launchctl load "$PLIST_DEST"

echo ""
green "✓ LaunchAgent 安裝完成！"
echo ""
echo "  查看狀態：launchctl list | grep openclaw"
echo "  查看 log ：cat /tmp/openclaw-node.log"
echo "  停止服務 ：launchctl unload $PLIST_DEST"
echo "  完整卸載 ：bash $SCRIPT_DIR/uninstall-node-launchagent.sh"
