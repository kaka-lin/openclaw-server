# Heartbeat 心跳排程配置指南

本文件說明如何在本專案的 `openclaw.json` 中設定 Heartbeat（心跳排程），讓 Agent 能夠週期性執行背景任務。

> **機制詳解**：若想深入了解 Heartbeat 的底層運作原理，請參考知識庫筆記 `LLM-notes/OpenClaw/concepts/heartbeat-mechanism.md`。
>
> **官方文件**：<https://docs.openclaw.ai/gateway/heartbeat>

## 1. 基本概念

- Heartbeat 是 **Gateway 內部定時器**，與 Channel (Discord/Telegram) 無關。
- 預設間隔為 `30m`（Anthropic OAuth 模式下為 `1h`）。
- 預設 `target: "none"`，代表心跳會執行但**不會把結果投遞到任何 Channel**。
- 若要在 Discord 或 Telegram 看到心跳報告，必須明確設定 `target`。

## 2. 設定方式

直接編輯 `openclaw.json` 或使用 CLI 皆可，效果完全相同。

### 2.1 直接編輯 openclaw.json

在 `agents.defaults` 區塊內加入 `heartbeat`：

```json
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "every": "30m",
        "target": "discord",
        "lightContext": true,
        "isolatedSession": true
      }
    }
  }
}
```

若只想讓特定 Agent（例如 `sentinel`）有心跳，改在 `agents.list[]` 中設定：

```json
{
  "agents": {
    "list": [
      {
        "id": "sentinel",
        "heartbeat": {
          "every": "1h",
          "target": "discord",
          "lightContext": true,
          "isolatedSession": true
        }
      }
    ]
  }
}
```

> [!IMPORTANT]
> 一旦任何 `agents.list[]` 中有設定 `heartbeat`，則**只有**設定了 heartbeat 的 Agent 會執行心跳。其他 Agent 不會繼承 `agents.defaults.heartbeat`。

### 2.2 使用 CLI

```bash
# 設定全域心跳間隔與投遞目標
docker compose run --rm openclaw-cli config set \
  agents.defaults.heartbeat \
  '{"every":"30m","target":"discord","lightContext":true,"isolatedSession":true}' \
  --strict-json

# 或為特定 Agent 設定
docker compose run --rm openclaw-cli config set \
  agents.list.sentinel.heartbeat \
  '{"every":"1h","target":"discord","lightContext":true,"isolatedSession":true}' \
  --strict-json
```

修改完後重啟 Gateway 以套用：

```bash
docker compose restart openclaw-gateway
```

## 3. HEARTBEAT.md 設定

將 `HEARTBEAT.md` 放在 Agent 的 Workspace 目錄中。

### 3.1 簡易清單（每次都執行）

```markdown
# Heartbeat

- 保活任務：檢查目前的系統連線與時間
- 每小時流量引擎：執行 `langlive-growth-engine` Skill
```

### 3.2 tasks: 區塊（各任務獨立排程，推薦）

```markdown
tasks:
  - name: keepalive
    interval: 30m
    prompt: "檢查目前的系統連線與時間。"
  - name: growth-engine
    interval: 60m
    prompt: "執行 langlive-growth-engine Skill（搜尋 Threads、過濾主播、生成回覆）。執行前請先檢查 memory/heartbeat-state.json，如果距離上次執行還沒超過 60 分鐘則跳過，若實際執行了則請更新該檔案的時間。"

# Additional instructions

- Keep alerts short.
- If nothing needs attention after all due tasks, reply HEARTBEAT_OK.
```

使用 `tasks:` 區塊的關鍵優勢：

- 每個 task 有自己的 `interval`，**只有到期的 task 才會被執行**。
- 若所有 task 都未到期，心跳會直接跳過，不浪費模型呼叫。
- 系統自動追蹤每個 task 的上次執行時間（存於 session state）。

## 4. Channel 層級的可見性控制

控制心跳訊息是否顯示在各 Channel 上：

```json
{
  "channels": {
    "defaults": {
      "heartbeat": {
        "showOk": false,
        "showAlerts": true,
        "useIndicator": true
      }
    },
    "discord": {
      "heartbeat": {
        "showOk": false,
        "showAlerts": true
      }
    },
    "telegram": {
      "heartbeat": {
        "showOk": true
      }
    }
  }
}
```

| 欄位 | 預設 | 說明 |
|---|---|---|
| `showOk` | `false` | 是否把「沒事」的 `HEARTBEAT_OK` 回覆送出去。 |
| `showAlerts` | `true` | 是否把「有事」的警報送出去。 |
| `useIndicator` | `true` | 是否發送 UI 狀態事件。 |

## 5. 本專案建議配置

基於目前架構（多 Agent + Discord + Telegram），建議的最小心跳配置：

```json
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "every": "0m"
      }
    },
    "list": [
      {
        "id": "sentinel",
        "heartbeat": {
          "every": "30m",
          "target": "discord",
          "lightContext": true,
          "isolatedSession": true,
          "activeHours": {
            "start": "08:00",
            "end": "24:00",
            "timezone": "Asia/Taipei"
          }
        }
      }
    ]
  },
  "channels": {
    "defaults": {
      "heartbeat": {
        "showOk": false,
        "showAlerts": true
      }
    }
  }
}
```

**設計考量**：

- 只讓 `sentinel`（排程任務與監控專用助手）執行心跳，其他 Agent 不需要。
- `lightContext: true` + `isolatedSession: true` 大幅省 Token。
- `activeHours` 限制在台灣時間 08:00-24:00 運行，避免凌晨白跑。
- `showOk: false` 避免每 30 分鐘在 Discord 收到一堆「沒事」的訊息。
- `showAlerts: true` 確保有異常時會主動通知。
