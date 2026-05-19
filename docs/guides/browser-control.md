# OpenClaw 瀏覽器控制：Docker Gateway + Mac Host Chrome 完整設定指南

本指南整合了 OpenClaw 在 Docker 環境下執行 Gateway，並透過 Mac Host 上的 Node 控制本機 Chrome 的完整安裝、設定與排障流程。

## 1. 目標與架構

### 1.1 目標

讓 **OpenClaw 的 Control UI 或任何已連線的 Channel (如 Telegram, Discord, Slack 等)** 可以透過自然語言，直接控制 **Mac 上已開啟且已登入的 Chrome**，並保持登入狀態（如 Threads, Instagram 等）。

### 1.2 架構圖

- **OpenClaw Gateway**：執行於 Docker 容器 (`openclaw-gateway`)。
- **OpenClaw CLI (管理)**：執行於 Docker 容器 (`openclaw-cli`)，用於修改 Gateway 設定。
- **OpenClaw Node Host**：執行於 **Mac 主機**，作為各 profile 的 Chrome supervisor／父程序（按需啟動並維護 Chrome 子程序）。
- **Chrome 瀏覽器**：執行於 **Mac 主機**，每個 profile 使用獨立的 user-data-dir（位於 `~/.openclaw/browser/<profile>/user-data/`），登入狀態各自保存。第一次啟動時是空白 Chrome，需在該 profile 內手動登入 Threads / IG 等服務後，狀態才會保留。
- **控制流**：Control UI / Channels -> Gateway -> Mac Node -> Mac Chrome。

> [!TIP]
> 如果你也在用 Hermes Agent，想知道 Hermes 怎麼連到同一批 OpenClaw 啟動的 Chrome（`cdp_proxy.py` 的角色、Node 在資料路徑上嗎、lazy-load 對 Hermes 的影響等），請參閱 hermes-server 的 [瀏覽器接線架構](https://github.com/kaka-lin/hermes-server/blob/main/docs/guides/mac-chrome-cdp-guide.md)。

## 2. 完整安裝與設定步驟

### 2.1 啟動 OpenClaw Gateway (Docker)

在 OpenClaw 專案目錄下執行：

```bash
bash setup.sh
```

確認可開啟管理介面：`http://127.0.0.1:18789`。

### 2.2 在 Mac Host 安裝 OpenClaw CLI

Node 必須跑在 Mac 主機上才能控制本機 Chrome。執行安裝指令（跳過 onboard 流程）：

```bash
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
```

確認安裝成功：`openclaw --version`。

### 2.3 切換工具集為 Full (Docker 端)

這是最關鍵的一步。預設的 `coding` profile 不包含 `Browser` 工具。

```bash
docker compose run --rm openclaw-cli config set tools.profile full
docker compose restart openclaw-gateway
```

### 2.4 設定 Browser 路由與預設 Profile (Docker 端)

指示 Gateway 將瀏覽器請求路由到名為 "Mac Mini Node" 的節點，並避免使用 Container 內的 Chrome。

```bash
docker compose run --rm openclaw-cli config set gateway.nodes.browser.mode auto
docker compose run --rm openclaw-cli config set gateway.nodes.browser.node "Mac Mini Node"
docker compose run --rm openclaw-cli config set browser.defaultProfile openclaw
docker compose restart openclaw-gateway
```

> [!TIP]
>
> - `openclaw` 不是寫死的唯一選擇，你完全可以根據需求自行將預設 Profile 取名並設定為你喜歡的名字。
> - 如果沒有特別在設定檔寫死目標 Port，本地 Profile 預設通常會從 `18800` 開始自動分配。
> - 若需要建立 **多環境/多帳號切換（Multi-Profile）** 或固定 Port 綁定，請進一步參考：[Browser Profiles 設定與 Multi-Profile 指南](./browser-profiles-config.md)。

### 2.5 啟動 Mac Host Node 並批准連線

#### 2.5.1. 啟動 Mac Host Node

在 Mac Terminal 手動執行以下指令（請替換為你的 Gateway Token）：

```bash
export OPENCLAW_GATEWAY_TOKEN="<你的 gateway token>"
openclaw node run --host 127.0.0.1 --port 18789 --display-name "Mac Mini Node"
```

> [!IMPORTANT]
> 此終端機視窗必須保持執行狀態，不可關閉。
> 若 Docker Gateway 重啟，強烈建議也中斷此 Node 程序再重新啟動，以避免產生舊裝置無法正常配對的情況。

#### 2.5.2. 批准裝置連線 (Docker 端)

Node 啟動後會向 Gateway 發起配對請求，在 Docker CLI 中核准連線才能正式使用：

```bash
# 列出待配對裝置，找到對應的 pairing code
docker compose run --rm openclaw-cli devices list

# 批准指定裝置（替換為 list 輸出中對應的 pairing code）
docker compose run --rm openclaw-cli devices approve <pairing-code>
```

### 2.6 準備 Mac Chrome

1. 確保 **OpenClaw 啟動的 Chrome 視窗保持開啟**（不要手動關閉那些彈出來的視窗，關掉 CDP port 就會掉）。
2. 每個 profile 的 Chrome 至少保留一個分頁。
3. 如果跳出「允許遠端連線 / Attach」的系統提示，請務必點擊 **允許**。
4. 前往 [chrome://inspect/#remote-debugging](chrome://inspect/#remote-debugging) 確保已允許 Remote Debugging（如有此選項）。

## 3. 驗證設定是否成功

> [!IMPORTANT]
> OpenClaw 是 **lazy-load** 設計：`openclaw node run` 啟動時不會自動啟動任何 profile 的 Chrome（**連預設 profile 也不會**）。`Browser control service ready (profiles=N)` 只代表 Node 起來了，但 Chrome 還沒被 spawn。Chrome 只在你下指令使用某個 profile 時才會啟動，OpenClaw log 才會印出 `openclaw browser started`。所以下方驗證若看不到對應輸出，請先下個測試指令觸發 spawn，再驗證一次。

### 3.1 檢查 Browser Profile

透過 Docker CLI 執行（因為 Gateway 跑在 Docker 內，需使用已配對的 operator token）：

```bash
docker compose run --rm openclaw-cli browser profiles
```

> [!NOTE]
> 因為本指南的架構是 Gateway 跑在 Docker 內，已配對的 operator token 在 Docker CLI 中，
> 所以驗證指令需透過 Docker CLI 執行。
> 如果你的 Gateway 是直接跑在本機（非 Docker），則改用 `openclaw browser profiles` 即可。
>
> **注意：** Mac Host 的 `openclaw` 若是以 `--no-onboard` 安裝的純 Node，
> 其 operator token 未配對，在 Host 直接執行此指令會觸發 Node 進入 repair 狀態。

**預期結果：**

應看到類似以下輸出，代表 Node 已成功連接到 Mac 上正在執行的 Chrome：

```text
openclaw: running (2 tabs) [default]
  port: 18800, color: #FF4500
user: running (3 tabs) [existing-session]
  transport: chrome-mcp, color: #00AA00
```

### 3.2 檢查工具清單

在 Control UI 或 任何 Channel (Telegram/Discord 等) 中輸入：

```text
/tools verbose
```

**預期結果：**

- `Profile: full`
- 工具清單中出現 `Browser`（而不僅是 `Web Fetch`）。

### 3.3 測試

在 Control UI 或 任何 Channel 輸入測試指令：

```text
開一個新的瀏覽器分頁，打開 https://www.threads.net/，不要關閉分頁，然後描述畫面。
```

## 4. 使用技巧與最佳實踐

### 4.1 保持登入狀態

由於登入狀態保存在 Mac Chrome 的 Session 中，請注意：

- 不要清空瀏覽器 Cookie。
- 不要使用無痕模式。
- 不要登出目標網站（如 Threads / IG）。

### 4.2 穩定控制指令建議

為了避免「Tab not found」或誤操作，建議使用明確的自然語言：

- **開啟新分頁：** 「開一個新的瀏覽器分頁，打開 [網址]」
- **保持頁面：** 「停在登入頁，不要替我輸入帳號密碼」
- **發文預覽：** 「進到發文頁面，把內容貼上，但先**不要**送出」

## 延伸閱讀

- [Browser Profiles 設定與 Multi-Profile 指南](./browser-profiles-config.md) — 多 profile / 固定 port 綁定的詳細設定。
- [Hermes 視角：Docker → Mac Chrome 接線架構](https://github.com/kaka-lin/hermes-server/blob/main/docs/guides/mac-chrome-cdp-guide.md) — 同時用 Hermes 時，搞懂兩者怎麼搭、`cdp_proxy.py` 的角色、lazy-load 與 auto-fallback 陷阱。
- [OpenClaw 內建工具整理與查詢 (LLM-notes)](/Users/kaka/Projects/kaka/LLM-notes/OpenClaw/openclaw-tools-guide.md) — Runtime / FS / Messaging 等工具分類查詢。
