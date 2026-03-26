# OpenClaw Server 部署全攻略：setup.sh 運作機制與環境配置詳解

我們專案提供的 `setup.sh` 腳本參考了官方 `docker-setup` 的核心邏輯，並針對 `openclaw-gateway` 與 `openclaw-cli` 雙服務架構進行了優化。如果直接跑 `docker-compose up` 而跳過這個腳本，通常會遇到 Token 衝突、權限異常、CORS 封鎖等讓人頭痛的問題。

> [!NOTE]
> 腳本執行完畢後，只會保留 `openclaw-gateway` 在背景持續運行；`openclaw-cli` 僅在初始化過程中以臨時容器方式啟動，執行完設定任務後就會自動銷毀 (`--rm`)。

## 1. Token 三層讀取優先順序

腳本遵循與官方一致的 Token 讀取優先順序，避免「資料庫內的舊密碼」與「.env 的新密碼」不同步而造成 `token_mismatch` 的困擾。

**讀取順序（從高到低）：**

1. **環境變數** `OPENCLAW_GATEWAY_TOKEN`（已 export 到 shell 中）
2. **資料庫** `~/.openclaw/openclaw.json` 中的 `gateway.auth.token`（透過 `read_config_gateway_token()` 取得）
3. **`.env` 檔案**中的 `OPENCLAW_GATEWAY_TOKEN=`（透過 `read_env_gateway_token()` 讀取）
4. **以上都沒有**：系統會自動透過 `openssl rand -hex 32` 產生一組新的 Token

## 2. 自動化環境變數同步 (upsert_env)

使用 `upsert_env()` 函式來管理 `.env` 檔案，這比傳統的 `sed` 或 `echo >>` 做法更安全且穩定：

- **現有欄位**：精準修改 `=` 後面的數值，且不會破壞原本的排版。
- **缺失欄位**：自動補充在檔案最後面。
- **相容性**：支援 Bash 3.2 (macOS 預設版本)，不依賴 `declare -A` 等較新的語法。

## 3. 資料持久化與權限自動修復

- **遇到的問題**：Docker 掛載本機資料夾時，檔案權限通常會被系統使用者綁定，導致容器內的 `node` 程式無法寫入資料。
- **解決方案**：

    ```bash
    find /home/node/.openclaw -xdev -exec chown node:node {} +
    ```

    這裡使用了 `-xdev` 參數來限制權限修復範圍，**不會跨越不同的掛載點**，確保不會誤動到您 `workspace` 裡的個人專案檔案。

## 4. CORS 跨來源資源共用 (Smart Origins)

- **遇到的問題**：前端 UI 與後端 API 之間的連線被瀏覽器阻擋（CORS 限制）。
- **解決方案**：腳本透過 `ensure_control_ui_allowed_origins()` 函式動態設定白名單。
- **手動設定方式**：您也可以直接在 `.env` 中設定 `OPENCLAW_ALLOWED_ORIGINS`。
    - 範例：`OPENCLAW_ALLOWED_ORIGINS=192.168.1.100,http://mac-mini.local:18789`
    - 全開放（測試用）：`OPENCLAW_ALLOWED_ORIGINS=["*"]`
- **建議**：請優先使用 `localhost` 而非 `127.0.0.1` 存取。

## 5. WebSocket 安全與區網存取

- **遇到的問題**：在非安全環境 (Non-Secure Context) 下，瀏覽器會限制加密通訊機制。
- **設定項**：`OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1`
- **用途**：如果您是透過區網 IP (如 `http://192.168.x.x:18789`) 存取，必須開啟此選項，否則 Control UI 將無法連線。

## 6. Sandbox 沙盒生命週期管理（含失敗還原機制）

- **前置檢查**：啟動前會先確認容器內是否有 Docker CLI。
- **Socket 掛載**：確認環境支援後，才會動態產出 `docker-compose.sandbox.yml`。
- **失敗還原**：如果 Sandbox 設定流程失敗，腳本會自動將環境還原至初始狀態，確保存取正常。

## 7. 常見問題排除 (Troubleshooting)

### 出現 "control ui requires device identity" 錯誤？

這是因為瀏覽器規定必須在「安全環境 (Secure Context)」下才能產生裝置資訊。

**解決方案**：

1. 優先使用 `http://localhost:18789` 存取。
2. 若必須透過區網 IP 存取，請確保 `.env` 中的 `OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1` 已開啟。

### 出現 "origin not allowed" 錯誤？

這是被原本的 CORS 安全機制擋住了。

**解決方案**：

1. 確認 `.env` 中的 `OPENCLAW_ALLOWED_ORIGINS` 是否有包含您目前的存取網址。
2. 或直接用 CLI 強制開放：`docker compose run --rm openclaw-cli config set gateway.controlUi.allowedOrigins '["*"]' --json`
