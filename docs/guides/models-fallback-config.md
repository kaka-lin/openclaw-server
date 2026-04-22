# OpenClaw Models Fallbacks (備用模型) 設定指南

為了避免因單一 AI API 服務（如 Gemini）不穩定或超載而造成的錯誤，OpenClaw 提供了 Model Fallback（備用模型）機制。當首選的 Primary Model 無法回應或發生異常時，系統會依序嘗試設定的備用模型，直到成功或所有備用方案皆失敗。

## 1. 備用模型運作邏輯

1. 當 Agent 發起請求時，會先送到 Primary Model（例如 `google/gemini-3.1-pro-preview`）。
2. 若遇到 Auth、Rate Limit 或服務超載等錯誤，OpenClaw 會自動切換到 `fallbacks` 清單中的下一個模型。
3. 同一個供應商（Provider）內部的認證切換機制會優先於跨模組（跨 Provide）的 Fallback 機制進行。

## 2. 使用 CLI 設定 Fallbacks (推薦)

OpenClaw 提供了完整的 `models` CLI 工具來設定 Fallbacks，建議使用此方法以減少修改 JSON 格式時出錯的風險。

### 2.1 查詢目前的 Fallbacks 清單

```bash
docker compose run --rm openclaw-cli models fallbacks list
```

### 2.2 新增備用模型

將 OpenAI 的 `gpt-4o` 加入為備用模型（加入的順序即為優先考量順序）：

```bash
docker compose run --rm openclaw-cli models fallbacks add openai/gpt-4o
```

### 2.3 移除備用模型

從目前的 Fallbacks 清單移除特定模型：

```bash
docker compose run --rm openclaw-cli models fallbacks remove openai/gpt-4o
```

### 2.4 清空所有備用模型

```bash
docker compose run --rm openclaw-cli models fallbacks clear
```

## 3. 手動修改 openclaw.json

除了使用 CLI 外，也可以直接編輯專案或家目錄的 `openclaw.json` 進行設定。請尋找 `agents.defaults.model` 區塊，修改 `fallbacks` 陣列檔案。

```json
"agents": {
  "defaults": {
    "model": {
      "primary": "google/gemini-3.1-pro-preview",
      "fallbacks": [
        "openai/gpt-4o"
      ]
    },
    "models": {
      "google/gemini-3.1-pro-preview": {},
      "openai/gpt-4o": {}
    }
  }
}
```

> [!IMPORTANT]
> 確保你設定的 Fallback 模型（如 `openai/gpt-4o`）不僅存在於 `fallbacks` 陣列內，也必須具有存取權限（即包含在 `agents.defaults.models` 選單中或 allowlist 裡面），否則備用機制觸發時系統會提示「Model is not allowed」。

## 4. 相關的 CLI 指令參考

若要進一步了解系統中可選用的所有模型，可利用以下指令：

- 列出目前系統中**已配置且可存取**的模型：

  ```bash
  docker compose run --rm openclaw-cli models list
  ```

- 如果想查閱系統支援的**全部模型型號清單**（例如想尋找新的代號來新增）：

  ```bash
  docker compose run --rm openclaw-cli models list --all
  ```

- 若要在全庫中，針對特定的供應商（例如 `google` 或 `openai`）進行篩選查詢：

  ```bash
  docker compose run --rm openclaw-cli models list --all --provider google
  ```

- 查看目前的預設模型與各 Provider 的狀態及認證檢查：

  ```bash
  docker compose run --rm openclaw-cli models status
  ```
