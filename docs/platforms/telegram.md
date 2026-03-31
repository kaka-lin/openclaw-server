# Telegram 整合指引

本目錄用於管理 OpenClaw 的 Telegram Messaging Platform 配置與筆記。

## 1. 使用 @BotFather 建立 Bot

1. 在 Telegram 中搜尋並開啟 [@BotFather](https://t.me/botfather)。
2. 發送下面指令：

    ```sh
    /start
    /newbot
    ```

3. 依照指示完成設定：
    - **Bot Name**: 顯示名稱
    - **Bot Username**: Bot 帳號名稱，且名稱結尾必須為 `bot`

4. 建立完成後，BotFather 會提供一組 **HTTP API Token**。

    ```sh
    HTTP API Token
    例如：
    123456:ABC-XYZ...
    ```

## 2. 取得 Telegram Chat ID

1. 在 Telegram 中搜尋並開啟你的 Bot。
2. 點選「Start」，然後隨意打一段訊息，例如：

    ```bash
    hello
    ```

3. 在終端機執行以下指令：

    ```bash
    curl https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
    ```

4. 在回傳的 JSON 中，找到 result[].message.chat.id，這個值就是你的 Chat ID。
  
    範例如下：

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

## 3. 在 OpenClaw 中加入 Telegram Channel

請在專案根目錄執行以下指令，並將 `<YOUR_TOKEN>` 替換為前一步取得的 Bot Token：

```bash
docker compose run --rm openclaw-cli channels add --channel telegram --token "<YOUR_TOKEN>"
```

完成後，重新啟動 Gateway 以套用新設定：

```bash
docker compose restart openclaw-gateway
```

## 4. 測試連線是否成功

OpenClaw 接上 Channel 後，預設會將收到的訊息導向內建 Agent 處理。

1. 先開啟 Gateway 即時日誌：

    ```bash
    docker compose logs -f openclaw-gateway
    ```

2. 在 Telegram 中對 Bot 發送一則測試訊息，例如：

    ```bash
    你好！這是一個測試。
    ```

3. **首次通訊配置（重要！）**：

    由於 OpenClaw 有安全性設計，如果是第一次對話，Telegram Bot 會回覆你：

    ```text
    OpenClaw: access not configured.
    Your Telegram user id: 123456789
    Pairing code: ABCXYZ

    Ask the bot owner to approve with:
    openclaw pairing approve telegram ABCXYZ
    ```

4. **請回到終端機執行以下指令完成授權：**：

    把 Bot 給你的這行指令，加上 `docker compose run --rm openclaw-cli` 的前綴即可完成授權：

    ```bash
    # 把下方的 ABCXYZ 換成你收到的 Pairing code
    docker compose run --rm openclaw-cli pairing approve telegram ABCXYZ
    ```

    核准成功後，你在 Telegram 再輸入一次問題，就能收到正常的 AI 回覆了！

  > [!TIP]
  > 如果你的 `openclaw-gateway` 用大寫紅字報錯，通常是因為你在 `.env` 裡面的 LLM API Key (如 Anthropic, OpenAI 或 Gemini) 還沒有填寫。如果有遇到問題，請先檢查 LLM 金鑰。
