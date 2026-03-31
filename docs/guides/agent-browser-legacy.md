# OpenClaw 整合 agent-browser 安裝與指南

本文旨在記錄如何將 Vercel Labs 的 [agent-browser](https://skills.sh/vercel-labs/agent-browser/agent-browser) 技能整合進基於 Docker 的 OpenClaw Server 環境中，並解釋其核心架構概念。

## 1. 核心概念：Agent 與 Session

### 1.1 什麼是 Agent (代理人)？

在 OpenClaw 中，**Agent** 是一個具備獨立能力的「認知單元」。你可以想像它是一個虛擬的機器人，擁有：

- **Identity (身份)**：自己的名字與性格設定。

- **Brain (模型)**：指定的 LLM 模型（如 Claude 3.5, Gemini 1.5）。

- **Workspace (工作空間)**：獨立的檔案儲存區。

- **Skills (技能)**：它被授權使用的工具清單（如：發送訊息、查詢天氣、操作瀏覽器）。

### 1.2 為何需要 `--agent main`？

`main` 是 OpenClaw 初始化時自動生成的預設 Agent ID。

當你執行命令時，必須指名由哪位 Agent 來處理。指定 `--agent main` 就是告訴系統：「請讓我的首席助理 `main` 來執行這個任務。」

## 2. `agent-browser` 安裝流程 (Docker 環境)

由於 OpenClaw 運行在隔離的容器中，必須在容器內部完成驅動安裝與路徑授權。

### 2.1 第一步：安裝全域驅動程式

必須以 `root` 身份進入容器，才能修改系統路徑：

```bash
# 進入容器
docker compose exec --user root openclaw-gateway sh

# 安裝驅動與 Chrome 瀏覽器
npm install -g agent-browser
agent-browser install --allow-root
```

### 2.2 第二步：路徑授權與數據遷移

OpenClaw 的背景服務是以 `node` 使用者身份運行，需要將瀏覽器權限下放：

```bash
# 建立共用目錄並搬移瀏覽器
mkdir -p /home/node/.agent-browser
cp -r /root/.agent-browser/* /home/node/.agent-browser/

# 修正權限歸屬
chown -R node:node /home/node/.agent-browser
```

### 2.3 第三步：導入 Vercel Skills

這一步會將瀏覽器的操作指令（SKILL.md）存入 OpenClaw 的大腦索引中：

```bash
# 切換到 Workspace 目錄
cd /home/node/.openclaw/workspace

# 執行 Vercel 官方安裝指令
# 提示：在互動選單中，Agent 請選擇 "OpenClaw"，Scope 選擇 "Project"，Method 選擇 "Copy"。
npx skills add https://github.com/vercel-labs/agent-browser --skill agent-browser

# 最後一步修復 Workspace 權限
chown -R node:node /home/node/.openclaw/workspace
exit
```

## 3. 驗證與使用

安裝完成後，你可以透過以下指令測試連動是否成功：

```bash
# 列出所有技能，確認 agent-browser 為 "ready" 狀態
docker compose run --rm openclaw-cli skills list

# 實際下達瀏覽器任務
docker compose run --rm openclaw-cli agent --agent main --message "去搜尋台灣今日即時新聞"
```

## 4. 實作成果

在成功整合後，當你要求 Agent 訪問網頁時，它不再只是提供連結，而是會真正啟動後端的 Chromium 進行網頁解析並回傳摘要。
