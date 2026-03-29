#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# OpenClaw - Disable Sandbox Script
# =========================================================
# 用途：
# - 在已經跑過 setup.sh 的前提下，快速關閉 sandbox
# - 不重跑 onboard / token / CORS 等完整初始化流程
#
# 這支 script 會做：
# 1. 把 OPENCLAW_SANDBOX 寫回 .env
# 2. 用 openclaw-cli 將 sandbox 設定重設為關閉狀態
# 3. 用 base compose 重建 openclaw-gateway（不疊加 sandbox override）
# 4. 重啟 gateway 套用設定
# 5. 驗證 sandbox 是否已關閉
# =========================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
BASE_COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
SANDBOX_COMPOSE_FILE="$ROOT_DIR/docker-compose.sandbox.yml"

fail() {
  echo "❌ ERROR: $*" >&2
  exit 1
}

info() {
  echo "ℹ️  $*"
}

success() {
  echo "✅ $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要指令：$1"
}

upsert_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp)"

  if [[ -f "$file" ]]; then
    awk -v k="$key" -v v="$value" '
      BEGIN { updated=0 }
      $0 ~ "^[[:space:]]*" k "=" {
        print k "=" v
        updated=1
        next
      }
      { print }
      END {
        if (updated==0) print k "=" v
      }
    ' "$file" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi

  mv "$tmp" "$file"
}

require_cmd docker
require_cmd awk

docker compose version >/dev/null 2>&1 || fail "docker compose 不可用"
[[ -f "$BASE_COMPOSE_FILE" ]] || fail "找不到 $BASE_COMPOSE_FILE"
[[ -f "$SANDBOX_COMPOSE_FILE" ]] || fail "找不到 $SANDBOX_COMPOSE_FILE"

info "更新 .env，將 OPENCLAW_SANDBOX 設為 0..."
upsert_env "$ENV_FILE" "OPENCLAW_SANDBOX" "0"
success ".env 已更新"

info "將 OpenClaw sandbox 設定重設為關閉狀態..."
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  run --rm openclaw-cli \
  config set agents.defaults.sandbox.mode off

docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  run --rm openclaw-cli \
  config set agents.defaults.sandbox.scope agent

docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  run --rm openclaw-cli \
  config set agents.defaults.sandbox.workspaceAccess none

success "OpenClaw sandbox 設定已重設為關閉狀態"

info "用 base compose 重建 openclaw-gateway..."
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  up -d --force-recreate openclaw-gateway

success "openclaw-gateway 已重建"

info "重新啟動 openclaw-gateway，套用關閉後設定..."
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  restart openclaw-gateway

success "openclaw-gateway 已重新啟動"

echo
info "驗證 sandbox 設定..."
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  run --rm openclaw-cli \
  config get agents.defaults.sandbox

echo
info "驗證 gateway 容器內是否仍有 docker.sock..."
if docker compose -f "$BASE_COMPOSE_FILE" exec openclaw-gateway ls -l /var/run/docker.sock; then
  echo "⚠️  注意：容器內仍看得到 /var/run/docker.sock，請檢查 docker-compose.yml 是否也有掛載它。"
else
  success "gateway 容器內已無 docker.sock"
fi

echo
success "Sandbox 關閉流程完成"