# OpenClaw Server

## 🚀 快速開始

按照以下步驟即可快速完成初始化並啟動 OpenClaw：

```bash
# 1. 複製專案並進入目錄
git clone https://github.com/kaka-lin/openclaw-server.git
cd openclaw-server

# 2. 設定環境變數（填入你的 API Keys）
cp .env.example .env

# 3. 執行初始化與啟動伺服器
./setup.sh
```

## 首次裝置配對 (Device Pairing)

首次啟動後，瀏覽器需要完成**裝置配對**才能使用 Control UI。

> [!TIP]
> **為什麼需要配對？**
> Docker 容器內的 Gateway 看到的連線來源是 `192.168.65.1`（Docker 橋接網路），而非 `127.0.0.1`（本機）。這是一次性的安全驗證，核准後不需要重複操作。

```bash
# 1. 開啟瀏覽器 http://localhost:18789，輸入 Token 後送出
#    此時會出現 "pairing required" 錯誤，這是正常的

# 2. 查看待核准的裝置請求
docker compose run --rm openclaw-cli devices list

# 3. 核准裝置（將 <request_id> 替換為上一步看到的 ID）
docker compose run --rm openclaw-cli devices approve <request_id>

# 4. 取得 Dashboard URL
docker compose run --rm openclaw-cli dashboard --no-open
```

## 日常使用指令

初始化完成後，日常開關機**不需要**再執行 `./setup.sh`：

- **背景啟動**：`docker compose up -d openclaw-gateway`
- **停止伺服器**：`docker compose down`
- **查看即時日誌**：`docker compose logs -f openclaw-gateway`

## 注意事項

- **存取介面**：建議優先使用 `http://localhost:18789`。瀏覽器規定「安全環境 (Secure Context)」下才能產生 Device Identity。
- **登入金鑰**：Token 留空時 `setup.sh` 會自動產生，並同步寫入 `.env` 與 `~/.openclaw/openclaw.json`。

## 進階設定與 CLI 工具 (OpenClaw CLI)

如需綁定通訊軟體 (如 Telegram、WhatsApp 或 Discord) 或進行更進階的設定，可透過臨時容器執行 CLI 指令。

👉 **詳細原理分析與指令範例：** [Gateway 與 CLI 運作機制及使用指南](./docs/openclaw-cli-usage.md)

## Sandbox (沙盒環境)

OpenClaw 支援 **DooD (Docker-out-of-Docker)** 架構的沙盒環境，讓 AI 代理人可以在隔離的容器中安全地執行程式碼，避免污染主機環境。

- **快速變更狀態**：
  - 啟用：`./scripts/enable_sandbox.sh`
  - 關閉：`./scripts/disable_sandbox.sh`

👉 **詳細操作指引：** [OpenClaw Sandbox 啟用與關閉指南](./docs/openclaw-sandbox-setup.md)

## 延伸閱讀與筆記

### 實作與操作

- [OpenClaw APIs 呼叫指南](https://github.com/kaka-lin/LLM-notes/blob/main/OpenClaw/openclaw-apis.md)
- [OpenClaw Server 部署全攻略：部署機制深度解析 (Deployment Deep Dive)](./docs/deployment-deep-dive.md)
- [OpenClaw Sandbox 啟用與關閉指南](./docs/openclaw-sandbox-setup.md)

### 架構與原理 (LLM-notes)

- [OpenClaw Sandbox 沙盒與 DooD 架構原理](https://github.com/kaka-lin/LLM-notes/blob/main/OpenClaw/sandbox-architecture.md)
- [OpenClaw Docker 網路與綁定設定](https://github.com/kaka-lin/LLM-notes/blob/main/OpenClaw/docker-network-binding.md)
- [OpenClaw 代理人 (Agents) 設計細節](https://github.com/kaka-lin/LLM-notes/blob/main/OpenClaw/openclaw-agents.md)