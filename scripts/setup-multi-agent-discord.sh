#!/bin/bash
# setup-multi-agent-discord.sh
#
# 為 OpenClaw Agent 配置 Discord 通道。
#
# 行為模式：
#   - 若專案根目錄存在 agents.yaml → 配置 main + 所有專家 Agent
#   - 若不存在 agents.yaml          → 僅配置 main 帳號
#
# 使用方式：
#   1. 先在 .env 中填入 DISCORD_BOT_TOKEN（main 必填）
#   2. 若需多 Agent，複製 agents.yaml.example → agents.yaml 並填入各 Token
#   3. 執行：
#        ./scripts/setup-multi-agent-discord.sh
#
# 詳細說明：docs/guides/multi-agent-discord.md

set -e

# ==========================================
# 設定：從 agents.yaml 動態載入
# ==========================================
AGENTS=()
AGENT_NAMES=()
TOKEN_VARS=()

CONFIG_FILE="agents.yaml"

# ==========================================
# 前置檢查
# ==========================================

# 確認在專案根目錄執行
if [ ! -f "docker-compose.yml" ]; then
  echo "❌ 請在專案根目錄執行此腳本（docker-compose.yml 所在位置）"
  exit 1
fi

# 確認 .env 存在
if [ ! -f ".env" ]; then
  echo "❌ 找不到 .env 檔案，請先從 .env.example 複製並填入 Token"
  exit 1
fi

# 載入 .env
set -a
# shellcheck disable=SC1091
source .env
set +a

# ==========================================
# 解析 agents.yaml（如果存在）
# 使用 awk 解析，無須額外安裝 yq
# ==========================================

# 將簡易 YAML 轉為 pipe-delimited 格式：id|name|token_env
parse_agents_yaml() {
  awk '
    /^  - id:/ {
      id = $NF
    }
    /^    name:/ {
      # 取 "name:" 之後的所有內容，去除前後引號與空格
      sub(/^    name: *"?/, "")
      sub(/"? *$/, "")
      name = $0
    }
    /^    token_env:/ {
      token_env = $NF
      print id "|" name "|" token_env
    }
  ' "$1"
}

if [ -f "$CONFIG_FILE" ]; then
  echo "📋 偵測到 ${CONFIG_FILE}，將配置 main + 多個專家 Agent..."

  # 解析 YAML 並填充陣列
  while IFS='|' read -r id name token_env; do
    [ -z "$id" ] && continue
    AGENTS+=("$id")
    AGENT_NAMES+=("$name")
    TOKEN_VARS+=("$token_env")
  done < <(parse_agents_yaml "$CONFIG_FILE")

  if [ ${#AGENTS[@]} -eq 0 ]; then
    echo "⚠️  ${CONFIG_FILE} 中 agents 清單為空，僅配置 main 帳號"
  else
    echo "   找到 ${#AGENTS[@]} 個專家 Agent：${AGENTS[*]}"
  fi
else
  echo "ℹ️  未偵測到 ${CONFIG_FILE}，僅配置 main 帳號"
  echo "   若需多 Agent，請複製 agents.yaml.example → agents.yaml"
fi

echo ""

# ==========================================
# 檢查 Token（main 必檢查，專家依設定檔）
# ==========================================

echo "🔍 檢查 .env 中的必要設定..."
ALL_OK=true

if [ -z "${DISCORD_BOT_TOKEN}" ]; then
  echo "  ❌ 缺少 DISCORD_BOT_TOKEN (main)"
  ALL_OK=false
else
  echo "  ✅ DISCORD_BOT_TOKEN (main) 已設定"
fi

if [ -z "${DISCORD_USER_ID}" ]; then
  echo "  ❌ 缺少 DISCORD_USER_ID"
  ALL_OK=false
else
  echo "  ✅ DISCORD_USER_ID 已設定"
fi

if [ -z "${DISCORD_SERVER_ID}" ]; then
  echo "  ❌ 缺少 DISCORD_SERVER_ID"
  ALL_OK=false
else
  echo "  ✅ DISCORD_SERVER_ID 已設定"
fi

# 專家 Agent Token
for i in "${!AGENTS[@]}"; do
  TOKEN_VAR="${TOKEN_VARS[$i]}"
  TOKEN_VALUE="${!TOKEN_VAR}"
  if [ -z "${TOKEN_VALUE}" ]; then
    echo "  ❌ 缺少 ${TOKEN_VAR} (${AGENTS[$i]})"
    ALL_OK=false
  else
    echo "  ✅ ${TOKEN_VAR} (${AGENTS[$i]}) 已設定"
  fi
done

if [ "$ALL_OK" = false ]; then
  echo ""
  echo "❌ 請先在 .env 中填入所有缺少的設定後再執行"
  exit 1
fi

echo ""

# ==========================================
# 第一階段：核心通道與主要帳號配置 (main)
# ==========================================

echo "=========================================="
echo "🌍 第一階段：核心通道與主要帳號配置 (main)"
echo "=========================================="

docker compose run --rm --entrypoint /bin/sh openclaw-cli -c "
  echo '    → 啟用 Discord 通道並設定主帳號 (main)...'
  openclaw config set channels.discord.enabled true --strict-json
  openclaw config set channels.discord.groupPolicy allowlist
  openclaw config set channels.discord.streaming progress

  echo '    → 建立 main 帳號...'
  openclaw config set channels.discord.accounts.main.token --ref-provider default --ref-source env --ref-id DISCORD_BOT_TOKEN
  openclaw config set channels.discord.accounts.main.allowFrom '[\"user:${DISCORD_USER_ID}\"]' --strict-json
  openclaw config set channels.discord.accounts.main.guilds.${DISCORD_SERVER_ID} '{\"requireMention\": true}' --strict-json

  echo '    → 建立路由綁定 (main)...'
  openclaw agents bind --agent main --bind discord:main
"

echo ""
echo "  💤 等待 Gateway 完成重載 (5s)..."
sleep 5

# ==========================================
# 第二階段：自動化配置各類專家 Agent
# ==========================================

if [ ${#AGENTS[@]} -gt 0 ]; then
  echo ""
  echo "=========================================="
  echo "🤖 第二階段：自動化配置各類專家 Agent (Specialized Agents)"
  echo "=========================================="

  for i in "${!AGENTS[@]}"; do
    AGENT="${AGENTS[$i]}"
    AGENT_NAME="${AGENT_NAMES[$i]}"
    TOKEN_VAR="${TOKEN_VARS[$i]}"

    echo "------------------------------------------"
    echo "▶️  正在配置專家：${AGENT} (${AGENT_NAME})"
    echo "------------------------------------------"

    # 執行專家批次配置指令
    docker compose run --rm --entrypoint /bin/sh openclaw-cli -c "
      echo '    → 建立 Agent 工作區...'
      openclaw agents add ${AGENT} 2>/dev/null || true

      echo '    → 設定 Agent 個性 (Identity)...'
      openclaw agents set-identity --name '${AGENT_NAME}' --agent ${AGENT} 2>/dev/null || true

      echo \"    → 註冊 Discord 帳號: ${AGENT} (${TOKEN_VAR})...\"
      openclaw config set channels.discord.accounts.${AGENT}.token --ref-provider default --ref-source env --ref-id ${TOKEN_VAR}

      echo '    → 配置帳號安全性與白名單...'
      openclaw config set channels.discord.accounts.${AGENT}.allowFrom '[\"user:${DISCORD_USER_ID}\"]' --strict-json
      openclaw config set channels.discord.accounts.${AGENT}.guilds.${DISCORD_SERVER_ID} '{\"requireMention\": true, \"users\": [\"${DISCORD_USER_ID}\"]}' --strict-json

      echo '    → 建立路由綁定 (Routing)...'
      openclaw agents bind --agent ${AGENT} --bind discord:${AGENT}
    "

    echo "  💤 等待 Gateway 重載 (2s)..."
    sleep 2

    echo "  ✅ ${AGENT} 配置完成"
    echo ""
  done
fi

# ==========================================
# 完成
# ==========================================
echo "=========================================="
echo "✅ 配置完成！"
echo "=========================================="
echo ""
echo "下一步："
echo "  1. 重啟 Gateway：docker compose restart openclaw-gateway"
echo ""
echo "詳細說明：docs/guides/multi-agent-discord.md"
