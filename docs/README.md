# OpenClaw 實作與設定指南 (Documentation)

歡迎來到此專案的文件庫。這裡收錄了經過簡化與實戰驗證的 OpenClaw 安裝、設定及部署指南。

## 1. 快速入門 (Getting Started)

- [安裝指南](deployment/setup.md)
- [CLI 使用手冊](guides/cli-usage.md)

## 2. 常用 Docker 指令

```bash
# 重啟 Gateway（修改 openclaw.json 後必須執行）
docker compose restart openclaw-gateway

# 查看即時 log
docker compose logs -f openclaw-gateway

# 查看最近 200 行 log
docker compose logs --tail 200 openclaw-gateway

# 進入容器
docker exec -it <container_id> bash

# 執行 CLI 指令
docker compose run --rm openclaw-cli <command>

# 例：列出 cron job
docker compose run --rm openclaw-cli cron list

# 例：列出所有 session
docker compose run --rm openclaw-cli sessions --all-agents
```

## 3. 功能配置指南 (Guides)

### 自動化與排程

- [Heartbeat 心跳設定指南](guides/heartbeat-config.md)
- [自動化與 Cron Job 設定指南](guides/automation-config.md)

### Agent 設定

- [Agent 身分識別與個性管理](guides/agent-identity.md)
- [Multi-Agent Discord 配置指南](guides/multi-agent-discord.md)
- [Models 設定指南](guides/models-config.md)

### 瀏覽器

- [瀏覽器控制：Docker Gateway + Mac Host Chrome](guides/browser-control.md)
- [Browser Profiles 配置指南](guides/browser-profiles-config.md)

### 擴充技能 (Skills)

- [擴充技能權限與系統指令配置](skills/permissions-config.md)
- [agent-browser 容器內建瀏覽器](skills/agent-browser.md)

## 4. 範本 (Templates)

- [HEARTBEAT.md 範例集](templates/heartbeat-examples.md)

## 5. 平台整合 (Platform Integrations)

- [Telegram 整合與 Bot 設定指南](platforms/telegram.md)
- [Discord 全功能安裝與配置指南](platforms/discord.md)

## 6. 進階部署 (Advanced Deployment)

- [部署腳本技術全解析](deployment/setup-deep-dive.md)

## 7. 疑難排解 (Troubleshooting)

- [關閉 VPN 後 Telegram Polling / LLM API 斷線問題](troubleshooting/docker-dns-vpn.md)
- [CLI config set 數字路徑 bug 修復](troubleshooting/cli-config-numeric-path.md)

## 8. 架構原理與研究

對於想要深入了解 OpenClaw 核心設計的使用者，請參閱個人筆記庫：

- [OpenClaw 核心原理與架構筆記 (LLM-notes)](https://github.com/kaka-lin/LLM-notes/tree/main/OpenClaw)

## 相關資源

- [回到專案首頁](../README.md)
- [OpenClaw 官方文件](https://docs.openclaw.ai)
- [個人技術筆記 (LLM-notes)](https://github.com/kaka-lin/LLM-notes/tree/main/OpenClaw)
