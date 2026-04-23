# OpenClaw Heartbeat 設定指南

> **版本：** v2026.4.2 ｜ **更新日期：** 2026-04-23

Heartbeat 讓 Agent 能定期自動執行任務，無需人工觸發。

> [!NOTE]
> `agents.list[]` 內的 agent 只要在設定中明確加上 `heartbeat` block，Gateway 啟動時就會自動載入排程。
> 唯一的注意事項是 **繼承規則**：只要 list 中任何一個 agent 設了 heartbeat block，其他沒設的 agent 就不再繼承 `agents.defaults.heartbeat`。詳見第 8 節。

## 1. 運作機制

Heartbeat 在 **main session** 中執行週期性 agent turn，讓模型主動回報需要關注的事項。

```text
Gateway 啟動
    ↓ 讀取 openclaw.json heartbeat 設定

每隔 N 分鐘觸發
    ↓ 喚醒 Agent，執行一次 heartbeat turn

Agent 讀取 HEARTBEAT.md（若存在）
    ↓ 依清單執行工作

回應 HEARTBEAT_OK（無事） 或 Alert（有需關注事項）
    ↓ 依 target 設定決定是否推送通知
```

> [!TIP]
> 如果您需要執行「特定的背景任務」或是「精確時間排程」，請參考 [自動化與 Cron Job 設定指南](./automation-config.md)。

## 2. openclaw.json 設定參數

Heartbeat 可設定在全域預設（`agents.defaults.heartbeat`）或個別 agent（`agents.list[].heartbeat`），個別設定會覆蓋全域預設。

```json5
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "every": "30m",
        "target": "last",
        "lightContext": true,
        "isolatedSession": true
      }
    },
    "list": [
      {
        "id": "worker",
        "heartbeat": {
          "every": "60m",
          "target": "discord",
          "accountId": "worker",
          "to": "<CHANNEL_ID>",
          "lightContext": true,
          "isolatedSession": true,
          "activeHours": {
            "start": "08:00",
            "end": "23:59",
            "timezone": "Asia/Taipei"
          }
        }
      }
    ]
  }
}
```

### 2.1 所有可用參數

| 參數 | 類型 | 預設值 | 說明 |
| ---- | ---- | ------ | ---- |
| `every` | string | `"30m"` | 執行間隔。Anthropic OAuth / token 驗證時預設為 `"1h"`；設為 `"0m"` 可停用 |
| `target` | string | `"none"` | 輸出目的地：`"none"`、`"last"`、`"discord"`、`"telegram"` 等 |
| `to` | string | — | Channel 專屬的收件人 ID（如頻道 ID、Telegram Chat ID） |
| `accountId` | string | — | Multi-account 場景下指定要用哪個帳號投遞 |
| `lightContext` | boolean | `false` | 啟動時只載入 HEARTBEAT.md，大幅節省 token |
| `isolatedSession` | boolean | `false` | 每次在全新 session 執行，不帶對話歷史 |
| `activeHours` | object | 無限制 | 限定執行時段（詳見 2.2） |
| `model` | string | — | 指定此 agent heartbeat 使用的模型 |
| `prompt` | string | — | 自訂 heartbeat 提示詞（覆蓋預設的「讀取 HEARTBEAT.md」） |
| `timeoutSeconds` | number | `45` | 單次執行的最長時間（秒），超過則中止 |
| `ackMaxChars` | number | `300` | HEARTBEAT_OK 回應的最大字元數 |
| `includeReasoning` | boolean | `false` | 是否將推理過程一併傳送 |
| `directPolicy` | string | `"allow"` | DM 傳送政策：`"allow"` 或 `"block"` |

### 2.2 activeHours 設定

```json5
"activeHours": {
  "start": "08:00",
  "end": "23:59",
  "timezone": "Asia/Taipei"
}
```

- `start` / `end`：24 小時制，使用 `HH:MM` 格式
- `timezone`：IANA 時區識別碼（例如 `"Asia/Taipei"`、`"America/New_York"`），或使用 `"user"` / `"local"` 套用主機時區
- 超出時段的 tick 會被跳過，不會補跑
- 完全省略 `activeHours` 表示 24/7 全時段運作

### 2.3 成本優化

同時啟用以下兩個參數，可將每次 heartbeat 的 token 消耗從約 100K 降至 2–5K：

```json5
"lightContext": true,
"isolatedSession": true
```

## 3. HEARTBEAT.md

放在 Agent workspace 內的選用檔案。Agent 執行 heartbeat 時會讀取此檔，決定要做什麼。更多範例請參考 [HEARTBEAT.md 範例集](../templates/heartbeat-examples.md)。

**檔案路徑**：`/home/node/.openclaw/workspace-<agent-id>/HEARTBEAT.md`

> [!NOTE]
> 若 HEARTBEAT.md 為空或只有註解，系統會跳過本次執行，**不呼叫模型**（節省費用）。

### 3.1 簡易清單格式

適合輕量、每次都要執行的固定檢查：

```markdown
# Heartbeat checklist

- 掃描是否有緊急通知？
- 檢查最新的社群互動狀況
- 若無需回報，回覆 HEARTBEAT_OK
```

### 3.2 結構化 tasks 區塊

適合需要不同執行頻率的多個任務，只有到期的任務才會執行：

```markdown
tasks:

- name: inbox-triage
  interval: 30m
  prompt: "掃描未讀郵件，標記所有具時效性的緊急內容。沒有就回覆 HEARTBEAT_OK。"
- name: calendar-scan
  interval: 2h
  prompt: "檢查即將到來的會議，找出需要事前準備或後續跟進的項目。沒有就回覆 HEARTBEAT_OK。"

# 補充說明

- 警報內容請保持簡短。
- 所有到期任務執行完畢後，若無需關注事項，回覆 HEARTBEAT_OK。
```

> [!TIP]
> task 的 `interval` 不應小於 `openclaw.json` 的 `heartbeat.every`，否則沒有意義。

## 4. 回應規範（Response Contract）

Agent 執行完畢後的標準回應規則：

- **無需關注**：回應的開頭或結尾包含 `HEARTBEAT_OK`，且總字元數少於 `ackMaxChars`（預設 300）→ OpenClaw 自動抑制，**不推送通知**
- **需要關注**：回應中不含 `HEARTBEAT_OK` → OpenClaw 將回應傳送到 `target` 指定的頻道

## 5. 可見度控制（Visibility Controls）

預設行為：`HEARTBEAT_OK` 靜音不推送，Alert 內容正常傳送。可透過 `channels` 設定針對特定頻道或帳號調整。

| 參數 | 說明 | 預設值 |
| ---- | ---- | ------ |
| `showOk` | 顯示 `HEARTBEAT_OK` 確認訊息 | `false` |
| `showAlerts` | 傳送 Alert 內容 | `true` |
| `useIndicator` | 發送 UI 狀態事件 | `true` |

**設定優先順序**：per-account → per-channel → channel defaults → 內建預設值。

### 5.1 設定範例

```json5
{
  "channels": {
    "defaults": {
      "heartbeat": {
        "showOk": false,      // 預設：HEARTBEAT_OK 靜音
        "showAlerts": true,   // 預設：Alert 正常傳送
        "useIndicator": true  // 預設：發送 UI 狀態事件
      }
    },
    "discord": {
      "heartbeat": {
        "showOk": true  // 此頻道顯示 HEARTBEAT_OK 確認訊息
      },
      "accounts": {
        "ops": {
          "heartbeat": {
            "showAlerts": false  // 此帳號不推送 Alert（僅靜默執行）
          }
        }
      }
    }
  }
}
```

> [!NOTE]
> 三個參數都設為 `false` 時，整個 heartbeat turn 仍會執行，只是所有輸出都被抑制。若要完全停用，請將 `every` 設為 `"0m"`。

## 6. 手動觸發

立即執行一次 heartbeat（測試用）：

```bash
docker compose run --rm openclaw-cli system event --text "heartbeat test" --mode now
```

排入下一次 heartbeat tick 執行：

```bash
docker compose run --rm openclaw-cli system event --text "請檢查最新通知" --mode next-heartbeat
```

## 7. Multi-Agent Heartbeat 繼承規則

### 7.1 agents.list[] 繼承規則（已驗證）

> **官方文件確認：** "If any `agents.list[]` entry includes a `heartbeat` block, **only those agents** run heartbeats."

只要 `agents.list[]` 裡任何一個 agent 設了 `heartbeat` block，其他沒有設的 agent 就**不再繼承** `agents.defaults.heartbeat`，heartbeat 靜默失效且無錯誤提示。

**錯誤設定（main agent heartbeat 失效）：**

```json5
{
  "agents": {
    "defaults": { "heartbeat": { "every": "30m" } },
    "list": [
      { "id": "main" },                                        // 不跑
      { "id": "ops", "heartbeat": { "every": "1h" } }  // 只有這個跑
    ]
  }
}
```

**正確設定（方案 A：list 裡一個都不設，全靠 defaults）：**

```json5
{
  "agents": {
    "defaults": { "heartbeat": { "every": "30m" } },
    "list": [
      { "id": "main" },  // 繼承 defaults
      { "id": "ops" }    // 繼承 defaults
    ]
  }
}
```

**正確設定（方案 B：每個都明確設）：**

```json5
{
  "agents": {
    "list": [
      { "id": "main", "heartbeat": { "every": "30m" } },
      { "id": "ops",  "heartbeat": { "every": "1h"  } }
    ]
  }
}
```

> [!TIP]
> 不確定該用 Heartbeat 還是 Cron？請參考 [Heartbeat vs Cron 選擇原則](./automation-config.md#3-heartbeat-vs-cron-選擇原則)。
