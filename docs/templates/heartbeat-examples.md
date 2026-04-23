# HEARTBEAT.md 範例集

> 搭配 [Heartbeat 設定指南](../guides/heartbeat-config.md) 使用。

## 1. 空白（停用 heartbeat API 呼叫）

HEARTBEAT.md 存在但留空，系統會跳過不呼叫模型，不花費任何 token。

```markdown
# Keep this file empty (or with only comments) to skip heartbeat API calls.
```

## 2. 輕量巡邏（簡易清單，每次都跑）

適合固定頻率檢查的場景，不需要個別 task interval，每次 heartbeat 都執行所有項目。

```markdown
# Heartbeat checklist

- 檢查有沒有未讀的重要通知或訊息
- 確認今天有沒有即將到來的會議或待辦事項
- 若無需關注事項，請回覆 HEARTBEAT_OK
```

## 3. 多任務不同頻率（tasks 區塊）

各 task 有自己的 interval，只跑到期的。全部未到期則整次跳過，不呼叫模型。

```markdown
tasks:

- name: check-notifications
  interval: 30m
  prompt: "檢查 GitHub 通知，有 review request 或 mention 請回報。沒有就回覆 HEARTBEAT_OK。"

- name: check-calendar
  interval: 1h
  prompt: "檢查今天行事曆，30 分鐘內有會議請提醒。沒有就回覆 HEARTBEAT_OK。"

- name: daily-summary
  interval: 24h
  prompt: "根據今天的對話歷史，摘要今天完成了什麼。"
```

## 4. 混合格式（簡易清單 + tasks 區塊）

結合兩種寫法：`tasks:` 區塊外的 markdown 作為額外 context 每次都會給 agent 看，`tasks:` 區塊內的任務只在到期時執行。

```markdown
# Heartbeat checklist

- 若所有任務完成且無需關注事項，請回覆 HEARTBEAT_OK。

tasks:

- name: check-notifications
  interval: 30m
  prompt: "檢查 GitHub 通知，有 review request 或 mention 請回報。沒有就回覆 HEARTBEAT_OK。"

- name: check-calendar
  interval: 1h
  prompt: "檢查今天行事曆，30 分鐘內有會議請提醒。沒有就回覆 HEARTBEAT_OK。"

# 補充說明

- 保持回覆簡短。
- 所有到期任務完成後，若無需關注事項，請回覆 HEARTBEAT_OK。
```

## 5. 測試用（驗證 heartbeat 是否正常運作）

搭配 `openclaw.json` 設定 `showOk: true`，確認 delivery 有在跑。測試完成後替換成正式版。

```markdown
# Heartbeat checklist

- 若所有任務完成且無需關注事項，請回覆 HEARTBEAT_OK。

tasks:

- name: heartbeat-ping
  interval: 10m
  prompt: "請只回覆以下格式，不要加任何其他內容：HEARTBEAT PING - [HH:MM] - 運作中"

- name: heartbeat-ok-test
  interval: 5m
  prompt: "請只回覆：HEARTBEAT_OK"

# 補充說明

- 保持回覆簡短。
- 所有到期任務完成後，若無需關注事項，請回覆 HEARTBEAT_OK。
```

> [!TIP]
> `interval` 不應小於 `openclaw.json` 的 `heartbeat.every`，否則沒有意義。

## 6. 格式注意事項

- `tasks:` 放在最左邊（column 0）
- `tasks:` 後空一行
- `-` 放在最左邊（column 0）
- `name`、`interval`、`prompt` 縮排 2 格
- 每個 task 的 prompt 都要明確加上沉默條件（如「沒有就回覆 HEARTBEAT_OK」）
- `tasks:` 區塊外的 markdown 內容作為額外 context，每次都會給 agent 看
