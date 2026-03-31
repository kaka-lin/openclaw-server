#!/usr/bin/env bash
# ==============================================================================
# 🎯 OpenClaw Server 全功能初始化 Script
# ==============================================================================
# 移植自官方 docker-setup 腳本的核心邏輯，並適配本專案的單一 Service 架構。
# .env 是唯一的設定真相來源 (Single Source of Truth)。
# 本腳本負責：
#   1. 讀取/產生 Gateway Token（三層優先鏈）
#   2. 將所有設定同步寫入 .env 與 openclaw.json 資料庫
#   3. 支援 Control UI Allowed Origins 採「基礎+追加」模式
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

# 檢查指定指令是否存在
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "缺少必要的系統指令：$1"
  fi
}

# 去掉字串外層單雙引號
strip_wrapping_quotes() {
  local s="${1:-}"

  if [[ ${#s} -ge 2 ]]; then
    if [[ "${s:0:1}" == '"' && "${s: -1}" == '"' ]]; then
      s="${s:1:${#s}-2}"
    elif [[ "${s:0:1}" == "'" && "${s: -1}" == "'" ]]; then
      s="${s:1:${#s}-2}"
    fi
  fi

  printf '%s' "$s"
}

# 判斷輸入值是否為「啟用」(支援 1/true/yes/on)
is_truthy_value() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1 | true | yes | on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ==============================================================================
# 2. 官方 CLI 執行器 (與 official.sh 一致)
# ==============================================================================

# 在容器啟動前，透過臨時容器對資料庫執行設定寫入
run_prestart_gateway() {
  docker compose "${COMPOSE_ARGS[@]}" run --rm --no-deps "$@"
}

run_prestart_cli() {
  # 啟動前的設定寫入，避免與運行中的網路命名空間產生死鎖
  run_prestart_gateway --entrypoint node openclaw-gateway \
    dist/index.js "$@"
}

# 運行中的設定寫入，使用附屬的 cli 服務 (Sidecar 模式)
run_runtime_cli() {
  local compose_scope="${1:-current}"
  local deps_mode="${2:-with-deps}"
  shift 2

  local -a compose_args
  local -a run_args=(run --rm)

  case "$compose_scope" in
    current)
      compose_args=("${COMPOSE_ARGS[@]}")
      ;;
    base)
      compose_args=("${BASE_COMPOSE_ARGS[@]}")
      ;;
    *)
      fail "Unknown runtime CLI compose scope: $compose_scope"
      ;;
  esac

  case "$deps_mode" in
    with-deps)
      ;;
    no-deps)
      run_args+=(--no-deps)
      ;;
    *)
      fail "Unknown runtime CLI deps mode: $deps_mode"
      ;;
  esac

  docker compose "${compose_args[@]}" "${run_args[@]}" openclaw-cli "$@"
}

# ==============================================================================
# 3. Token 處理函式 (與系統資料庫同步)
# ==============================================================================

# 從 openclaw.json 資料庫中讀取已儲存的 Token
read_config_gateway_token() {
  local config_path="$OPENCLAW_CONFIG_DIR/openclaw.json"
  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$config_path" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    token = cfg.get("gateway", {}).get("auth", {}).get("token")
    if token:
        print(token.strip())
except Exception:
    pass
PY
    return 0
  fi
}

# 從 .env 檔案中讀取 Token
read_env_gateway_token() {
  local env_path="$1"
  if [[ ! -f "$env_path" ]]; then
    return 0
  fi
  grep '^OPENCLAW_GATEWAY_TOKEN=' "$env_path" | cut -d= -f2- || true
}

# ==============================================================================
# 4. 智慧環境變數同步函式 (upsert_env)
# ==============================================================================
# 精準覆寫已有欄位、自動補齊缺少欄位
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

  for k in "${keys[@]}"; do
    if [[ "$seen" != *" $k "* ]]; then
      printf '%s=%s\n' "$k" "${!k-}" >>"$tmp"
    fi
  done

  mv "$tmp" "$file"
}

# ==============================================================================
# 5. CORS 設定邏輯 (基礎+追加模式)
# ==============================================================================

ensure_control_ui_allowed_origins() {
  if [[ "${OPENCLAW_GATEWAY_BIND}" == "loopback" ]]; then
    return 0
  fi

  local port="$OPENCLAW_GATEWAY_PORT"
  local raw_user_origins="${OPENCLAW_ALLOWED_ORIGINS:-}"

  # ================================
  # ⭐ 1. 如果包含 "*" → 直接 override
  # ================================
  if [[ "$raw_user_origins" == *"*"* ]]; then
    echo "⚠️ 偵測到 '*'，將使用全開放模式"
    run_prestart_cli config set gateway.controlUi.allowedOrigins '["*"]' --strict-json
    echo "✅ allowedOrigins = ['*']"
    return 0
  fi

  # ================================
  # ⭐ 2. default base（永遠存在）
  # ================================
  local -a final_origins=(
    "http://localhost:$port"
    "http://127.0.0.1:$port"
  )

  local -a user_origins=()
  local item=""

  # ================================
  # ⭐ 3. parse user input
  # ================================
  if [[ -n "${raw_user_origins:-}" ]]; then
    if [[ "$raw_user_origins" == \[* ]]; then
      if command -v python3 >/dev/null 2>&1; then
        IFS=$'\n' read -r -d '' -a user_origins < <(
          python3 -c '
import json, sys
try:
    arr = json.loads(sys.argv[1])
    if isinstance(arr, list):
        for x in arr:
            if x is not None:
                s = str(x).strip()
                if s:
                    print(s)
except Exception:
    pass
' "$raw_user_origins" 2>/dev/null
          printf '\0'
        ) || true
      fi
    else
      IFS=',' read -r -a user_origins <<< "$raw_user_origins" || true
    fi
  fi

  # ================================
  # ⭐ 4. normalize
  # ================================
  if [[ -n "${raw_user_origins:-}" && ${#user_origins[@]} -gt 0 ]]; then
    for item in "${user_origins[@]}"; do
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"

      [[ -z "$item" ]] && continue

      if [[ "$item" != http://* && "$item" != https://* ]]; then
        item="http://${item}"
      fi

      if [[ ! "$item" =~ ^https?://[^/]+:[0-9]+($|/) ]]; then
        item="${item}:$port"
      fi

      final_origins+=("$item")
    done
  fi

  # ================================
  # ⭐ 5. 去重 + JSON
  # ================================
  local allowed_origin_json
  allowed_origin_json=$(
    printf '%s\n' "${final_origins[@]}" | python3 -c '
import json, sys
origins = [line.strip() for line in sys.stdin if line.strip()]
unique = list(dict.fromkeys(origins))
print(json.dumps(unique))
'
  )

  run_prestart_cli config set gateway.controlUi.allowedOrigins "$allowed_origin_json" --strict-json
  echo "✅ 已同步 Control UI 跨域白名單 (基礎+追加)：$allowed_origin_json"
}

# ==============================================================================
# 🚀 主流程開始
# ==============================================================================

echo "🚀 開始初始化 OpenClaw 伺服器 ..."

require_cmd docker
require_cmd python3

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose 不可用 (請嘗試：docker compose version)"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
COMPOSE_ARGS=("-f" "$COMPOSE_FILE")
BASE_COMPOSE_ARGS=("${COMPOSE_ARGS[@]}")

export OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
export OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"

# 從 .env 讀取已有的 OPENCLAW_ALLOWED_ORIGINS
if [[ -z "${OPENCLAW_ALLOWED_ORIGINS:-}" && -f "$ENV_FILE" ]]; then
  OPENCLAW_ALLOWED_ORIGINS="$(grep '^OPENCLAW_ALLOWED_ORIGINS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
fi

OPENCLAW_ALLOWED_ORIGINS="$(strip_wrapping_quotes "${OPENCLAW_ALLOWED_ORIGINS:-}")"
export OPENCLAW_ALLOWED_ORIGINS="${OPENCLAW_ALLOWED_ORIGINS:-}"
echo "🔍 [INFO] OPENCLAW_ALLOWED_ORIGINS='${OPENCLAW_ALLOWED_ORIGINS}'"

# 區網 (非 HTTPS) 存取時需啟用，否則瀏覽器會阻擋 WebSocket 連線
if [[ -z "${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}" ]]; then
  if [[ "$OPENCLAW_GATEWAY_BIND" != "loopback" ]]; then
    OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
  fi
fi
export OPENCLAW_ALLOW_INSECURE_PRIVATE_WS="${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}"

# Sandbox 已停用：setup 僅維持非 sandbox 初始化流程。

echo "📁 建立本機資料夾..."
mkdir -p "$OPENCLAW_CONFIG_DIR" "$OPENCLAW_WORKSPACE_DIR"
mkdir -p "$OPENCLAW_CONFIG_DIR/identity" "$OPENCLAW_CONFIG_DIR/agents/main/agent" "$OPENCLAW_CONFIG_DIR/agents/main/sessions"

# ==============================================================================
# 6. Token 三層優先讀取鏈
# ==============================================================================
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  OPENCLAW_GATEWAY_TOKEN="$(read_config_gateway_token || true)"
  if [[ -z "$OPENCLAW_GATEWAY_TOKEN" ]]; then
    OPENCLAW_GATEWAY_TOKEN="$(read_env_gateway_token "$ENV_FILE" || true)"
  fi
  if [[ -z "$OPENCLAW_GATEWAY_TOKEN" ]]; then
    echo "🔑 正在自動產生登入 Token..."
    OPENCLAW_GATEWAY_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))' 2>/dev/null || openssl rand -hex 32)"
  fi
fi
export OPENCLAW_GATEWAY_TOKEN

# ==============================================================================
# 7. 同步 .env
# ==============================================================================
echo "📝 同步設定至 .env..."
upsert_env "$ENV_FILE" \
  OPENCLAW_CONFIG_DIR \
  OPENCLAW_WORKSPACE_DIR \
  OPENCLAW_GATEWAY_PORT \
  OPENCLAW_GATEWAY_BIND \
  OPENCLAW_GATEWAY_TOKEN \
  OPENCLAW_ALLOWED_ORIGINS \
  OPENCLAW_ALLOW_INSECURE_PRIVATE_WS

# ==============================================================================
# 8. 修正權限與初始化 (Onboard)
# ==============================================================================
echo "📦 關閉並初始化舊容器..."
docker compose "${COMPOSE_ARGS[@]}" down || true

echo "==> 修復資料夾權限"
run_prestart_gateway --user root --entrypoint sh openclaw-gateway -c \
  'find /home/node/.openclaw -xdev -exec chown node:node {} +; \
   [ -d /home/node/.openclaw/workspace/.openclaw ] && chown -R node:node /home/node/.openclaw/workspace/.openclaw || true'

echo "==> 系統初始化 (Onboard)"
run_prestart_cli onboard --mode local --no-install-daemon

echo "==> 同步 Gateway 分類設定"
run_prestart_cli config set gateway.mode local
run_prestart_cli config set gateway.bind "$OPENCLAW_GATEWAY_BIND"
ensure_control_ui_allowed_origins

# ==============================================================================
# 9. 啟動伺服器
# ==============================================================================
echo "🚀 啟動伺服器 (openclaw-gateway)..."
docker compose "${COMPOSE_ARGS[@]}" up -d openclaw-gateway

# ==============================================================================
# 10. 確保 Sandbox 關閉
# ==============================================================================
echo "==> 確保 sandbox 已關閉"
if ! run_runtime_cli current with-deps config set agents.defaults.sandbox.mode "off" >/dev/null; then
  echo "WARNING: Failed to set agents.defaults.sandbox.mode to off" >&2
fi

# ==============================================================================
# 完成提示
# ==============================================================================
echo ""
echo "========================================================"
echo "🎉 伺服器已成功啟動部署！"
echo "🔑 您的專屬登入 Token 為："
echo "   $OPENCLAW_GATEWAY_TOKEN"
echo ""
echo "👉 本機登入網址："
echo "   http://localhost:$OPENCLAW_GATEWAY_PORT"

if [[ -n "${OPENCLAW_ALLOWED_ORIGINS:-}" ]]; then
  IFS=',' read -r -a _o <<< "$OPENCLAW_ALLOWED_ORIGINS" || true
  for o in "${_o[@]}"; do
    if [[ "$o" != *localhost* && "$o" != *127.0.0.1* && -n "$o" && "$o" != \[* && "$o" != "*" ]]; then
      [[ "$o" != http://* && "$o" != https://* ]] && o="http://$o"
      [[ ! "$o" =~ ^https?://[^/]+:[0-9]+($|/) ]] && o="$o:$OPENCLAW_GATEWAY_PORT"
      echo ""
      echo "👉 區網登入網址："
      echo "   $o"
      break
    fi
  done
fi

echo ""
echo "📱 首次裝置配對 (初次使用必做)："
echo "  1. 開瀏覽器進入上方網址，輸入 Token 登入"
echo "  2. docker compose run --rm openclaw-cli devices list         # 查看待核准裝置"
echo "  3. docker compose run --rm openclaw-cli devices approve <id> # 核准裝置"
echo "  4. docker compose run --rm openclaw-cli dashboard --no-open  # 取得 Dashboard URL"
echo ""
echo "常用指令："
echo "  docker compose logs -f openclaw-gateway        # 查看即時日誌"
echo "  docker compose down                            # 停止伺服器"
echo "  docker compose up -d openclaw-gateway          # 日常啟動（初始化後不需再跑 setup.sh）"
echo "========================================================"