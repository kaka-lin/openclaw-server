# OpenClaw Browser Profiles 設定指南

本文件說明如何在 OpenClaw 中設定多個獨立的瀏覽器環境（Browser Profiles），並透過設定檔 `openclaw.json` 來新增與管理。這對於需要區分不同帳號或任務（例如 `work` 專案）的情境非常實用。

## 1. 什麼是 Browser Profiles

OpenClaw 允許建立多個從屬的瀏覽器設定檔（Profiles）。預設有一個 `openclaw` profile 作為完全隔離的代理瀏覽器環境，不會干擾你個人的使用。如果你有特定任務需求（例如專屬的工作或測試帳號），可以建立自訂 Profile。

## 2. 修改 openclaw.json 設定

目前新增或修改 Browser Profile 建議直接編輯 `openclaw.json`，設定檔位於 `~/.openclaw/openclaw.json` 或專案目錄中（本專案為 `/openclaw.json`）。

打開檔案並尋找 `browser.profiles` 區塊，加入你的自訂設定。以下示範如何建立自訂的 `work` Profile：

```json
"browser": {
  "defaultProfile": "openclaw",
  "profiles": {
    "openclaw": {
      "cdpPort": 18800,
      "color": "#FF4500"
    },
    "work": {
      "color": "#00AAFF",
      "cdpPort": 9223
    }
  }
}
```

- **設定檔名稱 (自行定義)**：`"work"` 可以命名為任何名稱（例如 `"research"`, `"langlive"` 等）。`openclaw` 只是系統原先內建的第一個隔離環境，你完全可以建立屬於自己的名稱，甚至也可以修改 `defaultProfile` 的值，來變更預設呼叫 CLI 時要啟用的環境。

- **`color`**: 瀏覽器視窗的高光標示顏色，`#00AAFF` 為淺藍色。這會渲染在視窗邊框，幫助你一眼辨識目前的任務環境。

- **`cdpPort`**: Chromium Debugging Protocol 的目標通訊埠。
  - **預設機制**：在沒有明確寫死 `cdpPort` 的情況下，系統執行本地端 (`local`) profile 時其實會自動分配可用的 port 號。不過在 OpenClaw 的配置邏輯中，`18800` 常常是系統用來配合預設 Gateway 分配給首個內建 Browser Profile 的埠口。
  - **增加多個環境如何分配**：推薦明確指定 Port (比較穩定)，只要給予未使用的數字即可。例如傳統 Chrome Debug 習慣開在 `9222`，所以你可以依序把自訂的 Profile 指定為 `9223`、`9224`、`9225` 等等，只要確保不重複衝突就好。

## 3. 使用 CLI 控制 Browser Profile

雖然新增 Profile 需手動修改 JSON，但你可以透過 CLI 操作與確認特定 Profile 的狀態。

### 3.1 查看列表與狀態

取得所有 Profile 的連線狀態，如果設定正確，可確認目標埠是否已服務：

```bash
openclaw browser profiles
openclaw browser status
```

針對特定的 Profile 查看：

```bash
openclaw browser --browser-profile work status
```

### 3.2 啟動指定的 Profile

若要手動啟動該瀏覽器環境：

```bash
openclaw browser --browser-profile work start
```

### 3.3 其他基本操作

除了啟動，CLI 也支援直接指定 profile 的細微操作。

- 開啟特定網址：

  ```bash
  openclaw browser --browser-profile work open https://example.com
  ```

- 對該 Profile 擷圖：

  ```bash
  openclaw browser --browser-profile work snapshot
  ```

- 停止該 Profile 的瀏覽器實例：

  ```bash
  openclaw browser --browser-profile work stop
  ```

> [!NOTE]
> 如果 OpenClaw 回報 `Unknown command` 或無法使用 Browser 功能，請確認 `openclaw.json` 的 `plugins.allow` 是否未包含 `browser`，或已設定 `browser.enabled: true`。
