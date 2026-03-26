# Telegram 整合指引

本目錄用於管理 OpenClaw 的 Telegram Messaging Platform 配置與筆記。

## 🚀 串接步驟

### 1. 向 @BotFather 申請 Bot Token

1. 在 Telegram 中搜尋並開啟 [@BotFather](https://t.me/botfather)。
2. 發送下面指令：

    ```sh
    /start
    /newbot
    ```

3. 依照指示設定：

    - Bot Name: 顯示名稱
    - Bot Username: 帳號名稱（結尾必須是 bot）

4. 你會拿到 **API Token**，存下來：

    ```sh
    HTTP API Token
    例如：
    123456:ABC-XYZ...
    ```

### 2. 取得你的 Chat ID

1. 在 Telegram 中搜尋並開啟你的 Bot。
2. 點選「Start」，然後隨意打一段訊息，例如：`hello`
3. 透過瀏覽器開啟或在終端機執行以下網址（需先暫停 OpenClaw 伺服器，以免它把訊息收走）：

    ```bash
    curl https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
    ```

    你會在回傳的 JSON `result` 陣列中看到你的 Chat ID，類似這樣：

    ```json
    {
        "result": [
            {
                "message": {
                    "chat": {
                        "id": 123456789
                    }
                }
            }
        ]
    }
    ```

### 3. 在 OpenClaw 設定 Telegram

請在專案根目錄執行以下指令（將 `<YOUR_TOKEN>` 替換為上一步取得的 Token）：

```bash
docker compose run --rm openclaw-cli channels add --channel telegram --token "<YOUR_TOKEN>"
```

執行完成後，請重啟 Gateway 以啟用新頻道：

```bash
docker compose restart openclaw-gateway
```

### 4. 測試連線是否成功

預設情況下，OpenClaw 接上 Channel 後，會自動將收到的訊息導向內建的代理人 (Agent) 處理。

1. **開啟 Gateway 即時日誌**：

    在終端機輸入以下指令並保持開啟，這樣你能看到伺服器的反應：

    ```bash
    docker compose logs -f openclaw-gateway
    ```

2. **發送測試訊息**：

    打開 Telegram，對你的 Bot 說：「你好！這是一個測試。」

3. **首次通訊配置（重要！）**：

    由於 OpenClaw 有安全性設計，如果是第一次對話，Telegram Bot 會回覆你：

    ```text
    OpenClaw: access not configured.
    Your Telegram user id: 123456789
    Pairing code: ABCXYZ

    Ask the bot owner to approve with:
    openclaw pairing approve telegram ABCXYZ
    ```

4. **在終端機核准配對**：

    把 Bot 給你的這行指令，加上 `docker compose run --rm openclaw-cli` 的前綴即可完成授權：

    ```bash
    # 把下方的 ABCXYZ 換成你收到的 Pairing code
    docker compose run --rm openclaw-cli pairing approve telegram ABCXYZ
    ```

    核准成功後，你在 Telegram 再輸入一次問題，就能收到正常的 AI 回覆了！

> [!TIP]
> 如果你的 `openclaw-gateway` 用大寫紅字報錯，通常是因為你在 `.env` 裡面的 LLM API Key (如 Anthropic, OpenAI 或 Gemini) 還沒有填寫。如果有遇到問題，請先檢查 LLM 金鑰。
