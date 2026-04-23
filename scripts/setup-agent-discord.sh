#!/bin/bash
# setup-agent-discord.sh
#
# 新增單一 OpenClaw Agent 的 Discord 設定（互動式）。
#
# 前置條件：
#   1. openclaw-gateway 容器已在執行中
#   2. openclaw-server/.env 中已填入 DISCORD_USER_ID 與 DISCORD_SERVER_ID
#
# 使用方式：
#   bash scripts/setup-agent-discord.sh              # 互動模式
#   bash scripts/setup-agent-discord.sh --yes        # 非互動，需搭配 single-agent.yml
#
# single-agent.yml（可選，作為預填值）：
#   複製 single-agent.example.yml → single-agent.yml 並填入設定

set -e

# ==========================================
# 參數解析
# ==========================================

AUTO_YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      AUTO_YES=true
      shift
      ;;
    *)
      echo "❌ 未知參數: $1"
      echo "使用方式: bash scripts/setup-agent-discord.sh [--yes]"
      exit 1
      ;;
  esac
done

# ==========================================
# 路徑與 .env 載入
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SINGLE_AGENT_YAML="$REPO_ROOT/single-agent.yml"

if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$REPO_ROOT/.env"
  set +a
else
  echo "⚠️ 找不到 $REPO_ROOT/.env"
fi

# ==========================================
# 解析 single-agent.yml（可選的預填檔）
# ==========================================

YAML_ID=""
YAML_NAME=""
YAML_TOKEN_ENV=""

if [ -f "$SINGLE_AGENT_YAML" ]; then
  YAML_ID="$(awk '/^id:/ { gsub(/"/, "", $2); print $2 }' "$SINGLE_AGENT_YAML")"
  YAML_NAME="$(awk '/^name:/ { sub(/^name: *"?/, ""); sub(/"? *$/, ""); print }' "$SINGLE_AGENT_YAML")"
  YAML_TOKEN_ENV="$(awk '/^token_env:/ { print $2 }' "$SINGLE_AGENT_YAML")"
fi

# ==========================================
# 預設值
# ==========================================

DEFAULT_AGENT_ID="${YAML_ID:-my-agent}"
DEFAULT_AGENT_NAME="${YAML_NAME:-My Agent}"
DEFAULT_TOKEN_ENV_VAR="${YAML_TOKEN_ENV:-}"

CONTAINER="${CONTAINER:-openclaw-gateway}"

# ==========================================
# 工具函數
# ==========================================

prompt_input() {
  local prompt="$1"
  local default="$2"
  local input

  printf "%s [%s]: " "$prompt" "$default" >&2
  read -r input
  echo "${input:-$default}"
}

prompt_confirm() {
  local prompt="$1"
  local input

  printf "%s [Y/n]: " "$prompt" >&2
  read -r input
  case "${input:-Y}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

derive_token_var() {
  local agent_id="$1"
  local upper
  upper="$(echo "$agent_id" | tr '[:lower:]-' '[:upper:]_')"
  echo "DISCORD_BOT_TOKEN_${upper}"
}

# ==========================================
# 設定流程
# ==========================================

interactive_setup() {
  echo ""
  echo "=========================================="
  echo "⚙️  Agent 設定（按 Enter 使用預設值）"
  echo "=========================================="
  echo ""

  AGENT_ID="$(prompt_input "id" "$DEFAULT_AGENT_ID")"
  AGENT_NAME="$(prompt_input "name" "$DEFAULT_AGENT_NAME")"

  local default_token_env="${DEFAULT_TOKEN_ENV_VAR:-$(derive_token_var "$AGENT_ID")}"
  TOKEN_ENV_VAR="$(prompt_input "token_env" "$default_token_env")"

  print_summary
  echo ""

  if ! prompt_confirm "確認以上設定並開始建立 Agent？"; then
    echo ""
    echo "🚫 已取消"
    exit 0
  fi
}

non_interactive_setup() {
  if [ -z "$YAML_ID" ]; then
    echo "❌ --yes 模式需要 single-agent.yml，請先建立 $SINGLE_AGENT_YAML"
    exit 1
  fi

  AGENT_ID="$DEFAULT_AGENT_ID"
  AGENT_NAME="$DEFAULT_AGENT_NAME"
  TOKEN_ENV_VAR="${DEFAULT_TOKEN_ENV_VAR:-$(derive_token_var "$AGENT_ID")}"

  print_summary
}

print_summary() {
  echo ""
  echo "=========================================="
  echo "📋 設定摘要"
  echo "=========================================="
  echo "  id:         $AGENT_ID"
  echo "  name:       $AGENT_NAME"
  echo "  token_env:  $TOKEN_ENV_VAR"
}

# ==========================================
# CLI 與容器檢查
# ==========================================

check_container() {
  if [ ! -f "$REPO_ROOT/docker-compose.yml" ]; then
    echo "❌ 找不到 $REPO_ROOT/docker-compose.yml"
    exit 1
  fi

  if ! docker info &>/dev/null; then
    echo "❌ Docker 未在執行，請先啟動 Docker"
    exit 1
  fi

  echo "🔍 確認 Gateway 狀態..."
  (cd "$REPO_ROOT" && docker compose up -d openclaw-gateway) 2>/dev/null || true
  local retries=15
  while [ "$retries" -gt 0 ]; do
    local state
    state="$(docker inspect -f '{{.State.Status}}' openclaw-gateway 2>/dev/null || echo "missing")"
    if [ "$state" = "running" ]; then
      break
    fi
    echo "  ⏳ Gateway 狀態: $state，等待中..."
    sleep 2
    retries=$((retries - 1))
  done
  if [ "$retries" -eq 0 ]; then
    echo "❌ Gateway 未能在時限內進入 running 狀態"
    echo "   請手動執行：docker compose up -d openclaw-gateway"
    exit 1
  fi
}

check_base_env() {
  local all_ok=true

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
# 安裝
# ==========================================

install_agent() {
  echo ""
  echo "=========================================="
  echo "🚀 建立 Agent: $AGENT_ID ($AGENT_NAME)"
  echo "=========================================="

  echo ""
  echo "🔍 檢查基礎環境變數..."
  check_base_env

  # 確保在正確的目錄執行，以便 docker compose 讀取設定
  pushd "$REPO_ROOT" >/dev/null

  # 將所有 CLI 指令包在單一容器執行，避免多次 docker compose run
  # 導致 Gateway 反覆重啟
  docker compose run --rm --entrypoint /bin/sh openclaw-cli -c "
    echo '→ [階段 1/4] 啟用 Discord 通道與基礎設定...'
    openclaw config set channels.discord.enabled true --strict-json
    openclaw config set channels.discord.groupPolicy allowlist
    openclaw config set channels.discord.streaming progress

    echo '→ [階段 2/4] 建立 Agent 工作區與身份識別...'
    openclaw agents add ${AGENT_ID} 2>/dev/null || true
    openclaw agents set-identity --name '${AGENT_NAME}' --agent ${AGENT_ID} 2>/dev/null || true

    echo '→ [階段 3/4] 註冊 Discord 帳號 Token 與白名單...'
    openclaw config set channels.discord.accounts.${AGENT_ID}.token --ref-provider default --ref-source env --ref-id ${TOKEN_ENV_VAR}
    openclaw config set channels.discord.accounts.${AGENT_ID}.allowFrom '[\"user:${DISCORD_USER_ID}\"]' --strict-json
    openclaw config set channels.discord.accounts.${AGENT_ID}.guilds '{}' --strict-json
    openclaw config set channels.discord.accounts.${AGENT_ID}.guilds.${DISCORD_SERVER_ID} '{\"requireMention\": true, \"users\": [\"${DISCORD_USER_ID}\"]}' --strict-json

    echo '→ [階段 4/4] 建立路由綁定 (Routing)...'
    openclaw agents bind --agent ${AGENT_ID} --bind discord:${AGENT_ID}
  "

  popd >/dev/null

  echo ""
  echo "=========================================="
  echo "✅ Agent $AGENT_ID 設定完成！"
  echo "=========================================="
  echo ""
  echo "⚠️  還需要以下步驟才能讓 Bot 上線："
  echo ""
  echo "  1. 在 openclaw-server/.env 加入 Bot Token："
  echo "     ${TOKEN_ENV_VAR}=<your_discord_bot_token>"
  echo ""
  echo "  2. 重啟 Gateway："
  echo "     docker compose restart openclaw-gateway"
}

# ==========================================
# 主程式
# ==========================================

check_container

if [ "$AUTO_YES" = true ]; then
  non_interactive_setup
  install_agent
else
  interactive_setup
  install_agent
fi
