# OpenClaw Models 設定指南

本文件整理 OpenClaw 在 `openclaw.json` 中與模型相關的設定——包含**模型註冊 (allowlist)**、**主要模型 (primary)**、**備用模型 (fallbacks)** 與**思考模式 (thinking)**——以及搭配的 CLI 指令與常見地雷。

典型的設定區塊長這樣：

```json
"agents": {
  "defaults": {
    "model": {
      "primary": "google/gemini-2.5-pro",
      "fallbacks": [
        "openai/gpt-4o",
        "google/gemini-3.1-flash-lite-preview"
      ]
    },
    "models": {
      "google/gemini-2.5-pro": { "alias": "gemini-2.5-pro" },
      "openai/gpt-4o": {},
      "google/gemini-3.1-flash-lite-preview": {}
    },
    "thinkingDefault": "medium"
  }
}
```

各欄位重點：

- `agents.defaults.models` — **allowlist**。只有在這裡註冊過的模型才能被 `primary` 或 `fallbacks` 參照；這也是 `/model` 指令與會話覆寫的選單範圍（見 §2.2、§3）。
- `agents.defaults.model.primary` — 預設送往的主要模型。
- `agents.defaults.model.fallbacks` — 主模型遇到 Auth、Rate Limit 或服務超載等錯誤時，依序嘗試的備援清單（見 §1、§2）。
- `agents.defaults.thinkingDefault` — 思考 / reasoning 層級的全域預設；部分模型（例如 `google/gemini-2.5-pro`）必須設定才能正常運作（見 §4）。

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

> [!IMPORTANT]
> 加入 `fallbacks` 清單的模型，必須同時存在於 `agents.defaults.models` allowlist 中，否則備用機制觸發時系統會回覆「Model is not allowed」。`models fallbacks add` **不會**自動把模型註冊到 allowlist，請先完成以下第 1 步。

以下以把 OpenAI 的 `gpt-4o` 加為備用模型為例（清單內的順序即為 Fallback 嘗試順序）：

1. **註冊模型到 allowlist** — 以 `config set` 直接寫入 `agents.defaults.models` 底下的 leaf path，並用 `--json` 將值解析為 JSON 物件；別名 (`alias`) 可自訂，若不需要別名可把值填成 `{}`：

    ```bash
    docker compose run --rm openclaw-cli config set \
      agents.defaults.models.openai/gpt-4o '{"alias":"gpt-4o"}' --json
    ```

2. **把模型加入 Fallbacks 清單**：

    ```bash
    docker compose run --rm openclaw-cli models fallbacks add openai/gpt-4o
    ```

> [!TIP]
> 若覺得指令列上 JSON 的引號跳脫麻煩，可改用 `docker compose run --rm openclaw-cli config edit` 直接打開預設編輯器，手動在 `agents.defaults.models` 區段補上 `"openai/gpt-4o": {"alias": "gpt-4o"}` 後存檔，系統會自動套用新設定。

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

## 4. 思考模式 (Thinking) 與 Gemini 2.5 Pro 的陷阱

若把**強制需要思考模式**的模型——例如 `google/gemini-2.5-pro`——加入 `primary` 或 `fallbacks`，務必同時設定 `thinkingDefault`，否則當請求輪到該模型時會收到：

```text
LLM error: {
  "error": {
    "code": 400,
    "message": "Budget 0 is invalid. This model only works in thinking mode.",
    "status": "INVALID_ARGUMENT"
  }
}
```

原因：OpenClaw 傳給 Google API 的 `thinkingConfig.thinkingBudget` 被設成 `0`（思考關閉），但 `gemini-2.5-pro` 在 Google API 端強制要求 `thinkingBudget > 0`。這是 Google 的 API 限制，不是 OpenClaw 的限制。

### 4.1 解法：設定全域 `thinkingDefault`

在 `agents.defaults` 加上 `thinkingDefault`，最保守的值是 `"medium"`：

```bash
docker compose run --rm openclaw-cli config set \
  agents.defaults.thinkingDefault "medium"
```

對應 `openclaw.json` 片段：

```json
"agents": {
  "defaults": {
    "thinkingDefault": "medium"
  }
}
```

### 4.2 可用層級與解析順序

可選值（由弱到強）：

| 值 | 別名 |
| --- | --- |
| `off` | — |
| `minimal` | think |
| `low` | think hard |
| `medium` | think harder |
| `high` | ultrathink |
| `xhigh` | ultrathink+ |
| `adaptive` | 自適應 |
| `max` | 最大 |

解析優先順序（高 → 低）：

1. 訊息內聯指令（只影響那一則訊息）
2. 會話層覆寫（單獨送一則 `/think:medium` 設定會話預設）
3. 每個 Agent：`agents.list[].thinkingDefault`
4. 全域：`agents.defaults.thinkingDefault`
5. Provider 宣告的預設

### 4.3 `/think` 與 `/reasoning` 的差異

兩個指令很容易混淆，但作用不同：

- `/t <level>` 或 `/think:<level>` — **控制思考層級**，真正影響送出的 `thinkingBudget` 是否 > 0；用它才能修正上述 Gemini 400 錯誤。
- `/reasoning on|off|stream` — **控制思考內容是否以獨立訊息輸出給你看**（是否把 reasoning 串流回顯）；單獨跑這個無法修正上述錯誤。

### 4.4 進階：針對單一模型覆寫（選用）

全域 `thinkingDefault: "medium"` 會讓**所有**模型（含平常不需思考的 `gpt-4o`、`gemini-3.1-flash-lite-preview` 等 fallback 模型）都帶上 medium 的 budget，可能徒增 token 成本與延遲。

若想只對 `gemini-2.5-pro` 開思考、其他模型維持預設，可嘗試把 thinking 參數掛在模型層：

```json
"agents": {
  "defaults": {
    "models": {
      "google/gemini-2.5-pro": {
        "alias": "gemini-2.5-pro",
        "params": {
          "thinkingBudget": 1024
        }
      }
    }
  }
}
```

> [!NOTE]
> 官方文件目前對 `agents.defaults.models.<model>.params.thinkingBudget` 這個 per-model 覆寫欄位的記載不完整（只有 `params.fastMode`、`params.cachedContent` 明確記載），使用前建議實測驗證。最保險的做法仍是採用全域 `thinkingDefault: "medium"`。

### 4.5 參考資料

完整思考模式文件：[docs.openclaw.ai/tools/thinking.md](https://docs.openclaw.ai/tools/thinking.md)

## 5. 相關的 CLI 指令參考

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
