# OpenClaw 自動化與 Cron Job 設定指南

> **版本：** v2026.4.2 ｜ **更新日期：** 2026-04-23

OpenClaw 內建排程器（Scheduler），允許使用 `--at`、`--every` 或 Cron 表達式精確喚醒 Agent 執行工作。

## 1. 核心觀念：Scheduled Tasks 與 Background Tasks

Cron 是 Gateway 內建的精確排程器；Background Tasks 是用來追蹤 detached work 的任務紀錄系統。每次 cron execution 都會建立 task record，但 cron 本身不是 task ledger。

- **排程持久化**：job 定義儲存在 `~/.openclaw/cron/jobs.json`，重啟 Gateway 自動載入。
- **執行狀態**：runtime state 會寫在旁邊的 `jobs-state.json`。
- **紀錄追蹤**：每次執行都建立 task record，並留下完整日誌。
- **Session 模式**：可選 `isolated`、`main`、`current` 或 `session:<id>`；`isolated` 適合報告與背景工作，`main` 適合提醒與 system event。

## 2. 設定方式

Cron job 有兩種建立方式，效果完全一樣，最終都寫入 `~/.openclaw/cron/jobs.json`。不需要手動編輯 `jobs.json`。

### 2.1 方式 A：透過聊天請 Agent 建立（推薦）

直接在 Discord 對 agent 說：

```text
幫我建立一個 cron job：
- 每天早上 9 點執行（Asia/Taipei）
- 檢查今日所有未讀郵件並提供摘要
- 任務名稱：每日早晨簡報
- 結果發送到這個頻道
```

Agent 會自動建立排程。不用記 CLI 參數，用自然語言描述即可。

### 2.2 方式 B：透過 CLI 建立

```bash
docker compose run --rm openclaw-cli cron add \
  --cron "0 9 * * *" \
  --message "檢查今日所有未讀郵件並提供摘要" \
  --name "每日早晨簡報" \
  --announce \
  --channel discord \
  --to <CHANNEL_ID>
```

#### 參數說明：

- `--cron`: Cron 表達式（例如 `"0 16 * * *"` 代表每日 16:00）。
- `--message`: 傳遞給 Agent 的 Prompt。
- `--name`: 任務顯示名稱。
- `--session`:
  - `isolated`（預設）：使用乾淨的 Agent 環境。
  - `main`：在主對話 Session 中執行（系統事件模式）。
  - `current`：綁定到建立時的當前 session。
  - `session:<id>`：指定持久 session，跨次保留歷史。
- `--announce`: 主動將最終回覆發送到指定頻道（isolated 預設行為）。
- `--no-deliver`: 靜默執行，僅寫入紀錄。
- `--channel`: 指定發送頻道（`discord`, `telegram` 等）。
- `--to`: 接信人的 ID 或頻道 ID。

> [!NOTE]
> `--deliver` 為已棄用的舊寫法，請改用 `--announce` 和 `--no-deliver`。

### 2.3 三種排程方式

```bash
# 一次性（相對時間）— 執行成功後自動刪除
docker compose run --rm openclaw-cli cron add \
  --name "30 分鐘後提醒" --at "30m" --message "提醒我開會"

# 一次性（絕對時間）— 需加 --tz，否則視為 UTC
docker compose run --rm openclaw-cli cron add \
  --name "明天早上" --at "2026-04-25T09:00:00" --tz "Asia/Taipei" --message "查看報告"

# 固定間隔
docker compose run --rm openclaw-cli cron add \
  --name "每小時同步" --every "1h" --message "同步資料"

# Cron expression（5 或 6 欄位；需要時搭配 --tz）
docker compose run --rm openclaw-cli cron add \
  --name "每天早上報告" --cron "0 9 * * *" --message "產出今日摘要"
```

### 2.4 Delivery 推送設定

```bash
# announce：agent 沒主動發訊時，自動推送最終回覆（isolated 預設）
docker compose run --rm openclaw-cli cron add \
  --cron "0 9 * * *" --session isolated --message "日報" --announce

# 推送到指定頻道
docker compose run --rm openclaw-cli cron edit <id> \
  --announce --channel discord --to <CHANNEL_ID>

# 停用推送（靜默執行，只寫日誌）
docker compose run --rm openclaw-cli cron edit <id> --no-deliver
```

### 2.5 管理指令

| 指令 | 說明 |
| ---- | ---- |
| `docker compose run --rm openclaw-cli cron list` | 列出所有排程及其 ID |
| `docker compose run --rm openclaw-cli cron show <id>` | 查看詳細設定（含 delivery 路由預覽） |
| `docker compose run --rm openclaw-cli cron run <id>` | 立即手動執行一次 |
| `docker compose run --rm openclaw-cli cron runs --id <id>` | 查看歷史執行記錄 |
| `docker compose run --rm openclaw-cli cron edit <id> [options]` | 修改現有排程設定 |
| `docker compose run --rm openclaw-cli cron remove <id>` | 刪除排程 |

### 2.6 常用 edit 範例

```bash
# 換 agent
docker compose run --rm openclaw-cli cron edit <id> --agent ops

# 換 session
docker compose run --rm openclaw-cli cron edit <id> --session "session:daily-brief"

# 指定模型
docker compose run --rm openclaw-cli cron edit <id> --model claude-haiku-4-5-20251001

# 啟用 light context（跳過 workspace bootstrap 檔案注入，省 token）
docker compose run --rm openclaw-cli cron edit <id> --light-context
```

## 3. Heartbeat vs Cron 選擇原則

兩者都能「定時」，但設計初衷不同：

| 特性 | Heartbeat | Cron Job |
| :--- | :--- | :--- |
| **時間精度** | 近似（預設每 30 分鐘） | 精確（cron expression、one-shot） |
| **設定方式** | `openclaw.json` + `HEARTBEAT.md` | CLI 或聊天請 agent 建立 |
| **執行環境** | Main session（預設） | Isolated（預設） |
| **Task 記錄** | 不建立 | 每次都建立 |
| **投遞方式** | 內嵌在 main session 中 | Channel、webhook、或靜默 |
| **適合場景** | 收件匣掃描、行事曆、通知彙整 | 報告、提醒、背景自動化任務 |

**怎麼選：**

| 任務類型 | 用哪個 | 原因 |
| :--- | :--- | :--- |
| 快速掃一眼（通知、信箱、開播狀態） | **Heartbeat** | 輕量、不需紀錄 |
| 多步驟重度任務（瀏覽器自動化、報告生成） | **Cron** | 耗時、需隔離、需紀錄追蹤 |
| 精確時間執行（每天 9 點產報告） | **Cron** | 時間精確 |
| 一次性提醒（20 分鐘後提醒我） | **Cron**（`--at`） | one-shot |

> [!NOTE]
> Heartbeat 官方建議 "keep it tiny"。不是所有定期任務都適合放在 HEARTBEAT.md。
> Heartbeat 詳細設定請參閱 [Heartbeat 設定指南](./heartbeat-config.md)。

## 4. 實戰範例

每個範例都提供聊天和 CLI 兩種方式。

### 範例 A：每小時檢查代碼庫變動

**聊天：**

```text
幫我建立一個 cron job：
- 每小時整點執行
- 檢查最新 Git Commit，若有重要變更請摘要
- 靜默執行，不需要推送結果
```

**CLI：**

```bash
docker compose run --rm openclaw-cli cron add \
  --name "每小時代碼檢查" \
  --cron "0 * * * *" \
  --message "檢查最新 Git Commit，若有重要變更請摘要。" \
  --no-deliver
```

### 範例 B：特定時段運行的報表

**聊天：**

```text
幫我建立一個 cron job：
- 每週一到週五 17:30 執行（Asia/Taipei）
- 產出今日任務列表並回報
- 結果發送到這個頻道
```

**CLI：**

```bash
docker compose run --rm openclaw-cli cron add \
  --name "每日任務報表" \
  --cron "30 17 * * 1-5" \
  --tz "Asia/Taipei" \
  --message "產出今日任務列表並回報" \
  --announce --channel discord --to <CHANNEL_ID>
```

### 範例 C：背景自動化任務（需授權操作）

如果 agent 的安全規則要求某些操作前需詢問確認（如發送郵件、對外發文等），在背景執行時無法互動，必須在訊息中加入明確授權。

**聊天：**

```text
幫我建立一個 cron job：
- 每週一到週五早上 9 點執行（Asia/Taipei）
- 掃描今日未讀郵件，整理成摘要並寄送到 team@example.com
- 這是已授權的排程任務，授權直接發送郵件，無需詢問確認
- 結果發送到這個頻道
```

**CLI：**

```bash
docker compose run --rm openclaw-cli cron add \
  --name "每日郵件摘要" \
  --cron "0 9 * * 1-5" \
  --tz "Asia/Taipei" \
  --session isolated \
  --message "掃描今日未讀郵件，整理成摘要並寄送到 team@example.com。這是已授權的排程任務：授權直接發送郵件，無需詢問使用者確認。" \
  --announce
```

> [!IMPORTANT]
> 此授權僅對該 cron job 生效，不影響互動對話時的安全行為。

## 5. 常見問題 (Q&A)

**Q: 為什麼設定了 `agents.defaults.heartbeat` 但某個 agent 心跳沒反應？**

A: 只要 `agents.list[]` 裡任何一個 agent 設了 `heartbeat` block，其他沒設的就不再繼承 defaults。詳見 [Heartbeat 設定指南 §7](./heartbeat-config.md)。

**Q: 為什麼 Cron job 卡在發文步驟不動？**

A: Agent 的安全規則要求對外發文前詢問確認，但背景執行無法互動。在 `--message` 中加入明確授權即可（見範例 C）。

**Q: 設定儲存在哪裡？**

A: `~/.openclaw/cron/jobs.json`（容器內為 `/home/node/.openclaw/cron/jobs.json`）。Gateway 重啟後自動載入。
