# OpenClaw Server 部署 Script 說明

我們專案提供的 `setup.sh` 腳本參考了官方 `docker-setup` 的核心邏輯，並針對 `openclaw-gateway` 與 `openclaw-cli` 雙服務架構進行了調整。如果直接跑 `docker compose up` 而跳過這個腳本，常見會遇到 Token 不同步、資料夾權限異常、Control UI 跨來源限制等問題。

> [!NOTE]
> 腳本執行完畢後，只會保留 `openclaw-gateway` 在背景持續運行；`openclaw-cli` 僅在初始化過程中以臨時容器方式啟動，執行完設定任務後就會自動銷毀（`--rm`）。

## 1. Token 三層讀取優先順序

腳本遵循與官方相近的 Token 讀取優先順序，避免資料庫中的舊 Token 與 `.env` 內的新 Token 不一致而造成連線或登入問題。

**讀取順序（由高到低）：**

1. **環境變數** `OPENCLAW_GATEWAY_TOKEN`（已 export 到 shell 中）
2. **資料檔** `~/.openclaw/openclaw.json` 中的 `gateway.auth.token`
3. **`.env` 檔案**中的 `OPENCLAW_GATEWAY_TOKEN=`
4. **以上都沒有**：系統自動產生新的 Token

## 2. 自動化環境變數同步（`upsert_env`）

使用 `upsert_env()` 函式管理 `.env` 檔案，比直接用 `sed` 或 `echo >>` 更穩定：

- **現有欄位**：精準更新 `=` 後面的值，不破壞整體格式
- **缺失欄位**：自動補在檔案最後
- **相容性**：支援 Bash 3.2（macOS 預設版本），不依賴較新的語法特性

## 3. 資料持久化與權限自動修復

### 問題背景

Docker 在 Linux 主機上掛載資料夾時，常會碰到宿主機 UID/GID 與容器內使用者不一致，導致 `node` 使用者無法寫入 `.openclaw` 相關資料。這在 macOS / Windows 的 Docker Desktop 比較不明顯，但在 Linux 伺服器部署時很常見。

### 解決方式

腳本會在初始化階段暫時以 `root` 身份進入容器，將掛載進來的 OpenClaw 資料夾擁有者修正為容器內的 `node` 使用者。

> [!NOTE]
> 關於 OpenClaw 如何透過 Docker 實現安全隔離的技術細節，請參閱 [Sandbox 隔離架構原理 (LLM-notes)](/Users/kaka/Projects/kaka/LLM-notes/OpenClaw/sandbox-architecture.md)。

```bash
run_prestart_gateway --user root --entrypoint sh openclaw-gateway -c   'find /home/node/.openclaw -xdev -exec chown node:node {} +'
```

### 為什麼使用 `-xdev`

`-xdev` 可避免 `find` 跨越到其他掛載點，只會在目標掛載資料夾內調整權限，降低誤操作範圍。

## 4. CORS 跨來源資源共用（Smart Origins）

### 問題背景

當 Control UI 與 Gateway 間的來源不在允許清單內時，瀏覽器會因 CORS 限制封鎖連線。

### 解決方式

腳本透過 `ensure_control_ui_allowed_origins()` 採用 **基礎（Base）+ 追加（Additional）** 模式設定白名單。

### 運作邏輯

1. **基礎名單**：自動包含
   - `http://localhost:$PORT`
   - `http://127.0.0.1:$PORT`

2. **追加名單**：讀取 `.env` 中的 `OPENCLAW_ALLOWED_ORIGINS`
   - 支援逗號分隔
   - 支援 JSON 陣列格式

3. **自動補齊**：
   - 自動補 `http://`
   - 自動補預設 port

### 全開放模式

如果設定：

```env
OPENCLAW_ALLOWED_ORIGINS=["*"]
```

腳本會將 Control UI 白名單設為全開放。

### 建議

本機存取時，優先使用 `localhost` 或 `127.0.0.1`。  
若改用 LAN 位址，需額外注意 device auth、allowed origins 與 WebSocket 安全設定。

## 5. WebSocket 安全與區網存取

### 問題背景

當 Gateway 不是只綁定在 loopback，而是提供區網存取時，瀏覽器在非 HTTPS 環境下可能對裝置識別或 WebSocket 行為有額外限制。

### 設定項

```env
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
```

### 腳本行為

當 `OPENCLAW_GATEWAY_BIND` 不是 `loopback` 時，腳本會自動將其開啟，讓你以 LAN IP 存取 Control UI 時仍可建立連線。

### 補充說明

這屬於**安全性降級設定**。  
正式環境仍應優先考慮：

- `localhost`
- HTTPS 反向代理
- Tailscale / 其他安全網路邊界

## 6. Sandbox 踩坑紀錄（目前狀態：停用）

我們目前專案**先停用 sandbox**，不是因為 OpenClaw 不支援，而是因為在目前這套 **Docker Gateway + host browser / node host** 的部署方式下，sandbox 會顯著增加設定與排錯成本。

OpenClaw 官方將 sandbox 視為**可選的安全邊界**；在工具不進 sandbox 時，程式會直接在主機上執行。在本專案現階段，我們的優先目標是先把 **UI / Channel → Browser** 的基本控制鏈路跑通，再回頭逐步恢復 sandbox。

> [!TIP]
> 關於 OpenClaw 為何採用 DooD (Docker-out-of-Docker) 模式以及其安全邊界設計，請參閱 [Sandbox 隔離架構原理筆記 (LLM-notes)](/Users/kaka/Projects/kaka/LLM-notes/OpenClaw/sandbox-architecture.md)。

### 我們實際遇到的典型問題

#### 案例 A：Docker runtime 可用性不完整

在我們的部署實測中，若 sandbox 依賴 Docker runtime，但執行環境內缺乏可用的 `docker` 指令或對應執行能力，agent 可能無法建立所需的 sandbox / container runtime。

**常見報錯：**

```text
Sandbox mode requires Docker, but the "docker" command was not found in PATH.
```

#### 案例 B：Docker Desktop（macOS）共享路徑限制

這主要是 **Docker Desktop on macOS** 的限制，不是 OpenClaw sandbox 本身獨有的規則。  
當 sandbox 嘗試掛載的 host path 不在 Docker Desktop 的共享白名單內，掛載會被拒絕。

**常見報錯：**

```text
The path ... is not shared from the host and is not known to Docker.
```

#### 案例 C：隔離網路帶來的 DNS / 主機可見性問題
Sandbox / browser runtime 會引入額外的獨立 network、DNS 與 browser / CDP 邊界設定；若設定不當，可能出現：

- 無法解析外部網域
- 無法存取宿主機服務
- browser control 無法建立

**常見報錯：**

```text
Could not resolve host: www.threads.net
```

或：

```text
ENETUNREACH
```

#### 案例 D：受限 runtime 下的 socket / port bind 問題

在某些受限 sandbox / runtime 設定下，啟動需要額外 socket、port bind 或 local service 的工具可能因權限或隔離限制而失敗。

**常見報錯：**

```text
Failed to bind socket: Operation not permitted (os error 1)
```

### 我們目前的結論

基於目前專案的首要目標是先驗證 **UI / Telegram → Browser** 的基本控制鏈路，我們暫時停用 sandbox。等主流程穩定後，再視安全需求逐步恢復 sandbox。

換句話說，目前採取的是：

- **優先跑通基本瀏覽器控制**
- **避免把使用者拖進 Docker / sandbox / network / host path 權限的複合排錯流程**
- **等功能穩定後，再逐步加回安全邊界**

## 7. CLI 執行模式：Prestart 與 Runtime

為避免資料庫存取衝突與初始化時序問題，腳本區分了兩種 CLI 執行模式：

### Prestart 模式（`run_prestart_cli`）

在 Gateway 正式啟動前，透過臨時容器直接操作底層 CLI，適合：

- 初始化設定
- 寫入 onboarding 結果
- 預先設定 CORS / gateway mode / bind

### Runtime 模式（`run_runtime_cli`）

在 Gateway 已經運行後，透過 `openclaw-cli` sidecar 方式執行 CLI 指令，適合：

- runtime config 調整
- device approve
- node / channel / browser 相關狀態查詢

## 8. 常見問題排除（Troubleshooting）

### 1. 出現 `control ui requires device identity`？

這通常與瀏覽器安全上下文、非 HTTPS 存取、或裝置識別流程有關。

**建議處理方式：**

1. 優先使用：

   ```text
   http://localhost:18789
   ```

2. 若必須使用 LAN IP 存取，確認：

   - `OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1`
   - `OPENCLAW_ALLOWED_ORIGINS` 已包含目前來源

### 2. 出現 `origin not allowed`？

代表目前的 Control UI 來源不在 Gateway 的允許清單內。

**處理方式：**

1. 檢查 `.env` 內的 `OPENCLAW_ALLOWED_ORIGINS`
2. 或用 CLI 臨時放寬：

```bash
docker compose run --rm openclaw-cli config set gateway.controlUi.allowedOrigins '["*"]' --json
```

### 3. 出現 Node / Browser 已連上，但 UI / Telegram 還是只會用 web_fetch？

這通常不是 browser runtime 壞掉，而是**聊天 agent 的工具集沒包含 Browser**。

請先確認：

```text
/tools verbose
```

如果沒有看到：

- `Profile: full`
- `Browser`

則需要把工具集切成 full，例如：

```bash
docker compose -f docker-compose.yml run --rm openclaw-cli config set tools.profile full
docker compose -f docker-compose.yml restart openclaw-gateway
```

## 9. 我們目前推薦的實務部署方式

針對本專案目前的需求，我們推薦：

- **Gateway 跑在 Docker**
- **Node host 跑在宿主機**
- **Chrome 跑在宿主機**
- **UI / Channel (Ex: Telegram) 經由 Gateway 與 Node 控制宿主機瀏覽器**
- **Sandbox 暫時停用**

這條路徑的好處是：

- 先把基本 browser control 跑通
- 減少 container 內 existing-session attach 問題
- 保留後續逐步加回 sandbox 的空間

## 10. 總結

`setup.sh` 的核心價值不只是「幫你把 container 跑起來」，而是：

- 幫你處理 Token 同步
- 修正掛載資料夾權限
- 建立合理的 CORS 設定
- 降低首次部署時的環境差異
- 在目前專案策略下，刻意避開 sandbox 帶來的額外複雜度

因此，在本專案中，**建議把 `setup.sh` 視為正式的部署入口，而不是可有可無的便利腳本。**

## 11. 進階原理與研究 (Architecture & Theory)

對於想要深入了解 OpenClaw 核心設計（如 DooD 沙盒、工具系統、API 規範等）的使用者，請參閱個人筆記庫：

- [OpenClaw 核心原理與架構筆記 (LLM-notes)](/Users/kaka/Projects/kaka/LLM-notes/OpenClaw/README.md)
- [OpenClaw 內建工具全集整理 (LLM-notes)](/Users/kaka/Projects/kaka/LLM-notes/OpenClaw/openclaw-tools-guide.md)
