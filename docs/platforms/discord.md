# 🦞 OpenClaw  Discord 全功能安裝與配置指南

本指南適用於 Docker 環境下架設的 OpenClaw 系統。

> **文件版本資訊**：本指南依據 [OpenClaw 官方文件](https://docs.openclaw.ai/channels/discord) 最新內容整理而成（最後同步更新日期：2026 年 4 月 4 日）。

## 1. 第一階段：Discord 開發者後台 (準備工作)

1. **建立 App**：前往 [Discord Developer Portal](https://discord.com/developers/applications) -> New Application。
2. **獲取 Bot Token**：在左側選單進入「Bot」頁面，點擊 `Reset Token`。
3. **開啟特權 (Intents)**：同樣在「Bot」頁面向下捲動找到「Privileged Gateway Intents」區塊，務必開啟以下特權：

    - **Message Content Intent (必開)**：最重要！沒開的話機器人會無法讀取頻道的訊息內容，直接變成聾子。
    - **Server Members Intent (建議開啟)**：如果您未來需要透過「身分組(roles)」設定白名單，或者需要讓機器人能讀取用戶名稱，就需要開啟此設定。
    - **Presence Intent (選用)**：若您想開啟自訂的動態狀態功能（例如「正在玩遊戲...」、「正在直播...」），則必須開啟此選項。

4. **產生邀請連結並將機器人加入伺服器**：點擊左側選單的 `OAuth2`，我們將帶有正確權限的邀請網址將機器人加入伺服器。

    - 向下捲動到「OAuth2 URL Generator」並勾選：`bot` 與 `applications.commands`。
    - 勾選 `bot` 後，下方會出現「Bot Permissions」區塊。官方建議勾選以下權限：`View Channels`, `Send Messages`, `Read Message History`, `Embed Links`, `Attach Files` (可選 `Add Reactions`)。

      > 💡 **實戰建議**：為了方便，您也可以**直接在這區塊勾選 `Administrator`** 來獲得完整權限。

    - 複製最下方產生的邀請網址 (Generated URL)，將其貼上至瀏覽器並打開，選擇您的伺服器後點擊「繼續」進行連接。此時您應該就能在伺服器中看到您的機器人了。

      > 💡 **這邊設定不會保存**：這頁只是一個「網址計算機」，勾選狀態不會被保存！權限的設定都會包含在您剛剛複製的邀請網址中。

5. **開啟開發者模式與複製 ID**：回到 Discord 應用程式內，您需要開啟「開發者模式」以便取得內部 ID：

    - 點擊左下角的齒輪圖示 (使用者設定) -> 「進階 (Advanced)」 -> 開啟「開發者模式 (Developer Mode)」。
    - 對著左側列表的**您的伺服器圖示**點擊右鍵 -> 選擇「複製伺服器 ID」(Copy Server ID)。
    - 點擊聊天頻道的**您的個人頭像**按右鍵 -> 選擇「複製用戶 ID」(Copy User ID)。
    - **請將此 Server ID、User ID 與先前的 Bot Token 一起妥善保存**，這三個資訊在下一個階段馬上會用到。

## 2. 第二階段：設定 OpenClaw 通道並啟動

為了讓 OpenClaw 能夠接上 Discord，我們必須將 Token 與 ID 餵給系統並啟動服務。請選擇以下任一方式進行：

### 方法 A：使用自然語言對著 Agent 下達指令 (官方最推薦)

基於安全性考量，這段 Token **絕對不可在對話中直接傳給機器人**。但我們可以先把 Token 藏在主機裡，剩下的繁瑣設定交給 Agent 自己搞定：

1. **安全存放 Token**：打開您宿主機的 `.env` 檔案，補上您的 Bot Token：

    ```bash
    DISCORD_BOT_TOKEN="你的_BOT_TOKEN"
    ```

2. **重啟或啟動服務**：讓 OpenClaw 重啟並載入新的環境變數：

    ```bash
    docker compose up -d
    ```

3. **讓 Agent 自動完成配置**：對著您的 OpenClaw 網頁端或終端機介面，貼上這句魔法指令讓它幫您打通頻道：

    > 「我已經在 `.env` 中設定好了 Discord Bot Token。請幫我啟用 Discord 通道，並且我的 User ID 是 **<你的_USER_ID>**，Server ID 是 **<你的_SERVER_ID>**，請幫我將它們都加入伺服器配置中。」

### 方法 B：傳統手動 CLI 變數設定 (適合除錯使用)

若您的 Agent 暫時無法對話或您喜歡純 CLI 修改，可以直接將所有變數打入 Docker 環境中：

1. **將資訊全數加入 `.env` 檔案**：

    ```bash
    DISCORD_BOT_TOKEN="你的_BOT_TOKEN"
    DISCORD_USER_ID="你的_USER_ID"
    DISCORD_SERVER_ID="你的_SERVER_ID"
    ```

2. **啟動容器**：讓 OpenClaw 讀取剛剛寫入的最新設定。

    ```bash
    docker compose up -d
    ```

3. **進入容器執行配置指令**：

    ```bash
    # 啟用 Discord 通道
    docker exec -it openclaw-gateway openclaw config set channels.discord.enabled true --strict-json

    # 將 Token 與 ID 連結至環境變數
    docker exec -it openclaw-gateway openclaw config set channels.discord.token --ref-provider default --ref-source env --ref-id DISCORD_BOT_TOKEN
    docker exec -it openclaw-gateway openclaw config set channels.discord.users.default --ref-provider default --ref-source env --ref-id DISCORD_USER_ID
    docker exec -it openclaw-gateway openclaw config set channels.discord.guilds.default --ref-provider default --ref-source env --ref-id DISCORD_SERVER_ID
    ```

## 3. 第三階段：身分核准與配對 (Pairing)

1. **私訊機器人**：在 Discord 私訊 (DM) 你的機器人隨便一句話。

    > ⚠️ **重要前提**：請確保您在 Discord 的帳號隱私設定中，**允許來自該伺服器成員的私人訊息**，否則您將無法收到機器人傳來的配對碼。

2. **取得配對碼**：機器人會回傳一組 Pairing Code。
3. **核准配對**：

    - **方法 A (對著現有機器人說)**：核准這個 Discord 配對碼： `<CODE>`
    - **方法 B (使用 CLI)**：

      ```bash
      docker exec -it openclaw-gateway openclaw pairing approve discord <CODE>
      ```

## 4. 第四階段：進階 - 建立伺服器工作區 (Workspace)

當私訊 (DM) 成功運作後，非常推薦將您的 Discord 伺服器設定為**完整工作區**（特別適合專屬您與機器人的私人伺服器）。

要完成這些設定，請依據您的喜好，選擇**「跟 Agent 對話」**或是**「寫入 CLI (Config)」**來完成配置：

1. **加入伺服器白名單 (Guild Allowlist)**

    這能讓機器人跳脫私訊，在您的伺服器頻道內合法回應。OpenClaw 預設的防止濫用機制非常嚴格，只有在白名單內的伺服器才能使用：

      - **向 Agent 說**：「請把我的 Discord 伺服器 ID `<您的公會 ID>` 加入公會白名單中。」
      - **透過 CLI (預設嚴格模式)**：

        ```bash
        docker exec -it openclaw-gateway openclaw config set channels.discord.guilds."<您的公會 ID>".users '["<您的 User ID>"]' --strict-json
        ```

        > 💡 **進階設定 (全域開放 vs 鎖定使用者)**
        > 
        > 如果您覺得每個公會都要設定太麻煩，您也可以將 `channels.discord.groupPolicy` 設為 `"open"` (允許在所有加入的伺服器運作)。
        > 同時強烈建議搭配設定 `channels.discord.allowFrom` 全域黑白名單，只填寫您自己的 User ID。這樣一來，不管機器人被拉去哪個伺服器，它都**只會聽您一個人的話**！

2. **取消 `@標註` 限制 (Allow responses without @mention)**
  
    預設機器人只會在被標註 `@mention` 時理人。對於私人專屬伺服器，您會希望能直接對話：

      - **向 Agent 說**：「請允許機器人在這個伺服器上，不需要被 @標註 也可以直接回應我。」
      - **透過 CLI**：

        ```bash
        docker exec -it openclaw-gateway openclaw config set channels.discord.guilds."<您的公會 ID>".requireMention false --strict-json
        ```

3. **頻道記憶橋接 (Plan for memory)**
  
    在伺服器頻道中，Agent 預設**不會**主動載入您的長期記憶檔 (`MEMORY.md`) 以節省資源。針對這個邏輯，您必須主動給予 Agent 指導原則：

      - **向 Agent 說 (或手動加入 Prompt)**：「當我在 Discord 頻道問問題時，如果你需要長期上下文，請主動使用 `memory_search` 或 `memory_get` 從 `MEMORY.md` 獲取資訊。」

> 💡 **開始聊天！**
> 設定完成後，您可以建立像是 `#coding`、`#home`、`#research` 等不同的頻道。機器人會辨識頻道名稱，並且**每個頻道都會擁有完全獨立與隔離的對話工作階段 (Session)**，完美貼合您的工作流！

## 5. 底層對話模型運作邏輯 (Runtime Model)

深入了解 OpenClaw 處理 Discord 對話的系統底層邏輯：

1. **Connection**：OpenClaw Gateway 原生接管並擁有 Discord 連線。
2. **Reply Routing (確定性回覆)**：回覆路由是具有確定性的——從 Discord 接收的訊息必定回覆至原 Discord 頻道。
3. **私聊共用主記憶 (DM Scope)**：預設情況下 (`session.dmScope=main`)，私訊 (DM) 永遠共用 Agent 的主對話記憶區塊 (`agent:main:main`)。
4. **頻道上下文隔離 (Isolated Channels)**：伺服器頻道的每次對話，都會拆分成獨立的 Session Key (`agent:<agentId>:discord:channel:<channelId>`)，藉此隔離不同頻道的上下文。
5. **預設忽略群組 (Group DMs)**：群組私聊預設是忽略不處理的 (`channels.discord.dm.groupEnabled=false`)。
6. **Slash 指令隔離**：原生的斜線指令 (`/`) 會在獨立的環境中執行 (`agent:<agentId>:discord:slash:<userId>`)，但它會帶著 `CommandTargetSessionKey`，將結果漂亮地送回您目前所屬的對話頻道中。

## 6. Feature details

根據官方文件，OpenClaw 對 Discord 還支援以下強大功能，可透過設定檔或 CLI 開啟：

- **串流回覆 (Live Stream Preview)**：設定 `channels.discord.streaming`
  - `"off"` (預設)：預設保持關閉。因為 Discord 的預覽編輯很容易觸發速率限制 (Rate limits)——特別是當多台機器人或 Gateway 共用相同的帳號或公會流量時。
  - `"progress"`：為了支援跨頻道 (Cross-channel) 的對齊一致性而允許此值，在 Discord 底層實際上映射到 `partial` 模式。
  - `"partial"`：隨著 Token 抵達，會針對單一預覽訊息 (preview message) 不斷進行編輯更新。
  - `"block"`：會送出草稿區塊大小 (draft-sized chunks) 的訊息（可使用 `draftChunk` 參數來微調區塊長度與斷點）。
