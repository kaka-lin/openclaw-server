# 🎭 Agent 身分識別設定指南 (Agent Identity)

在 OpenClaw 中，每個 Agent 不僅僅是一個執行腳本的程序，它們可以擁有獨特的**名稱、性格 (Vibe) 與視覺形象**。

透過設定 `IDENTITY.md` 檔案，您可以輕鬆定義 Agent 的「身分特質」，並透過 CLI 工具快速同步到系統中。

## 1. 什麼是 IDENTITY.md？

`IDENTITY.md` 是一個存放在 Agent 工作目錄 (Workspace) 根目錄下的 Markdown 檔案。它具備以下功能：

- **自我介紹**：讓 Agent 知道自己是誰、是什麼角色。
- **視覺設定**：定義在 UI 或通訊軟體 (如 Discord/Telegram) 中顯示的名稱、Emoji 與頭像。
- **性格引導**：透過 Vibe 與描述，影響 Agent 的對話語氣與行為模式。

### 檔案結構範例

```markdown
# IDENTITY.md - Who Am I?

- **Name:** 🦞 OpenClaw Assistant
- **Creature:** AI familiar
- **Vibe:** Sharp, helpful, and slightly chaotic
- **Emoji:** 🦞
- **Avatar:** avatars/openclaw.png
```

## 2. 欄位說明

| 欄位 | 說明 | 對應 CLI 參數 |
| :--- | :--- | :--- |
| **Name** | Agent 的顯示名稱 | `--name` |
| **Creature** | Agent 的本質描述（如：機器人、幽靈、精靈） | (內建於系統提示詞) |
| **Vibe** | 對話風格（如：暖心、專業、冷靜） | (內建於系統提示詞) |
| **Emoji** | 代表該 Agent 的表情符號（作為預設頭像） | `--emoji` |
| **Avatar** | 頭像路徑或是 URL | `--avatar` |

> 💡 **關於 Avatar**：
>
> - **相對路徑**：如 `avatars/bot.png`（相對於該 Workspace 目錄）。
> - **網路路徑**：如 `https://example.com/image.png`。
> - **Data URI**：支援 Base64 編碼的圖片字串。

## 3. 如何同步身分設定

當您修改了 `IDENTITY.md` 後，必須執行 CLI 指令來將這些變更更新到核心系統中。

### 方法 A：基於 Workspace 自動同步（推薦）

如果您知道 Agent 的工作目錄，系統會自動定位該資料夾所屬的 Agent 並讀取檔案。

```bash
docker compose run --rm openclaw-cli agents set-identity \
  --workspace ~/.openclaw/workspace-main \
  --from-identity
```

### 方法 B：指定 Agent ID 與檔案路徑

適合想從特定檔案更新特定對象的場景。

```bash
docker compose run --rm openclaw-cli agents set-identity \
  --agent main \
  --identity-file /path/to/your/IDENTITY.md
```

### 方法 C：直接透過指令參數設定（不使用檔案）

如果您只想快速改名或換 Emoji，可以跳過 Markdown 檔案：

```bash
docker compose run --rm openclaw-cli agents set-identity \
  --agent main \
  --name "新名字" \
  --emoji "🔥"
```

## 4. 最佳實踐

1. **區分角色**：為不同的 Agent 設定不同的 Vibe。例如 `coder` 設定為「邏輯嚴謹」，`writer` 設定為「文采斐然」。
2. **版本控制**：將 `IDENTITY.md` 連同其他設定檔一起備份，方便重新部署時快速恢復 Agent 的「個性」。
3. **配合 Discord**：更新身分後，通常需要重啟 Gateway 或重新載入，Bot 的暱稱與狀態會隨之更新。

## 相關參考

- [Multi-Agent Discord 配置指南](./multi-agent-discord.md)
- [OpenClaw CLI 使用手冊](./cli-usage.md)
