#!/bin/bash
# setup-agent-discord.sh
#
# 通用 OpenClaw Agent 建立腳本（互動式）。
# 執行時會詢問 Agent 名稱、ID 等設定，每項均有預設值可直接 Enter 跳過。
#
# 前置條件：
#   1. openclaw-gateway 容器已在執行中
#   2. .env 中已填入對應的 DISCORD_BOT_TOKEN_xxx
#   3. .env 中已填入 DISCORD_USER_ID 與 DISCORD_SERVER_ID
#
# 使用方式：
#   bash scripts/setup-agent-discord.sh                            # 互動模式
#   bash scripts/setup-agent-discord.sh --yes                      # 跳過互動，使用預設值
#   bash scripts/setup-agent-discord.sh --project /path/to/repo    # 載入專案 .env 作為預設值
#   bash scripts/setup-agent-discord.sh --remove                   # 移除 Agent
#   bash scripts/setup-agent-discord.sh --remove --yes             # 直接移除預設 Agent
#

set -e

# ==========================================
# 參數解析
# ==========================================

AUTO_YES=false
REMOVE_MODE=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      AUTO_YES=true
      shift
      ;;
    --remove)
      REMOVE_MODE=true
      shift
      ;;
    --project)
      PROJECT_DIR="$2"
      shift 2
      ;;
    *)
      echo "❌ 未知參數: $1"
      echo "使用方式: bash scripts/setup-agent-discord.sh [--yes] [--remove] [--project /path/to/repo]"
      exit 1
      ;;
  esac
done

# ==========================================
# .env 載入
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. 載入 openclaw-server 的 .env（本 repo）
if [ -f "$REPO_ROOT/.env" ]; then
  echo "📂 載入 OpenClaw .env: $REPO_ROOT/.env"
  set -a
  # shellcheck disable=SC1090
  source "$REPO_ROOT/.env"
  set +a
else
  echo "⚠️ 找不到 $REPO_ROOT/.env"
fi

# 2. 載入指定專案的 .env（覆蓋 Agent 專屬設定）
if [ -n "$PROJECT_DIR" ]; then
  if [ -f "$PROJECT_DIR/.env" ]; then
    echo "📂 載入 Project .env: $PROJECT_DIR/.env"
    set -a
    # shellcheck disable=SC1090
    source "$PROJECT_DIR/.env"
    set +a
  else
    echo "⚠️ 找不到 $PROJECT_DIR/.env，將使用預設值"
  fi
fi

# ==========================================
# 預設值（.env 中的值 > 寫死的 fallback）
# ==========================================

DEFAULT_AGENT_ID="${AGENT_ID:-my-agent}"
DEFAULT_AGENT_NAME="${AGENT_NAME:-My Agent}"
DEFAULT_TOKEN_ENV_VAR="${TOKEN_ENV_VAR:-}"
DEFAULT_WORKSPACE_PATH="${WORKSPACE_PATH:-}"

DEFAULT_HEARTBEAT_EVERY="${HEARTBEAT_EVERY:-60m}"
DEFAULT_HEARTBEAT_TARGET="${HEARTBEAT_TARGET:-discord}"
DEFAULT_HEARTBEAT_ACTIVE_START="${HEARTBEAT_ACTIVE_START:-08:00}"
DEFAULT_HEARTBEAT_ACTIVE_END="${HEARTBEAT_ACTIVE_END:-24:00}"
DEFAULT_HEARTBEAT_TIMEZONE="${HEARTBEAT_TIMEZONE:-Asia/Taipei}"

# OpenClaw 容器名稱
CONTAINER="${CONTAINER:-openclaw-gateway}"

# ==========================================
# 互動式輸入工具
# ==========================================

# 讀取使用者輸入，若空白則回傳預設值
# Usage: prompt_input "提示文字" "預設值"
prompt_input() {
  local prompt="$1"
  local default="$2"
  local input

  printf "%s [%s]: " "$prompt" "$default"
  read -r input
  echo "${input:-$default}"
}

# 確認 Y/n 提示 (預設 Y)
prompt_confirm() {
  local prompt="$1"
  local input

  printf "%s [Y/n]: " "$prompt"
  read -r input
  case "${input:-Y}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# 根據 AGENT_ID 自動推導 Token 環境變數名稱
# 例: my-bot → DISCORD_BOT_TOKEN_MY_BOT
derive_token_var() {
  local agent_id="$1"
  local upper
  upper="$(echo "$agent_id" | tr '[:lower:]-' '[:upper:]_')"
  echo "DISCORD_BOT_TOKEN_${upper}"
}

# 根據 AGENT_ID 自動推導 Workspace 路徑
# 例: my-bot → /home/node/.openclaw/workspace-my-bot
derive_workspace() {
  local agent_id="$1"
  echo "/home/node/.openclaw/workspace-${agent_id}"
}

# ==========================================
# 互動式設定流程
# ==========================================

interactive_setup() {
  echo ""
  echo "=========================================="
  echo "⚙️  Agent 設定（按 Enter 使用預設值）"
  echo "=========================================="
  echo ""

  # --- 核心設定 ---
  AGENT_ID="$(prompt_input "Agent ID（唯一識別碼，建議 kebab-case）" "$DEFAULT_AGENT_ID")"
  AGENT_NAME="$(prompt_input "Agent 顯示名稱" "$DEFAULT_AGENT_NAME")"

  # 當使用者自訂了 AGENT_ID，自動推導 TOKEN_ENV_VAR 與 WORKSPACE_PATH
  if [ -z "$DEFAULT_TOKEN_ENV_VAR" ] || [ "$AGENT_ID" != "$DEFAULT_AGENT_ID" ]; then
    DEFAULT_TOKEN_ENV_VAR="$(derive_token_var "$AGENT_ID")"
  fi
  if [ -z "$DEFAULT_WORKSPACE_PATH" ] || [ "$AGENT_ID" != "$DEFAULT_AGENT_ID" ]; then
    DEFAULT_WORKSPACE_PATH="$(derive_workspace "$AGENT_ID")"
  fi

  TOKEN_ENV_VAR="$(prompt_input "Discord Token 環境變數名稱" "$DEFAULT_TOKEN_ENV_VAR")"
  WORKSPACE_PATH="$(prompt_input "容器內 Workspace 路徑" "$DEFAULT_WORKSPACE_PATH")"

  # --- Heartbeat 設定 ---
  echo ""
  if prompt_confirm "是否自訂 Heartbeat 排程？（預設使用標準設定）"; then
    HEARTBEAT_EVERY="$(prompt_input "  排程間隔" "$DEFAULT_HEARTBEAT_EVERY")"
    HEARTBEAT_TARGET="$(prompt_input "  通知目標" "$DEFAULT_HEARTBEAT_TARGET")"
    HEARTBEAT_ACTIVE_START="$(prompt_input "  活動開始時間" "$DEFAULT_HEARTBEAT_ACTIVE_START")"
    HEARTBEAT_ACTIVE_END="$(prompt_input "  活動結束時間" "$DEFAULT_HEARTBEAT_ACTIVE_END")"
    HEARTBEAT_TIMEZONE="$(prompt_input "  時區" "$DEFAULT_HEARTBEAT_TIMEZONE")"
  else
    HEARTBEAT_EVERY="$DEFAULT_HEARTBEAT_EVERY"
    HEARTBEAT_TARGET="$DEFAULT_HEARTBEAT_TARGET"
    HEARTBEAT_ACTIVE_START="$DEFAULT_HEARTBEAT_ACTIVE_START"
    HEARTBEAT_ACTIVE_END="$DEFAULT_HEARTBEAT_ACTIVE_END"
    HEARTBEAT_TIMEZONE="$DEFAULT_HEARTBEAT_TIMEZONE"
  fi

  # --- 確認摘要 ---
  print_summary
  echo ""

  if ! prompt_confirm "確認以上設定並開始建立 Agent？"; then
    echo ""
    echo "🚫 已取消"
    exit 0
  fi
}

# 跳過互動，直接使用預設值
non_interactive_setup() {
  AGENT_ID="$DEFAULT_AGENT_ID"
  AGENT_NAME="$DEFAULT_AGENT_NAME"

  # 自動推導（若 .env 未提供）
  TOKEN_ENV_VAR="${DEFAULT_TOKEN_ENV_VAR:-$(derive_token_var "$AGENT_ID")}"
  WORKSPACE_PATH="${DEFAULT_WORKSPACE_PATH:-$(derive_workspace "$AGENT_ID")}"

  HEARTBEAT_EVERY="$DEFAULT_HEARTBEAT_EVERY"
  HEARTBEAT_TARGET="$DEFAULT_HEARTBEAT_TARGET"
  HEARTBEAT_ACTIVE_START="$DEFAULT_HEARTBEAT_ACTIVE_START"
  HEARTBEAT_ACTIVE_END="$DEFAULT_HEARTBEAT_ACTIVE_END"
  HEARTBEAT_TIMEZONE="$DEFAULT_HEARTBEAT_TIMEZONE"

  print_summary
}

print_summary() {
  echo ""
  echo "=========================================="
  echo "📋 設定摘要"
  echo "=========================================="
  echo "  Agent ID:       $AGENT_ID"
  echo "  Agent 名稱:     $AGENT_NAME"
  echo "  Token 變數:     $TOKEN_ENV_VAR"
  echo "  Workspace:      $WORKSPACE_PATH"
  echo "  Heartbeat:      every ${HEARTBEAT_EVERY}, ${HEARTBEAT_ACTIVE_START}-${HEARTBEAT_ACTIVE_END} (${HEARTBEAT_TIMEZONE})"
}

# ==========================================
# CLI 與檢查函數
# ==========================================

cli() {
  docker exec -it "$CONTAINER" openclaw "$@"
}

check_container() {
  if ! docker inspect "$CONTAINER" &>/dev/null; then
    echo "❌ 找不到容器 $CONTAINER"
    echo "   請先啟動：cd openclaw-server && docker compose up -d"
    exit 1
  fi

  if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
    echo "❌ 容器 $CONTAINER 未在執行"
    echo "   請先啟動：cd openclaw-server && docker compose up -d"
    exit 1
  fi
}

check_env_vars() {
  local all_ok=true

  if [ -z "${!TOKEN_ENV_VAR}" ]; then
    echo "  ❌ 缺少 $TOKEN_ENV_VAR"
    all_ok=false
  else
    echo "  ✅ $TOKEN_ENV_VAR 已設定"
  fi

  if [ -z "${DISCORD_USER_ID}" ]; then
    echo "  ❌ 缺少 DISCORD_USER_ID"
    all_ok=false
  else
    echo "  ✅ DISCORD_USER_ID 已設定"
  fi

  if [ -z "${DISCORD_SERVER_ID}" ]; then
    echo "  ❌ 缺少 DISCORD_SERVER_ID"
    all_ok=false
  else
    echo "  ✅ DISCORD_SERVER_ID 已設定"
  fi

  if [ "$all_ok" = false ]; then
    echo ""
    echo "❌ 請在 .env 中補齊缺少的設定"
    exit 1
  fi
}

# ==========================================
# 安裝 / 移除
# ==========================================

install_agent() {
  echo ""
  echo "=========================================="
  echo "🚀 建立 Agent: $AGENT_ID ($AGENT_NAME)"
  echo "=========================================="

  echo ""
  echo "🔍 檢查環境變數..."
  check_env_vars

  echo ""
  echo "→ 1/5 建立 Agent..."
  cli agents add "$AGENT_ID" 2>/dev/null || echo "  (Agent 已存在，跳過)"

  echo "→ 2/5 設定 Identity 與 Workspace..."
  cli agents set-identity --name "$AGENT_NAME" --agent "$AGENT_ID" 2>/dev/null || true
  cli config set "agents.list.${AGENT_ID}.workspace" "$WORKSPACE_PATH"

  echo "→ 3/5 註冊 Discord 帳號..."
  cli config set "channels.discord.accounts.${AGENT_ID}.token" \
    --ref-provider default --ref-source env --ref-id "$TOKEN_ENV_VAR"
  cli config set "channels.discord.accounts.${AGENT_ID}.allowFrom" \
    "[\"user:${DISCORD_USER_ID}\"]" --strict-json
  cli config set "channels.discord.accounts.${AGENT_ID}.guilds.${DISCORD_SERVER_ID}" \
    "{\"requireMention\": true, \"users\": [\"${DISCORD_USER_ID}\"]}" --strict-json

  echo "→ 4/5 建立路由綁定..."
  cli agents bind --agent "$AGENT_ID" --bind "discord:${AGENT_ID}"

  echo "→ 5/5 設定 Heartbeat..."
  local heartbeat_json
  heartbeat_json=$(cat <<EOF
{
  "every": "${HEARTBEAT_EVERY}",
  "target": "${HEARTBEAT_TARGET}",
  "lightContext": true,
  "isolatedSession": true,
  "activeHours": {
    "start": "${HEARTBEAT_ACTIVE_START}",
    "end": "${HEARTBEAT_ACTIVE_END}",
    "timezone": "${HEARTBEAT_TIMEZONE}"
  }
}
EOF
)
  # 壓成單行餵給 CLI
  cli config set "agents.list.${AGENT_ID}.heartbeat" \
    "$(echo "$heartbeat_json" | tr -d '\n' | tr -s ' ')" --strict-json

  echo ""
  echo "=========================================="
  echo "✅ Agent $AGENT_ID 配置完成！"
  echo "=========================================="
  echo ""
  echo "下一步："
  echo "  1. 確認 docker-compose.yml 有掛載 workspace volume"
  echo ""
  echo "  2. 重啟 Gateway："
  echo "     docker compose restart openclaw-gateway"
  echo ""
  echo "  3. 確認 workspace 中有 HEARTBEAT.md（若需要心跳功能）"
}

remove_agent() {
  echo ""
  echo "=========================================="
  echo "🗑️  移除 Agent: $AGENT_ID"
  echo "=========================================="

  echo "→ 移除路由綁定..."
  cli agents unbind --agent "$AGENT_ID" 2>/dev/null || true

  echo "→ 移除 Discord 帳號設定..."
  cli config delete "channels.discord.accounts.${AGENT_ID}" 2>/dev/null || true

  echo "→ 移除 Heartbeat 設定..."
  cli config delete "agents.list.${AGENT_ID}.heartbeat" 2>/dev/null || true

  echo "→ 移除 Agent..."
  cli agents remove "$AGENT_ID" 2>/dev/null || true

  echo ""
  echo "✅ Agent $AGENT_ID 已移除"
  echo "   請重啟 Gateway：docker compose restart openclaw-gateway"
}

# ==========================================
# 主程式
# ==========================================

check_container

if [ "$REMOVE_MODE" = true ]; then
  if [ "$AUTO_YES" = true ]; then
    non_interactive_setup
  else
    echo ""
    AGENT_ID="$(prompt_input "要移除的 Agent ID" "$DEFAULT_AGENT_ID")"
    echo ""
    if ! prompt_confirm "確定要移除 Agent「$AGENT_ID」？"; then
      echo "🚫 已取消"
      exit 0
    fi
  fi
  remove_agent
elif [ "$AUTO_YES" = true ]; then
  non_interactive_setup
  install_agent
else
  interactive_setup
  install_agent
fi
