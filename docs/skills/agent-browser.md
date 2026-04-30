# 擴充技能：agent-browser 安裝指南

> [!NOTE]
> **架構選擇提示**
> OpenClaw 本身已具備**內建的 Browser 工具**（本專案預設推薦方案，可連線至 [Mac Host Chrome](../guides/browser-control.md)）。
> 本文介紹的是**另一種替代方案（第三方擴充技能）**：透過安裝 Vercel 的 `agent-browser` 技能，直接在 Docker 容器內部運行 headless 瀏覽器。若您的部署環境是純 Server（無法橋接 Mac 主機），即可安裝此技能來賦予 Agent 瀏覽網頁的能力。

本文旨在記錄如何將 [agent-browser](https://agent-browser.dev/) 技能整合進基於 Docker 的 OpenClaw Server 環境中，並解釋其核心架構概念。

## 1. `agent-browser` 安裝流程 (Docker 環境)

由於 OpenClaw 運行在隔離的容器中，必須在容器內部完成驅動安裝與路徑授權。

### 1.1 第一步：安裝全域驅動程式

必須以 `root` 身份進入容器，才能修改系統路徑：

```bash
# 進入容器
docker compose exec --user root openclaw-gateway sh

# 安裝驅動與 Chrome 瀏覽器
npm install -g agent-browser
agent-browser install --allow-root
```

### 1.2 第二步：路徑授權與數據遷移

OpenClaw 的背景服務是以 `node` 使用者身份運行，需要將瀏覽器權限下放：

```bash
# 建立共用目錄並搬移瀏覽器
mkdir -p /home/node/.agent-browser
cp -r /root/.agent-browser/* /home/node/.agent-browser/

# 修正權限歸屬
chown -R node:node /home/node/.agent-browser
```

### 1.3 第三步：導入 Vercel Skills

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

## 2. 驗證與使用

安裝完成後，你可以透過以下指令測試連動是否成功：

```bash
# 列出所有技能，確認 agent-browser 為 "ready" 狀態
docker compose run --rm openclaw-cli skills list

# 實際下達瀏覽器任務
docker compose run --rm openclaw-cli agent --agent main --message "去搜尋台灣今日即時新聞"
```

## 3. 實作成果

在成功整合後，當你要求 Agent 訪問網頁時，它不再只是提供連結，而是會真正啟動後端的 Chromium 進行網頁解析並回傳摘要。
