# 擴充技能權限與系統指令配置 (openclaw.json)

對於 Gateway 的持有者來說，我們需要透過主設定檔 `~/.openclaw/openclaw.json` 來控制哪些技能可以被誰使用，以及要注入哪些環境變數。

> **💡 新手導讀：如何獲取或撰寫技能？**
>
> 在您開始進行權限配置之前，若您還不清楚如何撰寫擴充技能，或者想知道如何管理技能（下載 / 更新），請先參閱以下資源：
>
> 1. **架構原理解析**：請見 [LLM-notes: Skills 與 ClawHub 架構概念](https://github.com/kaka-lin/LLM-notes/blob/main/OpenClaw/concepts/skills-and-clawhub.md)
> 2. **開發自訂技能**：請參考官方教學 [Creating Skills (docs.openclaw.ai)](https://docs.openclaw.ai/tools/creating-skills)
> 3. **管理技能 (Install/Update)**：請參考官方教學 [Skills & ClawHub (docs.openclaw.ai)](https://docs.openclaw.ai/tools/skills)
>
> 本文主要聚焦於技能載入後的**「權限管控、Agent 隔離與環境變數注入」**。

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
          "GEMINI_API_KEY": "${GEMINI_API_KEY}"
        }
      }
    }
  }
}
```

### 1.1 注入 API Keys (`skills.entries`)

這是 Gateway 最常用到的功能。當您從 ClawHub 下載了某個第三方技能，該技能通常缺乏它所需的外部 API 金鑰。為了安全，我們**絕對不要**把金鑰寫在 `SKILL.md` 的提示詞裡面，而是透過 `skills.entries.<skillKey>.env` 的方式動態注入至該次啟動的環境中。

> **🔒 安全建議：使用環境變數替換**
> 請如上方範例使用 `"${GEMINI_API_KEY}"` 的語法。系統啟動時會自動從 `.env` 檔案中讀取對應的數值並進行替換，這樣能避免將明碼密碼直接存放在 `openclaw.json` 中並被意外推送到 Git。

### 1.2 技能自動載入與 Agent 權限隔離

**預設情況（自動載入，全域可用）：**
只要將 Skill 腳本放入 `~/.openclaw/skills` 或是 `<workspace>/skills` 等預設目錄，系統即會自動載入。**如果未在設定檔中做任何限制，所有的 Agent 預設皆可存取並使用這些技能。** 此設定適合單純的個人使用情境，無需額外配置即可享受擴充功能。

**進階情況（權限管控與隔離）：**

> 👉 **架構原理解析**：若想了解為什麼 OpenClaw 採用「全域安裝 + 設定檔隔離」而不是把技能實體丟進個別 Agent 資料夾，請參閱：[LLM-notes: 架構設計 - 全域安裝與 Agent 權限隔離](https://github.com/kaka-lin/LLM-notes/blob/main/OpenClaw/concepts/skills-and-clawhub.md#4-架構設計全域安裝與-agent-權限隔離)。

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

## 2. Python 技能環境支援 (Miniconda)

OpenClaw 官方的 Docker 映像檔預設僅提供 Node.js 與 Bash 執行環境。若您的技能腳本是用 Python 撰寫的，直接執行將會遇到找不到 `python` 指令的錯誤。

為了解決這個問題，本專案特別客製化了 `Dockerfile`，在官方基底映像檔之上加入了 **Miniconda** 環境：

- **內建跨平台 Python 支援**：`Dockerfile` 會自動根據 Host 主機的系統架構（x86_64 或 ARM64）下載並安裝對應的 Miniconda，並將指令加入 `PATH`。
- **使用者權限轉移**：所有的 Conda 資料夾權限已轉交給背景執行的 `node` 使用者。這代表您可以隨時使用 `docker compose exec openclaw-gateway bash` 進入容器，並直接使用 `pip install -r requirements.txt` 來為您的 Python 技能安裝第三方套件，而不會遇到權限阻擋。

透過這個機制，您的 Agent 就可以毫無障礙地調用任何 Python 撰寫的擴充能力了！

## 3. 斜線指令系統與權限設定 (Commands)

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

### 3.1 介面與行為開關 (Features)

- `commands.text` (預設 `true`)：允許系統解析一般訊息字串中的 `/` 指令（支援 Line, WhatsApp 等純文字平台）。
- `commands.native` (預設 `"auto"`)：是否向 Discord/Telegram 等平台自動註冊原生的「斜線指令 (Slash Commands)」輔助選單。
- `commands.nativeSkills` (預設 `"auto"`)：是否將已載入的 Skills 自動整合至原生斜線指令選單（例如能在 Discord 輸入框直接看到 `/技能名稱`）。

### 3.2 系統控制與擴充套件 (System & Plugins)

開啟下列功能可透過對話框即時操作伺服器，**強烈建議配合設定 `ownerAllowFrom` 來防堵風險**：

- `commands.config` (預設 `false`)：啟用 `/config` 指令，允許讀寫 `openclaw.json`。
- `commands.plugins` (預設 `false`)：啟用 `/plugins` 指令，用於安裝或停用擴充套件外掛。
- `commands.mcp` (預設 `false`)：啟用 `/mcp` 指令，用於管理 Model Context Protocol 伺服器組態。
- `commands.restart` (預設 `true`)：啟用 `/restart` 指令，允許直接從對話框重新啟動 Gateway 服務。
- `commands.debug` (預設 `false`)：啟用 `/debug` 指令，用於執行階段 (Runtime) 的除錯覆寫。

### 3.3 底層系統執行 (Bash Execution)

- `commands.bash` (預設 `false`)：**危險操作**。允許使用 `/bash <cmd>` 或 `! <cmd>` 讓模型或擁有者直接執行伺服器作業系統底層的 Shell 指令。
- `commands.bashForegroundMs` (預設 `2000`)：控制 Bash 指令執行多久後，若尚未結束，即轉入背景作業（預設 2 秒；若設為 `0` 則立即背景執行）。

### 3.4 防火牆與權限白名單 (Allowlist & Owners)

為了防止非授權用戶任意操控系統：

- **嚴格全域白名單 (`commands.allowFrom`)**：一旦設定，**只有該名單內的使用者有資格觸發「任何」指令**，並會凌駕覆寫其他權限規則。支援按平台篩選（如 `"discord": ["user:123"]`）或使用 `"*"` 設定通用白名單。
- **存取群組 (`commands.useAccessGroups`)** (預設 `true`)：若未設定上述全域白名單，則根據頻道專屬的白名單與配對邏輯來決定是否允許指令。
- **系統最高權限 (`commands.ownerAllowFrom`)**：此為專門用來鎖定 `/config`, `/plugins`, `/debug` 等最高層級系統改動的最後防線。請填入您的唯一身分識別碼（如 `discord:123456789012345678`）以確保只有您能修改設定。
- **擁有者 ID 遮罩**：`ownerDisplay` 搭配 `ownerDisplaySecret`，控制你的擁有者 ID 在傳遞給模型時，是維持明碼（`"raw"`）還是以加密雜湊轉換（`"hash"`）來保護真實身分。
