# Gateway 與 CLI 運作機制及使用指南

OpenClaw 的核心程式 (`index.js`) 設計了兩種截然不同的工作模式：

## 1. 核心概念：一體兩面的系統

### openclaw-gateway (閘道伺服器)

- **職責**：常駐背景運行，監聽 `18789` 通訊埠，處理瀏覽器操作與通訊軟體訊息。
- **啟動方式**：直接執行 `docker compose up -d`。
- **狀態**：不可以隨意中斷，否則系統服務會中斷。

### openclaw-cli (命令列工具)

- **職責**：用於修改系統底層設定（例如綁定帳號、掃描 WhatsApp QR Code）。
- **機制**：啟動一個臨時的分身程式，對資料庫執行完指令後會自動關閉，不影響 Gateway 運行。
- **狀態**：隨開隨用，執行完即自動銷毀。

## 2. 在本專案中執行 CLI

本專案已透過 `docker-compose.yml` 將 CLI 封裝。只要在所有的指令前加上 `docker compose run --rm openclaw-cli` 即可使用。

### 常見 CLI 操作範例

#### 🔑 查詢 Dashboard 控制台連結

如果您忘了之前的 Token 或登入網址，可以直接輸入指令：

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

#### 📱 裝置管理 (Device Management)

當有新裝置嘗試連線時，您需要手動核准它：

- **查看申請清單**：

  ```bash
  docker compose run --rm openclaw-cli devices list
  ```

- **核准裝置** (將 `<id>` 換成上一步看到的 ID)：

  ```bash
  docker compose run --rm openclaw-cli devices approve <id>
  ```

#### 🔗 綁定通訊軟體頻道

- **查看已綁定的頻道清單：**

  ```bash
  docker compose run --rm openclaw-cli channels list
  ```

- **Telegram**：

  ```bash
  docker compose run --rm openclaw-cli channels add --channel telegram --token "<Token>"
  ```

- **Discord**：

  ```bash
  docker compose run --rm openclaw-cli channels add --channel discord --token "<Token>"
  ```

- **WhatsApp (掃描 QR Code)**：

  ```bash
  docker compose run --rm openclaw-cli channels login
  ```

#### ⏰ Cron Job 排程管理

詳細設定請參考 [自動化與 Cron Job 設定指南](./automation-config.md)。

- **列出所有排程：**

  ```bash
  docker compose run --rm openclaw-cli cron list
  ```

- **查看特定排程詳情：**

  ```bash
  docker compose run --rm openclaw-cli cron show <job-id>
  ```

- **手動立即執行：**

  ```bash
  docker compose run --rm openclaw-cli cron run <job-id>
  ```

- **查看執行記錄：**

  ```bash
  docker compose run --rm openclaw-cli cron runs --id <job-id>
  ```

- **刪除排程：**

  ```bash
  docker compose run --rm openclaw-cli cron remove <job-id>
  ```

#### 💓 Heartbeat 管理

詳細設定請參考 [Heartbeat 設定指南](./heartbeat-config.md)。

- **立即觸發一次 heartbeat：**

  ```bash
  docker compose run --rm openclaw-cli system event --text "heartbeat test" --mode now
  ```

- **查看上次 heartbeat 狀態：**

  ```bash
  docker compose run --rm openclaw-cli system heartbeat last
  ```

#### 🧩 擴充技能 (Skills) 管理

生態系提供官方指令，讓使用者能透過 ClawHub 輕鬆安裝與更新 AgentSkills：

- **查看目前安裝的 Skills 清單：**

  ```bash
  docker compose run --rm openclaw-cli skills list
  ```

- **安裝一個新的 Skill：**

  ```bash
  docker compose run --rm openclaw-cli skills install <skill-slug>
  ```

- **從 ClawHub 更新本地已安裝的第三方 Skills（拉取最新版本）：**

  > **⚠️ 注意**：如果您是手動修改了本地的 `SKILL.md` 進行開發，**請勿**執行此指令，否則您的修改可能會被遠端版本覆蓋。本地修改通常會由 Gateway 自動熱重載生效，或透過對話視窗輸入 `/restart` 重啟服務。

  ```bash
  docker compose run --rm openclaw-cli skills update --all
  ```

- **發布技能至 ClawHub (針對開發者)：**

  發布技能使用的是獨立的 `clawhub` CLI 工具，**不包含在 `openclaw-cli` 中**。若要發布，請在本機環境使用 `npm install -g clawhub` 安裝後，直接執行 `clawhub sync --all`。
