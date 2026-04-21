# 擴充技能權限與系統指令配置 (openclaw.json)

對於 Gateway 的持有者來說，我們需要透過主設定檔 `~/.openclaw/openclaw.json` 來控制哪些技能可以被誰使用，以及要注入哪些環境變數。

> **💡 前置概念：Skill 是怎麼產生的？**
> 
> 本文件主要聚焦於 **「權限管控與系統層級的環境設定」**。
> 如果您的目標是「如何從零開始撰寫一個專屬的 Skill」（例如建立一個包含 `SKILL.md` 提示詞與腳本的資料夾，並將其放入 `<workspace>/skills` 目錄中），請先參考官方教學：[Creating Skills](https://docs.openclaw.ai/tools/creating-skills)。當技能建置完成後，再回到本文進行全域管控。

## 1. 技能權限與環境變數 (Skills Config)

在設定檔的 `skills` 區塊之下，您可以管理技能的載入與認證設定：

```json
{
  "skills": {
    "load": {
      "extraDirs": ["~/Projects/agent-scripts/skills"],
      "watch": true
    },
    "entries": {
      "image-lab": {
        "enabled": true,
        "env": {
          "GEMINI_API_KEY": "YOUR_KEY_HERE"
        }
      }
    }
  }
}
```

### 1.1 注入 API Keys (`skills.entries`)

這是 Gateway 最常用到的功能。當您從 ClawHub 下載了某個第三方技能，該技能通常缺乏它所需的外部 API 金鑰。為了安全，我們**絕對不要**把金鑰寫在 `SKILL.md` 的提示詞裡面，而是透過 `skills.entries.<skillKey>.env` 的方式動態注入至該次啟動的環境中。

### 1.2 技能自動載入與 Agent 權限隔離

**預設情況（自動載入，全域可用）：**
只要將 Skill 腳本放入 `~/.openclaw/skills` 或是 `<workspace>/skills` 等預設目錄，系統即會自動載入。**如果未在設定檔中做任何限制，所有的 Agent 預設皆可存取並使用這些技能。** 此設定適合單純的個人使用情境，無需額外配置即可享受擴充功能。

**進階情況（權限管控與隔離）：**

> **🤔 常見疑問：為什麼不把技能分別放進各個 Agent 專屬的 Workspace 就好了？**
>
> 1. **全域外掛管理**：從 ClawHub 下載的第三方技能通常安裝在全域（例如 `~/.openclaw/skills`）。與其很笨地手動複製到 10 個不同的 Agent 專屬資料夾中，不如在全域安裝一次，統一透過設定檔分配。
> 2. **共用 Workspace 的情境**：如果有多個 Agent 共用同一個專案資料夾（像是 Coder Agent 負責寫扣、Reviewer Agent 負責審查程式，兩者都在同一個 Workspace），這時就必須依賴這套白名單，來限制負責審查的 Agent 不能偷用寫入指令的技能。

當專案擁有多個專責 Agent，且不希望某些 Agent 存取特定危險技能（例如刪除資料庫）時，您可以在設定檔中使用白名單（Allowlist）機制來嚴格隔離其存取權限：

```json
{
  "agents": {
    "defaults": {
      "skills": ["github", "weather"]
    },
    "list": [
      { "id": "writer" },
      { "id": "docs", "skills": ["docs-search"] },
      { "id": "locked-down", "skills": [] }
    ]
  }
}
```

- `agents.defaults.skills`：未在 `list` 中特別宣告的 Agent 皆會繼承此預設白名單。（若連此項也省略，未設定的 Agent 即為存取無限制）
- `agents.list[].skills`：針對特定 Agent 覆寫白名單設定，以達成隔離。若設為 `[]`，則代表此 Agent 被徹底拔除所有擴充技能。

## 2. 斜線指令系統與權限設定 (Commands)

Gateway 支援透過對話框下達以 `/` 或 `!` 開頭的斜線指令（如 `/think`, `/skill`, `/bash`）。這些指令可以直接操控底層行為，甚至牽涉系統環境變數與核心設定，因此必須嚴格配管權限。

下方是一個完整的 `commands` 設定範例：

```json
{
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "text": true,
    "bash": false,
    "bashForegroundMs": 2000,
    "config": false,
    "mcp": false,
    "plugins": false,
    "debug": false,
    "restart": true,
    "ownerAllowFrom": ["discord:123456789012345678"],
    "ownerDisplay": "raw",
    "ownerDisplaySecret": "${OWNER_ID_HASH_SECRET}",
    "allowFrom": {
      "*": ["user1"],
      "discord": ["user:123"]
    },
    "useAccessGroups": true
  }
}
```

### 2.1 介面與行為開關 (Features)

- `commands.text` (預設 `true`)：允許系統解析一般訊息字串中的 `/` 指令（支援 Line, WhatsApp 等純文字平台）。
- `commands.native` (預設 `"auto"`)：是否向 Discord/Telegram 等平台自動註冊原生的「斜線指令 (Slash Commands)」輔助選單。
- `commands.nativeSkills` (預設 `"auto"`)：是否將已載入的 Skills 自動整合至原生斜線指令選單（例如能在 Discord 輸入框直接看到 `/技能名稱`）。

### 2.2 系統控制與擴充套件 (System & Plugins)

開啟下列功能可透過對話框即時操作伺服器，**強烈建議配合設定 `ownerAllowFrom` 來防堵風險**：

- `commands.config` (預設 `false`)：啟用 `/config` 指令，允許讀寫 `openclaw.json`。
- `commands.plugins` (預設 `false`)：啟用 `/plugins` 指令，用於安裝或停用擴充套件外掛。
- `commands.mcp` (預設 `false`)：啟用 `/mcp` 指令，用於管理 Model Context Protocol 伺服器組態。
- `commands.restart` (預設 `true`)：啟用 `/restart` 指令，允許直接從對話框重新啟動 Gateway 服務。
- `commands.debug` (預設 `false`)：啟用 `/debug` 指令，用於執行階段 (Runtime) 的除錯覆寫。

### 2.3 底層系統執行 (Bash Execution)

- `commands.bash` (預設 `false`)：**危險操作**。允許使用 `/bash <cmd>` 或 `! <cmd>` 讓模型或擁有者直接執行伺服器作業系統底層的 Shell 指令。
- `commands.bashForegroundMs` (預設 `2000`)：控制 Bash 指令執行多久後，若尚未結束，即轉入背景作業（預設 2 秒；若設為 `0` 則立即背景執行）。

### 2.4 防火牆與權限白名單 (Allowlist & Owners)

為了防止非授權用戶任意操控系統：

- **嚴格全域白名單 (`commands.allowFrom`)**：一旦設定，**只有該名單內的使用者有資格觸發「任何」指令**，並會凌駕覆寫其他權限規則。支援按平台篩選（如 `"discord": ["user:123"]`）或使用 `"*"` 設定通用白名單。
- **存取群組 (`commands.useAccessGroups`)** (預設 `true`)：若未設定上述全域白名單，則根據頻道專屬的白名單與配對邏輯來決定是否允許指令。
- **系統最高權限 (`commands.ownerAllowFrom`)**：此為專門用來鎖定 `/config`, `/plugins`, `/debug` 等最高層級系統改動的最後防線。請填入您的唯一身分識別碼（如 `discord:123456789012345678`）以確保只有您能修改設定。
- **擁有者 ID 遮罩**：`ownerDisplay` 搭配 `ownerDisplaySecret`，控制你的擁有者 ID 在傳遞給模型時，是維持明碼（`"raw"`）還是以加密雜湊轉換（`"hash"`）來保護真實身分。
