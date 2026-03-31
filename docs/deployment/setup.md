# OpenClaw 安裝指南 (Installation Guide)

本文件介紹了 OpenClaw 的多種安裝方式。

## 1. 本專案快速部署 (setup.sh)

這是針對本專案架構優化過的安裝方式，會導引您完成 Token 產生、環境變數同步與資料夾權限修護。

> [!NOTE]
> 關於本腳本的技術細節與原理解析，請參閱：[OpenClaw 部署腳本技術全解析 (Setup Deep Dive)](setup-deep-dive.md)

### 部署步驟

在專案根目錄下執行：

```bash
bash setup.sh
```

## 2. 官方安裝方式 (Official Methods)

如果您偏好使用 OpenClaw 官方標準提供的安裝途徑，請參考以下分類：

### 2.1 NPM 安裝 (General NPM Method)

適用於已安裝 Node.js (22.16+ / 24+) 的環境：

```bash
# 全域安裝 OpenClaw
npm install -g openclaw@latest

# 執行初始化 (同樣需要 Onboarding)
openclaw onboard --mode local
```

### 2.2 Docker 部署 (Official Docker Methods)

如果您偏好使用官方標準 Docker 路徑，請根據您的環境選擇以下兩種方式：

#### 2.2.1 手動部署：使用預建映像檔 (Manual - Pre-built Image)

適用於不想克隆原始碼，只想拉取現成映像檔並手動管理設定的使用者。**注意：此方式必須手動執行初始化與基礎配置。**

```bash
# 1. 執行 Onboarding 產出 Token 與配置
docker run -it --rm -v ~/.openclaw:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest onboard --mode local --no-install-daemon

# 2. 設定運作模式 (Mode) 與 綁定地址 (Bind)
docker run -it --rm -v ~/.openclaw:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest config set gateway.mode local
docker run -it --rm -v ~/.openclaw:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest config set gateway.bind lan

# 3. 手動設定 CORS 白名單 (如果您是透過瀏覽器存取)
docker run -it --rm -v ~/.openclaw:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest config set gateway.controlUi.allowedOrigins '["http://localhost:18789"]' --strict-json

# 4. 正常啟動服務
docker run -d -p 18789:18789 --name openclaw \
  -v ~/.openclaw:/home/node/.openclaw ghcr.io/openclaw/openclaw:latest
```

#### 2.2.2 克隆儲存庫執行腳本 (Clone & Setup)

這是官方提供的自動化安裝流程，適用於一般的伺服器環境：

```bash
git clone https://github.com/openclaw/openclaw-server.git
cd openclaw-server
bash setup.sh
```

> [!NOTE]
> 腳本運作原理可參閱：[Setup Deep Dive](setup-deep-dive.md)

### 2.3 從原始碼建構 (From Source)

如果您是開發者，需要手動修改原始碼並本地建構映像檔：

```bash
# 1. 安裝依賴
pnpm install

# 2. 本地建構映像檔
docker build -t openclaw:local -f Dockerfile .
```

## 3. 後續設定 (Next Steps)

完成基礎部署後，請根據您的需求參閱以下進階配置：

- [瀏覽器控制：Docker Gateway + Mac Host Chrome 完整設定](../guides/browser-control.md)
- [Telegram 整合與 Bot 設定指南](../platforms/telegram.md)
