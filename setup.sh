#!/usr/bin/env bash
# ==============================================================================
# 🎯 OpenClaw Server 全功能初始化 Script
# ==============================================================================
# 移植自官方 docker-setup 腳本的核心邏輯，並適配本專案的單一 Service 架構。
# .env 是唯一的設定真相來源 (Single Source of Truth)。
# 本腳本負責：
#   1. 讀取/產生 Gateway Token（三層優先鏈）
#   2. 將所有設定同步寫入 .env 與 openclaw.json 資料庫
#   3. 處理 Sandbox 沙盒啟用/回滾
# ==============================================================================

set -euo pipefail

# ==============================================================================
# 1. 通用輔助函式
# ==============================================================================

# 輸出錯誤訊息並中斷腳本
fail() {
  echo "❌ ERROR: $*" >&2
  exit 1
}

# 檢查指定指令是否存在（缺少則中斷）
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "缺少必要的系統指令：$1"
  fi
}

# 判斷輸入值是否為「啟用」(支援 1/true/yes/on，不區分大小寫)
# 👉 (對應官方 is_truthy_value)
is_truthy_value() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1 | true | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

# ==============================================================================
# 2. Token 三層優先讀取鏈
# ==============================================================================
# 👉 (對應官方 read_config_gateway_token + read_env_gateway_token)
# 優先順序：
#   1. 環境變數 OPENCLAW_GATEWAY_TOKEN（已 export 進 shell）
#   2. openclaw.json 資料庫中的 gateway.auth.token
#   3. .env 檔案中的 OPENCLAW_GATEWAY_TOKEN=
#   4. 以上都沒有 → openssl/python3 隨機產生

# 從 openclaw.json 資料庫中讀取已儲存的 Token
read_config_gateway_token() {
  local config_path="$OPENCLAW_CONFIG_DIR/openclaw.json"
  if [[ ! -f "$config_path" ]]; then
    return 0
  fi
  # 優先使用 python3 解析 JSON（macOS 內建）
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$config_path" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
except Exception:
    raise SystemExit(0)

gateway = cfg.get("gateway")
if not isinstance(gateway, dict):
    raise SystemExit(0)
auth = gateway.get("auth")
if not isinstance(auth, dict):
    raise SystemExit(0)
token = auth.get("token")
if isinstance(token, str):
    token = token.strip()
    if token:
        print(token)
PY
    return 0
  fi
  # 備案：使用 node 解析
  if command -v node >/dev/null 2>&1; then
    node - "$config_path" <<'NODE'
const fs = require("node:fs");
const configPath = process.argv[2];
try {
  const cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const token = cfg?.gateway?.auth?.token;
  if (typeof token === "string" && token.trim().length > 0) {
    process.stdout.write(token.trim());
  }
} catch {
  // 解析失敗時靜默處理，確保腳本韌性
}
NODE
  fi
}

# 從 .env 檔案中讀取 OPENCLAW_GATEWAY_TOKEN 的值
read_env_gateway_token() {
  local env_path="$1"
  local line=""
  local token=""
  if [[ ! -f "$env_path" ]]; then
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == OPENCLAW_GATEWAY_TOKEN=* ]]; then
      token="${line#OPENCLAW_GATEWAY_TOKEN=}"
    fi
  done <"$env_path"
  if [[ -n "$token" ]]; then
    printf '%s' "$token"
  fi
}

# ==============================================================================
# 3. 智慧環境變數同步函式 (upsert_env)
# ==============================================================================
# 👉 (對應官方 upsert_env)
# 精準覆寫已有欄位、自動補齊缺少欄位，取代土炮的 sed + echo >>
# 相容 Bash 3.2 (macOS 預設)，不使用 declare -A
upsert_env() {
  local file="$1"
  shift
  local -a keys=("$@")
  local tmp
  tmp="$(mktemp)"
  local seen=" "

  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      local key="${line%%=*}"
      local replaced=false
      for k in "${keys[@]}"; do
        if [[ "$key" == "$k" ]]; then
          printf '%s=%s\n' "$k" "${!k-}" >>"$tmp"
          seen="$seen$k "
          replaced=true
          break
        fi
      done
      if [[ "$replaced" == false ]]; then
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <"$file"
  fi

  # 將 .env 中原本不存在的新變數，補寫到檔案末尾
  for k in "${keys[@]}"; do
    if [[ "$seen" != *" $k "* ]]; then
      printf '%s=%s\n' "$k" "${!k-}" >>"$tmp"
    fi
  done

  mv "$tmp" "$file"
}

# ==============================================================================
# 4. 預啟動 CLI 執行器
# ==============================================================================
# 👉 (對應官方 run_prestart_gateway / run_prestart_cli)
# 在伺服器啟動前，透過臨時容器對資料庫執行設定寫入

run_prestart_gateway() {
  docker compose "${COMPOSE_ARGS[@]}" run --rm --no-deps "$@"
}

run_prestart_cli() {
  # 啟動前的設定寫入，不依賴其他容器的網路命名空間
  run_prestart_gateway --entrypoint node openclaw-gateway \
    dist/index.js "$@"
}

# ==============================================================================
# 5. CORS 與 Gateway 同步函式
# ==============================================================================
# 👉 (對應官方 ensure_control_ui_allowed_origins / sync_gateway_mode_and_bind)

ensure_control_ui_allowed_origins() {
  if [[ "${OPENCLAW_GATEWAY_BIND}" == "loopback" ]]; then
    return 0
  fi

  local allowed_origin_json
  local current_allowed_origins
  allowed_origin_json="$(printf '["http://localhost:%s","http://127.0.0.1:%s"]' "$OPENCLAW_GATEWAY_PORT" "$OPENCLAW_GATEWAY_PORT")"
  current_allowed_origins="$(
    run_prestart_cli config get gateway.controlUi.allowedOrigins 2>/dev/null || true
  )"
  current_allowed_origins="${current_allowed_origins//$'\r'/}"

  # 若已有設定，不覆蓋使用者的自訂白名單
  if [[ -n "$current_allowed_origins" && "$current_allowed_origins" != "null" && "$current_allowed_origins" != "[]" ]]; then
    echo "📋 Control UI 白名單已設定，維持現有設定不變。"
    return 0
  fi

  run_prestart_cli config set gateway.controlUi.allowedOrigins "$allowed_origin_json" --strict-json \
    >/dev/null
  echo "✅ 已設定 Control UI 跨域白名單：$allowed_origin_json"
}

sync_gateway_mode_and_bind() {
  run_prestart_cli config set gateway.mode local >/dev/null
  run_prestart_cli config set gateway.bind "$OPENCLAW_GATEWAY_BIND" >/dev/null
  echo "✅ 已鎖定 gateway.mode=local, bind=$OPENCLAW_GATEWAY_BIND"
}

# ==============================================================================
# 🚀 主流程開始
# ==============================================================================

echo "🚀 開始初始化 OpenClaw 伺服器 ..."

# --- 檢查必要工具 ---
require_cmd docker
if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose 不可用 (請嘗試：docker compose version)"
fi

# --- 路徑與變數準備 ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
DOCKER_SOCKET_PATH="${OPENCLAW_DOCKER_SOCKET:-}"

# 自動偵測 Docker Socket 路徑
if [[ -z "$DOCKER_SOCKET_PATH" && "${DOCKER_HOST:-}" == unix://* ]]; then
  DOCKER_SOCKET_PATH="${DOCKER_HOST#unix://}"
fi
if [[ -z "$DOCKER_SOCKET_PATH" ]]; then
  DOCKER_SOCKET_PATH="/var/run/docker.sock"
fi

# 判斷 Sandbox 是否啟用（支援 1/true/yes/on）
RAW_SANDBOX_SETTING="${OPENCLAW_SANDBOX:-}"
if [[ -z "$RAW_SANDBOX_SETTING" && -f "$ENV_FILE" ]]; then
  RAW_SANDBOX_SETTING=$(grep '^OPENCLAW_SANDBOX=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
fi
SANDBOX_ENABLED=""
if is_truthy_value "$RAW_SANDBOX_SETTING"; then
  SANDBOX_ENABLED="1"
fi

# --- 設定核心路徑 ---
export OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
export OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"
export OPENCLAW_SANDBOX="$SANDBOX_ENABLED"
export OPENCLAW_DOCKER_SOCKET="$DOCKER_SOCKET_PATH"

# --- 建立必要的本機資料夾 ---
echo "📁 建立本機資料夾..."
mkdir -p "$OPENCLAW_CONFIG_DIR"
mkdir -p "$OPENCLAW_WORKSPACE_DIR"
# 預先建立子目錄，避免 Docker Desktop 上容器無法 mkdir
mkdir -p "$OPENCLAW_CONFIG_DIR/identity"
mkdir -p "$OPENCLAW_CONFIG_DIR/agents/main/agent"
mkdir -p "$OPENCLAW_CONFIG_DIR/agents/main/sessions"

# --- 偵測 Docker Socket GID (Sandbox 專用) ---
DOCKER_GID=""
if [[ -n "$SANDBOX_ENABLED" && -S "$DOCKER_SOCKET_PATH" ]]; then
  DOCKER_GID="$(stat -c '%g' "$DOCKER_SOCKET_PATH" 2>/dev/null || stat -f '%g' "$DOCKER_SOCKET_PATH" 2>/dev/null || echo "")"
fi
export DOCKER_GID

# ==============================================================================
# 6. Token 三層優先讀取鏈 (核心邏輯)
# ==============================================================================
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  # 第一層：嘗試從資料庫 (openclaw.json) 讀取
  EXISTING_CONFIG_TOKEN="$(read_config_gateway_token || true)"
  if [[ -n "$EXISTING_CONFIG_TOKEN" ]]; then
    OPENCLAW_GATEWAY_TOKEN="$EXISTING_CONFIG_TOKEN"
    echo "🔑 沿用資料庫中的既有 Token（來源：$OPENCLAW_CONFIG_DIR/openclaw.json）"
  else
    # 第二層：嘗試從 .env 讀取
    DOTENV_GATEWAY_TOKEN="$(read_env_gateway_token "$ENV_FILE" || true)"
    if [[ -n "$DOTENV_GATEWAY_TOKEN" ]]; then
      OPENCLAW_GATEWAY_TOKEN="$DOTENV_GATEWAY_TOKEN"
      echo "🔑 沿用 .env 中的既有 Token"
    else
      # 第三層：全部都沒有，現場產生新的
      echo "🔑 偵測到您尚未設定登入 Token，系統正在為您自動產生一組..."
      if command -v openssl >/dev/null 2>&1; then
        OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
      elif command -v python3 >/dev/null 2>&1; then
        OPENCLAW_GATEWAY_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
      else
        fail "無法產生 Token：找不到 openssl 或 python3"
      fi
    fi
  fi
fi
export OPENCLAW_GATEWAY_TOKEN

# ==============================================================================
# 7. 使用 upsert_env 智慧同步 .env 檔案
# ==============================================================================
echo "📝 同步所有設定值至 .env..."
upsert_env "$ENV_FILE" \
  OPENCLAW_GATEWAY_PORT \
  OPENCLAW_GATEWAY_BIND \
  OPENCLAW_GATEWAY_TOKEN \
  OPENCLAW_SANDBOX \
  OPENCLAW_DOCKER_SOCKET \
  OPENCLAW_ALLOW_INSECURE_PRIVATE_WS \
  DOCKER_GID

# ==============================================================================
# 8. 組裝 Docker Compose 啟動參數
# ==============================================================================
COMPOSE_ARGS=("-f" "$ROOT_DIR/docker-compose.yml")
# 保留一份不含 Sandbox 掛載的基礎參數（用於回滾）
BASE_COMPOSE_ARGS=("${COMPOSE_ARGS[@]}")

# ==============================================================================
# 9. 關閉執行中的容器 & 修復權限
# ==============================================================================
echo "📦 關閉執行中的容器..."
docker compose "${COMPOSE_ARGS[@]}" down

echo ""
echo "==> 修復資料夾權限"
# 使用 -xdev 限制 chown 僅在設定目錄內執行，不跨越掛載點
# 避免覆寫使用者的個人專案檔案權限
run_prestart_gateway --user root --entrypoint sh openclaw-gateway -c \
  'find /home/node/.openclaw -xdev -exec chown node:node {} +; \
   [ -d /home/node/.openclaw/workspace/.openclaw ] && chown -R node:node /home/node/.openclaw/workspace/.openclaw || true'

# ==============================================================================
# 10. 系統資料庫初始化 (Onboard) 與設定同步
# ==============================================================================
echo ""
echo "==> 系統初始化 (Onboard)"
echo "  Gateway 綁定模式：$OPENCLAW_GATEWAY_BIND"
echo "  Gateway Token：$OPENCLAW_GATEWAY_TOKEN"
echo ""
run_prestart_cli onboard --mode local --no-install-daemon

echo ""
echo "==> 同步 Gateway 設定至資料庫"
sync_gateway_mode_and_bind

echo ""
echo "==> 設定 Control UI 跨域白名單"
ensure_control_ui_allowed_origins

# ==============================================================================
# 11. 啟動 Gateway 伺服器
# ==============================================================================
echo ""
echo "==> 啟動伺服器"
docker compose "${COMPOSE_ARGS[@]}" up -d

# ==============================================================================
# 12. Sandbox 沙盒完整生命週期 (含失敗回滾)
# ==============================================================================
# 👉 (對應官方 sandbox setup + rollback 邏輯)
SANDBOX_COMPOSE_FILE="$ROOT_DIR/docker-compose.sandbox.yml"

if [[ -n "$SANDBOX_ENABLED" ]]; then
  echo ""
  echo "==> Sandbox 沙盒設定"

  # 防禦性檢查：驗證容器內是否有 Docker CLI
  if ! docker compose "${COMPOSE_ARGS[@]}" run --rm --entrypoint docker openclaw-gateway --version >/dev/null 2>&1; then
    echo "⚠️  WARNING: 容器內找不到 Docker CLI，無法啟用 Sandbox。" >&2
    echo "  請使用包含 Docker CLI 的映像檔，或設定 OPENCLAW_INSTALL_DOCKER_CLI=1 重新編譯。" >&2
    SANDBOX_ENABLED=""
  fi
fi

# 掛載 Docker Socket（僅在通過前置檢查後執行）
if [[ -n "$SANDBOX_ENABLED" ]]; then
  if [[ -S "$DOCKER_SOCKET_PATH" ]]; then
    cat >"$SANDBOX_COMPOSE_FILE" <<YAML
services:
  openclaw-gateway:
    volumes:
      - ${DOCKER_SOCKET_PATH}:/var/run/docker.sock
YAML
    if [[ -n "${DOCKER_GID:-}" ]]; then
      cat >>"$SANDBOX_COMPOSE_FILE" <<YAML
    group_add:
      - "${DOCKER_GID}"
YAML
    fi
    COMPOSE_ARGS+=("-f" "$SANDBOX_COMPOSE_FILE")
    echo "✅ 已掛載 Docker Socket 至沙盒"
  else
    echo "⚠️  WARNING: 啟用了 Sandbox 但找不到 Docker Socket ($DOCKER_SOCKET_PATH)" >&2
    SANDBOX_ENABLED=""
  fi
fi

# 寫入 Sandbox 安全邊界設定
if [[ -n "$SANDBOX_ENABLED" ]]; then
  echo "🛡️ 正在寫入 Sandbox 安全邊界限制..."
  sandbox_config_ok=true

  if ! docker compose "${COMPOSE_ARGS[@]}" run --rm --no-deps --entrypoint node openclaw-gateway \
    dist/index.js config set agents.defaults.sandbox.mode "non-main" >/dev/null; then
    echo "⚠️  WARNING: 無法設定 sandbox.mode" >&2
    sandbox_config_ok=false
  fi
  if ! docker compose "${COMPOSE_ARGS[@]}" run --rm --no-deps --entrypoint node openclaw-gateway \
    dist/index.js config set agents.defaults.sandbox.scope "agent" >/dev/null; then
    echo "⚠️  WARNING: 無法設定 sandbox.scope" >&2
    sandbox_config_ok=false
  fi
  if ! docker compose "${COMPOSE_ARGS[@]}" run --rm --no-deps --entrypoint node openclaw-gateway \
    dist/index.js config set agents.defaults.sandbox.workspaceAccess "none" >/dev/null; then
    echo "⚠️  WARNING: 無法設定 sandbox.workspaceAccess" >&2
    sandbox_config_ok=false
  fi

  if [[ "$sandbox_config_ok" == true ]]; then
    echo "✅ Sandbox 已啟用：mode=non-main, scope=agent, workspaceAccess=none"
    # 重啟以套用 Socket 掛載與設定
    docker compose "${COMPOSE_ARGS[@]}" up -d
  else
    # 🔥 回滾機制：設定失敗時，撤銷 Sandbox 並清理 Socket 掛載
    echo "⚠️  WARNING: Sandbox 設定部分失敗，正在執行安全回滾..." >&2
    docker compose "${BASE_COMPOSE_ARGS[@]}" run --rm --no-deps --entrypoint node openclaw-gateway \
      dist/index.js config set agents.defaults.sandbox.mode "off" >/dev/null || true
    rm -f "$SANDBOX_COMPOSE_FILE"
    # 使用不含 Socket 掛載的基礎參數強制重建容器
    docker compose "${BASE_COMPOSE_ARGS[@]}" up -d --force-recreate
    echo "🔄 已回滾至無沙盒模式。"
  fi
else
  # 未啟用 Sandbox 時，重設殘留的沙盒設定（確保重複執行的冪等性）
  docker compose "${COMPOSE_ARGS[@]}" run --rm --no-deps --entrypoint node openclaw-gateway \
    dist/index.js config set agents.defaults.sandbox.mode "off" >/dev/null 2>&1 || true
  rm -f "$SANDBOX_COMPOSE_FILE"
fi

# ==============================================================================
# 13. 完成提示
# ==============================================================================
echo ""
echo "========================================================"
echo "🎉 伺服器已成功啟動部署！"
echo "🔑 您的專屬登入 Token 為："
echo "   $OPENCLAW_GATEWAY_TOKEN"
echo ""
echo "👉 一般登入網址 (需手動貼上密碼)："
echo "   http://localhost:${OPENCLAW_GATEWAY_PORT}"
echo "========================================================"
echo ""
echo "📱 首次裝置配對 (初次使用必做)："
echo "  1. 開瀏覽器進入上方網址，輸入 Token 登入"
echo "  2. docker compose run --rm openclaw-cli devices list       # 查看待核准裝置"
echo "  3. docker compose run --rm openclaw-cli devices approve <id> # 核准裝置"
echo "  4. docker compose run --rm openclaw-cli dashboard --no-open  # 取得 Dashboard URL"
echo "  ⚠️  步驟 4 的 URL 必須直接點選終端機連結，不能複製貼上！"
echo ""
echo "常用指令："
echo "  docker compose logs -f openclaw-gateway       # 查看即時日誌"
echo "  docker compose down                          # 停止伺服器"
echo "  docker compose up -d openclaw-gateway         # 日常啟動（初始化後不需再跑 setup.sh）"
