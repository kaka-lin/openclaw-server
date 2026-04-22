# 排錯：CLI 設定路徑中的純數字自動推導 Bug

## 問題描述

當使用 `openclaw-cli config set` 指令去設定一個深層路徑，且路徑中的下一個節點是「純數字字串」（例如 Discord 伺服器 ID：`1488063326796906659`）時，若該路徑的父層（例如 `guilds`）尚不存在，CLI 可能會錯誤地將父層類型推導為 **陣列 (Array)**，而非 **Record (物件)**。

### 症狀

即使您的 JSON 結構邏輯看起來正確，仍會收到驗證失敗錯誤：

```text
Error: Config validation failed: channels.discord.accounts.my-agent.guilds: Invalid input: expected record, received array
```

## 發生原因

`openclaw-cli` 在處理設定路徑時具有動態類型推導機制。當它遇到一個看起來完全是數字的路徑節點時，其預設策略會假設您正在設定一個 **陣列索引 (Array Index)**。

如果當時 `openclaw.json` 中還沒有該父層（例如 `guilds`），CLI 會先將其初始化為空的陣列 `[]`。隨後的 Zod Schema 驗證就會失敗，因為設定檔規範要求 `guilds` 必須是一個物件 `{}`。

## 解決方案：明確初始化 (Explicit Initialization)

為了防止 CLI 誤判類型，您必須在設定具備「純數字 Key」的子屬性之前，**先明確將父層初始化為空物件 `{}`**。

### 修正範例 (Bash)

不建議直接設定深層數字路徑：

```bash
# 如果 "guilds" 不存在，這一行可能會失敗
openclaw config set channels.discord.accounts.agent-id.guilds.12345 '{"requireMention": true}'
```

請拆分為兩步執行：

```bash
# 1. 先明確初始化為物件
openclaw config set "channels.discord.accounts.agent-id.guilds" "{}" --strict-json

# 2. 現在可以安全地設定數字 Key 的內容了
openclaw config set "channels.discord.accounts.agent-id.guilds.12345" "{\"requireMention\": true}" --strict-json
```

## 相關腳本修正

此 Bug 已在以下腳本中修復並作為標準實作：
- `scripts/setup-agent-discord.sh`：現在使用「階段 5」來確保 `guilds` 先被初始化為物件。
- `scripts/setup-multi-agent-discord.sh`：透過先設定 `main` 帳號來提前穩定 Schema 結構，避開了此問題。
