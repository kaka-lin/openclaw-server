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

#### 🧩 擴充技能 (Skills) 管理

生態系提供官方指令，透過 ClawHub 安裝並同步 AgentSkills：

- **查看目前安裝的 Skills 清單：**

  ```bash
  docker compose run --rm openclaw-cli skills list
  ```

- **安裝一個新的 Skill：**

  ```bash
  docker compose run --rm openclaw-cli skills install <skill-slug>
  ```

- **更新本地已安裝的 Skills：**

  ```bash
  docker compose run --rm openclaw-cli skills update --all
  ```

- **掃描並同步發布至 ClawHub：**

  ```bash
  docker compose run --rm openclaw-cli clawhub sync --all
  ```
