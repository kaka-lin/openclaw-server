# OpenClaw 瀏覽器控制：Docker Gateway + Mac Host Chrome 完整設定指南

本指南整合了 OpenClaw 在 Docker 環境下執行 Gateway，並透過 Mac Host 上的 Node 控制本機 Chrome 的完整安裝、設定與排障流程。

## 1. 目標與架構

### 1.1 目標

讓 **OpenClaw 的 Control UI 或任何已連線的 Channel (如 Telegram, Discord, Slack 等)** 可以透過自然語言，直接控制 **Mac 上已開啟且已登入的 Chrome**，並保持登入狀態（如 Threads, Instagram 等）。

### 1.2 架構圖

- **OpenClaw Gateway**：執行於 Docker 容器 (`openclaw-gateway`)。
- **OpenClaw CLI (管理)**：執行於 Docker 容器 (`openclaw-cli`)，用於修改 Gateway 設定。
- **OpenClaw Node Host**：執行於 **Mac 主機**，作為橋接器。
- **Chrome 瀏覽器**：執行於 **Mac 主機**（使用現有的 User Profile / Session）。
- **控制流**：Control UI / Channels -> Gateway -> Mac Node -> Mac Chrome。

## 2. 完整安裝與設定步驟

### 2.1 步驟 1：啟動 OpenClaw Gateway (Docker)

在 OpenClaw 專案目錄下執行：

```bash
bash setup.sh
```

確認可開啟管理介面：`http://127.0.0.1:18789`。

### 2.2 步驟 2：在 Mac Host 安裝 OpenClaw CLI

Node 必須跑在 Mac 主機上才能控制本機 Chrome。執行安裝指令（跳過 onboard 流程）：

```bash
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
```

確認安裝成功：`openclaw --version`。

### 2.3 步驟 3：切換工具集為 Full (Docker 端)

這是最關鍵的一步。預設的 `coding` profile 不包含 `Browser` 工具。

```bash
docker compose -f docker-compose.yml run --rm openclaw-cli config set tools.profile full
docker compose -f docker-compose.yml restart openclaw-gateway
```

### 2.4 步驟 4：設定 Browser 路由與預設 Profile (Docker 端)

指示 Gateway 將瀏覽器請求路由到名為 "Mac Mini Node" 的節點，並避免使用 Container 內的 Chrome。

```bash
docker compose -f docker-compose.yml run --rm openclaw-cli config set gateway.nodes.browser.mode auto
docker compose -f docker-compose.yml run --rm openclaw-cli config set gateway.nodes.browser.node "Mac Mini Node"
docker compose -f docker-compose.yml run --rm openclaw-cli config set browser.defaultProfile openclaw
docker compose -f docker-compose.yml restart openclaw-gateway
```

### 2.5 步驟 5：啟動 Mac Host Node

#### 選項一：手動執行（測試用）

在 Mac Terminal 執行（請替換為你的 Gateway Token）：

```bash
export OPENCLAW_GATEWAY_TOKEN="<你的 gateway token>"
openclaw node run --host 127.0.0.1 --port 18789 --display-name "Mac Mini Node"
```

> [!IMPORTANT]
> 此指令必須保持執行狀態，不可關閉。

#### 選項二：macOS LaunchAgent（開機自動啟動，推薦）

Repo 提供了一個安裝腳本，會自動偵測 `openclaw` 路徑與 Gateway Token，並直接寫入 `~/Library/LaunchAgents/`。

1. 執行安裝腳本：

    ```bash
    bash scripts/install-node-launchagent.sh
    ```

    腳本會依序：

    - 自動偵測 `openclaw` binary 路徑（支援 nvm）
    - 自動從 `~/.openclaw/openclaw.json` 讀取 Gateway Token
    - 詢問 Node 顯示名稱（預設 `Mac Mini Node`）
    - 寫入 plist 並執行 `launchctl load`

2. 確認服務正常運作：

    ```bash
    launchctl list | grep openclaw
    cat /tmp/openclaw-node.log
    ```

> [!NOTE]
> LaunchAgent 會在登入後自動啟動，並在異常退出時自動重啟（`KeepAlive: true`）。
> 若需手動調整，plist 範本位於 `scripts/com.openclaw.node.plist`。

### 2.6 步驟 6：批准裝置連線 (Docker 端)

在 Docker CLI 中核准來自 Mac Node 的連線：

```bash
# 列出待配對裝置
docker compose -f docker-compose.yml run --rm openclaw-cli devices list

# 批准最新的 pending 裝置
docker compose -f docker-compose.yml run --rm openclaw-cli devices approve --latest
```

### 2.7 步驟 7：準備 Mac Chrome

1. 確保 **Chrome 保持開啟**。
2. 至少保留一個分頁。
3. 如果跳出「允許遠端連線 / Attach」的系統提示，請務必點擊 **允許**。
4. 前往 [chrome://inspect/#remote-debugging](chrome://inspect/#remote-debugging) 確保已允許 Remote Debugging（如有此選項）。

## 3. 驗證設定是否成功

### 3.1 檢查 Browser Profile

在 Mac Host 執行：

```bash
openclaw browser profiles
```

**預期結果：**

應看到 `user: running (...) [existing-session]`。這代表 Mac 現有的 Chrome session 已可被附著。

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

## 5. 常見問題與排障 (FAQ)

### 5.1 Q: 為什麼 Agent 一直說不支援 JS 或只能用 Web Fetch？

**原因：** 這是因為 `tools.profile` 被設為 `coding` 或其他不含 `Browser` 的模式。
**解法：** 執行步驟 3，將 profile 改為 `full` 並重啟 Gateway。

### 5.2 Q: 出現 `Could not find DevToolsActivePort` 錯誤？

**原因：** Gateway 試圖直接在 Docker Container 內啟動 Chrome，而非路由到 Mac Node。
**解法：** 檢查步驟 4 的 `gateway.nodes.browser.mode` 與 `node` 設定是否正確。

### 5.3 Q: Node 顯示 `pairing required`？

**原因：** Mac Node 尚未在 Gateway 中被核准。
**解法：** 使用 `openclaw-cli devices approve --latest` 進行核准。

## 延伸閱讀

關於 OpenClaw 內建的所有工具分類（如 Runtime, FS, Messaging 等）及其查詢方式，請參閱：

- [OpenClaw 內建工具整理與查詢 (LLM-notes)](/Users/kaka/Projects/kaka/LLM-notes/OpenClaw/openclaw-tools-guide.md)
