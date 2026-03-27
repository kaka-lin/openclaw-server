# OpenClaw APIs 呼叫指南

本文件旨在提供 OpenClaw 伺服器的 API 呼叫規格，方便其他程式（如 Python, Node.js 或透過 Webhook）與你的 OpenClaw 實例進行互動。

## ⚙️ 伺服器配置 (Server Configuration)

在呼叫 API 之前，您需要透過 CLI 啟用對應的 HTTP 端點。

### 使用 CLI 啟用

您可以執行以下指令來快速開啟端點，不需手動編輯 JSON 檔案：

```bash
# 1. 啟用 OpenAI 相容 API (/v1/chat/completions)
docker compose run --rm openclaw-cli \
  config set gateway.http.endpoints.chatCompletions.enabled true --strict-json

# 2. 啟用 OpenResponses API (/v1/responses)
docker compose run --rm openclaw-cli \
  config set gateway.http.endpoints.responses.enabled true --strict-json

# 3. 重啟 Gateway 以套用設定
docker compose restart openclaw-gateway
```

### 手動檢查配置

設定成功後，您的 `~/.openclaw/openclaw.json`應包含如下結構：

```json
{
  "gateway": {
    "http": {
      "endpoints": {
        "responses": { "enabled": true },
        "chatCompletions": { "enabled": true }
      }
    }
  }
}
```

## 🔑 身份驗證 (Authentication)

所有 API 呼叫皆需透過 `Authorization` 標頭提供 Token。

```bash
Authorization: Bearer <TOKEN>
```

- **Token 來源**：請查看專案根目錄下的 `.env` 檔案中的 `OPENCLAW_GATEWAY_TOKEN` 值。

---

## 🚀 API 端點介紹

### 1. OpenAI Chat Completions

此端點旨在相容 OpenAI 的原生客戶端 (如 Open WebUI 等)，同時保留 OpenClaw「Agent 優先」的路由設計。

```bash
POST /v1/chat/completions
```

or

```bash
http://<gateway-host>:<port>/v1/chat/completions
```

#### Examples

- **Curl 範例**:
  - **Non-streaming**:

    ```bash
    curl -sS http://127.0.0.1:18789/v1/chat/completions \
      -H "Authorization: Bearer <TOKEN>" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "openclaw/default",
        "messages": [{"role": "user", "content": "測試內容"}],
      }'
    ```

  - **Streaming**:

    ```bash
    curl -N http://127.0.0.1:18789/v1/chat/completions \
      -H "Authorization: Bearer <TOKEN>" \
      -H "Content-Type: application/json" \
      -H 'x-openclaw-model: openai/gpt-5.4' \
      -d '{
        "model": "openclaw/research",
        "messages": [{"role": "user", "content": "測試內容"}],
        "stream": true
      }'
    ```

    > [!TIP]
    > **Curl 指令技巧**：
    > - `-sS`：隱藏進度條 (silent)，但若發生錯誤則顯示 (show-error)。適合用在腳本或日誌中。
    > - `-N`：停用緩衝 (no-buffer)。這對於 **Streaming (串流)** 至關重要，能確保數據一到達即刻顯示。
  
  - List models:

    ```bash
    curl -sS http://127.0.0.1:18789/v1/models \
      -H 'Authorization: Bearer YOUR_TOKEN'
    ```

- **Python (requests) 範例**:
  - **Non-streaming**:

    ```python
    import requests

    headers = {
      "Authorization": "Bearer <TOKEN>",
      "Content-Type": "application/json",
    }

    payload = {
      "model": "openclaw/default",
      "messages": [{"role": "user", "content": "測試內容"}],
    }

    response = requests.post(
        "http://127.0.0.1:18789/v1/chat/completions", 
        headers=headers, 
        json=payload
    )
    print(response.json())
    ```

  - **Streaming**:

    ```python
    import requests
    import json

    headers = {
      "Authorization": "Bearer <TOKEN>",
      "Content-Type": "application/json",
      "x-openclaw-model": "openai/gpt-5.4"
    }

    payload = {
      "model": "openclaw/research",
      "messages": [{"role": "user", "content": "測試內容"}],
      "stream": true
    }

    response = requests.post(
        "http://127.0.0.1:18789/v1/chat/completions", 
        headers=headers, 
        json=payload, 
        stream=True
    )
    for line in response.iter_lines():
        if line:
            decoded_line = line.decode('utf-8')
            if decoded_line.startswith('data: '):
                content = decoded_line[6:]
                if content == '[DONE]':
                    break
                print(json.loads(content))
    ```

#### OpenAI 詳細技術規格 (Detailed Specification)

- **支援的 Endpoints**:
  - `POST /v1/chat/completions`
  - `GET /v1/models` (列出可用模型/Agent)
  - `GET /v1/models/{id}`
  - `POST /v1/embeddings`

- **模型路由 (Model Routing)**：
  - 傳入 `model: "openclaw"` 或 `model: "openclaw/default"`：路由至系統預設配置的 Agent。
  - 傳入 `model: "openclaw/<agentId>"`：路由至特定的 Agent (例如 `openclaw/coding`)。

- **專屬 HTTP 標頭 (Special Headers)**：
  - `x-openclaw-model`：覆寫底層實際呼叫的 OpenAI 模型名稱。
  - `x-openclaw-agent-id`：強制指定 Agent ID，覆蓋 Payload 設定。
  - `x-openclaw-session-key`：指定並固定 Session Key 以延續對話上下文。
  - `x-openclaw-message-channel`：用於模擬特定平台 (如 Slack, Telegram) 的行為表現。

- **請求參數 (Request Shape)**：
  完全相容標準 OpenAI 規格。但若深入至 OpenClaw 引擎處理層面，其支援與忽略的進階參照**等同於 OpenResponses API**：
  
  - **支援**：`input` (對應 `messages`), `instructions`, `tools`, `tool_choice`, `stream`, `max_output_tokens`, `user`。
  - **忽略**：`max_tool_calls`, `reasoning`, `metadata`, `store`, `truncation`。

  *(註：若請求包含 `"user"` 欄位或提供 Session Header，系統會自動維持 Sticky Session)*

### 2. OpenResponses API

支援更精簡的 `input` 結構，回傳結構也較為單純。適合用來處理單次、多模態、結構化的請求。

```bash
POST /v1/response
```

or

```bash
http://<gateway-host>:<port>/v1/responses
```

#### Examples

- **Curl 範例**:
  - **Non-streaming**:

    ```bash
    curl -sS http://127.0.0.1:18789/v1/responses \
      -H "Authorization: Bearer <TOKEN>" \
      -H "Content-Type: application/json" \
      -H "x-openclaw-agent-id: main" \
      -d '{
        "model": "openclaw",
        "input": "測試內容",
      }'
    ```

  - **Streaming**:

    ```bash
    curl -N -sS http://127.0.0.1:18789/v1/responses \
      -H "Authorization: Bearer <TOKEN>" \
      -H "Content-Type: application/json" \
      -H "x-openclaw-agent-id: main" \
      -d '{
        "model": "openclaw",
        "input": "測試內容",
        "stream": true
      }'
    ```

- **Python (requests) 範例**:
  - **Non-streaming**:

    ```python
    import requests

    headers = {
      "Authorization": "Bearer <TOKEN>",
      "Content-Type": "application/json",
      "x-openclaw-agent-id": "main"
    }

    payload = {
      "model": "openclaw",
      "input": "測試內容",
    }

    response = requests.post(
        "http://127.0.0.1:18789/v1/responses", 
        headers=headers, 
        json=payload
    )
    print(response.json())
    ```

  - **Streaming**:

    ```python
    import requests
    import json

    headers = {
      "Authorization": "Bearer <TOKEN>",
      "Content-Type": "application/json",
      "x-openclaw-agent-id": "main"
    }

    payload = {
      "model": "openclaw",
      "input": "測試內容",
      "stream": true
    }

    response = requests.post(
      "http://127.0.0.1:18789/v1/responses", 
      headers=headers, 
      json=payload, 
      stream=True
    )
    for line in response.iter_lines():
      if line:
        decoded_line = line.decode('utf-8')
        if decoded_line.startswith('data: '):
          content = decoded_line[6:]
          if content == '[DONE]':
            break
          print(json.loads(content))
    ```

#### OpenResponses 詳細技術規格 (Detailed Specification)

- **URL**: `POST http://127.0.0.1:18789/v1/responses`

- **支援的請求參數 (Request Shape)**：

  1. `"input"`：(必填) 字串或項目物件 (Item Objects) 陣列。
  2. `"instructions"`：會自動合併到系統提示詞中。
  3. `"tools"`：客戶端工具定義 (Function tools)。
  4. `"tool_choice"`：過濾或強制使用指定的客戶端工具。
  5. `"stream"`：設為 `true` 以啟用 SSE 串流回覆。
  6. `"user"`：(選填) 自訂用戶 ID。
  7. `"previous_response_id"`：重用先前的回覆 Session。

- **輸入項目詳情 (Items Input)**：
  1. **一般訊息 (`message`)**：支援 `system`, `developer`, `user`, `assistant`。
  2. **工具結果 (`function_call_output`)**：

      ```json
      { "type": "function_call_output", "call_id": "call_123", "output": "{...}" }
      ```

  3. **圖片傳輸 (`input_image`)**：支援 Base64/URL。格式：jpeg, png, webp 等。最大 10MB。
  4. **檔案傳輸 (`input_file`)**：支援 Base64/URL。格式：txt, pdf, json 等。最大 5MB。

### 3. Tools Invoke API

這是一個簡單的 HTTP 端點，允許客戶端「直接呼叫並執行單一工具」，而完全不經過 Agent 的大語言模型思考與對話邏輯。

#### Examples

- **Curl 範例**:

  ```bash
  curl -sS http://127.0.0.1:18789/tools/invoke \
    -H "Authorization: Bearer <TOKEN>" \
    -H "Content-Type: application/json" \
    -H "x-openclaw-agent-id: main" \
    -d '{
      "tool": "sessions_list",
      "action": "json",
      "args": {}
    }'
  ```

- **Python (requests) 範例**:

  ```python
  import requests

  headers = {
    "Authorization": "Bearer <TOKEN>",
    "Content-Type": "application/json",
    "x-openclaw-agent-id": "main"
  }

  payload = {
    "tool": "sessions_list",
    "action": "json",
    "args": {}
  }

  response = requests.post(
      "http://127.0.0.1:18789/tools/invoke", 
      headers=headers, 
      json=payload
  )
  print(response.json())
  ```

#### 工具調用詳細技術規格 (Detailed Specification)

- **請求結構 (Payload Structure)**：
  最大 Payload 限制為 **2MB**。
  1. `"tool"`：(必填) 字串，要呼叫的工具名稱。
  2. `"action"`：(選填) 被映射為參數 `args.action`。
  3. `"args"`：(選填) 傳遞給該工具的具體參數。
  4. `"sessionKey"`：(選填) 操作目標 Session，預設為 `"main"`。
  5. `"dryRun"`：(選填) 若為 `true` 則僅作驗證。

- **策略與安全路由 (Policy & Routing)**：
  系統具備**硬性阻擋清單 (Hard Deny List)**：`cron`, `sessions_spawn`, `sessions_send`, `gateway`, `whatsapp_login`。

- **回覆狀態碼 (Response Statuses)**：
  - `200`：成功。回傳格式 `{ "ok": true, "result": ... }`。
  - `400` / `401` / `404` / `429` / `500`：分別對應無效參數、未授權、找不到工具、速率限制及內部錯誤。

## 🛠 技術細節與限制

- **最大請求大小**：HTTP Gateway 預設限制為 **20MB**。
- **檔案傳輸限制**：
  - **圖片**：最大 10MB (jpg, png, webp 等)。
  - **檔案**：最大 5MB (txt, pdf, json 等)。
- **特殊標頭 (Headers)**：
  - `x-openclaw-model`：覆寫權重。
  - `x-openclaw-session-key`：自定義 Session。
  - `x-openclaw-agent-id`：強制指定 Agent ID（預設為 `main`）。
- **Session 行為**：
  - 使用 `user` 欄位可確保同一用戶的多次呼叫被路由到同一個穩定的 Agent Session。
