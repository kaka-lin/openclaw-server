#!/usr/bin/env bash

# 出錯就停止
# -e: 任一指令失敗就退出
# -u: 使用到未定義變數就退出
# -o pipefail: pipeline 中任何一段失敗都算失敗
set -euo pipefail

# =========================================================
# OpenClaw - Enable Sandbox Script
# =========================================================
# 用途：
# - 在已經跑過 setup.sh 的前提下，快速開啟 sandbox
# - 不重跑 onboard / token / CORS 等完整初始化流程
#
# 前提：
# - docker-compose.sandbox.yml 固定存在於 repo 中
#
# 這支 script 會做以下事情：
# 1. 找出 Docker socket 在哪裡
# 2. 查出 docker.sock 的群組 ID（DOCKER_GID）
# 3. 把 OPENCLAW_SANDBOX / OPENCLAW_DOCKER_SOCKET / DOCKER_GID 寫進 .env
# 4. 使用 repo 內固定存在的 docker-compose.sandbox.yml 重建 openclaw-gateway
# 5. 用 openclaw-cli 寫入 OpenClaw sandbox 設定
#    - mode=non-main
#    - scope=agent
#    - workspaceAccess=none
# 6. 重啟 gateway 套用設定
# 7. 驗證 sandbox 是否成功啟用
# =========================================================


# =========================================================
# 1. 路徑設定
# =========================================================

# 取得這支 script 所在的資料夾
# 例如如果 script 在 /app/enable_sandbox.sh
# 那 ROOT_DIR 就會是 /app
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# .env 檔位置
ENV_FILE="$ROOT_DIR/.env"

# 基本 compose 檔
BASE_COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

# sandbox override compose 檔
SANDBOX_COMPOSE_FILE="$ROOT_DIR/docker-compose.sandbox.yml"


# =========================================================
# 2. 小工具函式：輸出訊息 / 中止
# =========================================================

# 顯示錯誤並結束
fail() {
  echo "❌ ERROR: $*" >&2
  exit 1
}

# 一般資訊訊息
info() {
  echo "ℹ️  $*"
}

# 成功訊息
success() {
  echo "✅ $*"
}


# =========================================================
# 3. 小工具函式：確認某個指令存在
# =========================================================

# 用法：require_cmd docker
# 如果系統找不到這個指令，就直接報錯退出
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要指令：$1"
}


# =========================================================
# 4. 小工具函式：更新 .env 裡的某個 key
# =========================================================
#
# 作用：
# - 如果 key 已存在：覆蓋舊值
# - 如果 key 不存在：新增一行
#
# 例如：
# upsert_env .env OPENCLAW_SANDBOX 1
#
# 最後 .env 裡會有：
# OPENCLAW_SANDBOX=1
# =========================================================
upsert_env() {
  local file="$1"    # .env 檔案路徑
  local key="$2"     # 要更新的 key
  local value="$3"   # 要寫入的值
  local tmp          # 暫存檔

  # 建一個暫存檔，先把修改後內容寫進去
  tmp="$(mktemp)"

  if [[ -f "$file" ]]; then
    # 如果 .env 已存在，就逐行處理：
    # - 找到 key=... 這行就改成新值
    # - 沒找到就保留原樣
    # - 最後如果整份檔都沒這個 key，就補一行
    awk -v k="$key" -v v="$value" '
      BEGIN { updated=0 }

      # 如果這一行是 key=...
      $0 ~ "^[[:space:]]*" k "=" {
        print k "=" v
        updated=1
        next
      }

      # 其他行原樣保留
      { print }

      # 如果整份檔都沒找到，就在最後新增
      END {
        if (updated==0) print k "=" v
      }
    ' "$file" > "$tmp"
  else
    # 如果 .env 不存在，就直接建立新檔
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi

  # 用新檔覆蓋舊檔
  mv "$tmp" "$file"
}


# =========================================================
# 5. 小工具函式：從 .env 讀某個值
# =========================================================
#
# 例如：
# read_env_value .env OPENCLAW_DOCKER_SOCKET
#
# 會回傳像：
# /var/run/docker.sock
# =========================================================
read_env_value() {
  local file="$1"
  local key="$2"

  # 檔案不存在就直接返回空值
  [[ -f "$file" ]] || return 0

  # 抓出最後一個符合 key=... 的值
  grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- || true
}


# =========================================================
# 6. 偵測 Docker socket 路徑
# =========================================================
#
# 這段會依序嘗試：
#
# 1. 看環境變數 OPENCLAW_DOCKER_SOCKET 有沒有設
# 2. 看 .env 裡有沒有 OPENCLAW_DOCKER_SOCKET
# 3. 看 DOCKER_HOST 是否是 unix://...
# 4. 最後嘗試 /var/run/docker.sock
#
# 找到後回傳路徑
# 找不到就報錯
# =========================================================
detect_docker_socket() {
  local sock="${OPENCLAW_DOCKER_SOCKET:-}"

  # 先看目前 shell 環境變數有沒有設，且該路徑真的是 socket
  if [[ -n "$sock" && -S "$sock" ]]; then
    printf '%s' "$sock"
    return 0
  fi

  # 再看 .env 裡有沒有定義
  if [[ -f "$ENV_FILE" ]]; then
    sock="$(read_env_value "$ENV_FILE" "OPENCLAW_DOCKER_SOCKET")"
    if [[ -n "$sock" && -S "$sock" ]]; then
      printf '%s' "$sock"
      return 0
    fi
  fi

  # 如果 DOCKER_HOST 是 unix://... 就從那裡取路徑
  if [[ -n "${DOCKER_HOST:-}" && "${DOCKER_HOST}" == unix://* ]]; then
    sock="${DOCKER_HOST#unix://}"
    if [[ -S "$sock" ]]; then
      printf '%s' "$sock"
      return 0
    fi
  fi

  # 最常見的預設位置
  if [[ -S /var/run/docker.sock ]]; then
    printf '%s' "/var/run/docker.sock"
    return 0
  fi

  # 全部都找不到就報錯
  fail "找不到 Docker socket。請確認 Docker Desktop / Docker daemon 已啟動。"
}


# =========================================================
# 7. 查詢 docker.sock 的 GID
# =========================================================
#
# Docker socket 是個檔案，這裡要取它的 group id。
#
# Linux 常用：
#   stat -c '%g'
#
# macOS 常用：
#   stat -f '%g'
#
# 這裡兩種都試，哪個能用就用哪個。
# =========================================================
detect_docker_gid() {
  local sock="$1"   # 例如 /var/run/docker.sock
  local gid=""

  # Linux 寫法
  gid="$(stat -c '%g' "$sock" 2>/dev/null || true)"

  # 如果 Linux 寫法失敗，再試 macOS 寫法
  if [[ -z "$gid" ]]; then
    gid="$(stat -f '%g' "$sock" 2>/dev/null || true)"
  fi

  # 如果還是拿不到，就報錯
  [[ -n "$gid" ]] || fail "無法取得 docker.sock 的 GID：$sock"

  # 回傳 gid
  printf '%s' "$gid"
}


# =========================================================
# 8. 前置檢查
# =========================================================

# 確認必要指令存在
require_cmd docker
require_cmd awk
require_cmd grep
require_cmd cut
require_cmd stat

# 確認 docker compose 可用
docker compose version >/dev/null 2>&1 || fail "docker compose 不可用"

# 確認 compose 檔存在
[[ -f "$BASE_COMPOSE_FILE" ]] || fail "找不到 $BASE_COMPOSE_FILE"
[[ -f "$SANDBOX_COMPOSE_FILE" ]] || fail "找不到 $SANDBOX_COMPOSE_FILE"


# =========================================================
# 9. 偵測 Docker socket 與 GID
# =========================================================

info "偵測 Docker socket..."
DOCKER_SOCKET_PATH="$(detect_docker_socket)"
success "Docker socket: $DOCKER_SOCKET_PATH"

info "查詢 docker.sock GID..."
DOCKER_GID_VALUE="$(detect_docker_gid "$DOCKER_SOCKET_PATH")"
success "DOCKER_GID: $DOCKER_GID_VALUE"


# =========================================================
# 10. 更新 .env
# =========================================================
#
# 這裡會把三個值寫進 .env：
# - OPENCLAW_SANDBOX=1
# - OPENCLAW_DOCKER_SOCKET=偵測到的 socket 路徑
# - DOCKER_GID=偵測到的群組 id
# =========================================================
info "更新 .env..."
upsert_env "$ENV_FILE" "OPENCLAW_SANDBOX" "1"
upsert_env "$ENV_FILE" "OPENCLAW_DOCKER_SOCKET" "$DOCKER_SOCKET_PATH"
upsert_env "$ENV_FILE" "DOCKER_GID" "$DOCKER_GID_VALUE"
success ".env 已更新"


# =========================================================
# 11. 用 sandbox override 重建 gateway
# =========================================================
#
# 這一步很重要：
# 單用 docker-compose.yml 不會掛 docker.sock
#
# 加上 docker-compose.sandbox.yml 之後：
# - gateway 容器裡才會有 /var/run/docker.sock
# - 才有能力操作 host Docker
# =========================================================
info "使用 sandbox override 重建 openclaw-gateway..."
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  up -d --force-recreate openclaw-gateway

success "openclaw-gateway 已重建"


# =========================================================
# 12. 寫入 OpenClaw 內部 sandbox 設定
# =========================================================
#
# 注意：
# 就算 gateway 容器已經掛到 docker.sock，
# OpenClaw 內部設定如果還是 off，也不算真的啟用 sandbox。
#
# 所以還要另外寫這三個設定：
#
# 1. mode = non-main
#    表示啟用 sandbox
#
# 2. scope = agent
#    表示 sandbox 作用範圍是 agent
#
# 3. workspaceAccess = none
#    表示不直接開放 workspace 存取
# =========================================================
info "寫入 OpenClaw sandbox 設定..."

docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  run --rm openclaw-cli \
  config set agents.defaults.sandbox.mode non-main

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

success "OpenClaw sandbox 設定已寫入"

# OpenClaw 要 restart gateway 才會套用
info "重新啟動 openclaw-gateway，讓 sandbox 設定生效..."
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  restart openclaw-gateway

success "openclaw-gateway 已重新啟動"


# =========================================================
# 13. 驗證
# =========================================================

echo
info "驗證 sandbox 設定..."

# 查詢 OpenClaw 目前記錄的 sandbox 設定
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  run --rm openclaw-cli \
  config get agents.defaults.sandbox

echo
info "驗證 gateway 容器是否看得到 docker.sock..."

# 看容器裡是否真的存在 /var/run/docker.sock
docker compose \
  -f "$BASE_COMPOSE_FILE" \
  -f "$SANDBOX_COMPOSE_FILE" \
  exec openclaw-gateway \
  ls -l /var/run/docker.sock


# =========================================================
# 14. 完成提示
# =========================================================
echo
success "Sandbox 啟用流程完成"
echo "你現在可以用下面指令再次確認："
echo
echo "docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config get agents.defaults.sandbox"
echo "docker compose -f docker-compose.yml -f docker-compose.sandbox.yml exec openclaw-gateway ls -l /var/run/docker.sock"