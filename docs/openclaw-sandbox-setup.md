# OpenClaw Sandbox 啟用與關閉

這份文件整理了 **OpenClaw Sandbox** 的使用流程，包含：

- 預設關閉的設計
- `docker-compose.yml` 與 `docker-compose.sandbox.yml` 的角色
- 如何啟用 sandbox
- 如何驗證 sandbox 是否成功
- 如何關閉 sandbox
- `setup.sh`、`enable_sandbox.sh`、`disable_sandbox.sh` 的用途

## 設計目標

本專案採用 **預設關閉（default-off）** 的 sandbox 設計：

- 預設只使用 `docker-compose.yml`
- 預設 **不掛載** `docker.sock`
- 預設 OpenClaw 的 `sandbox.mode` 應為 `off`
- 只有在需要 sandbox 時，才疊加 `docker-compose.sandbox.yml`

這樣做的好處是：

- 預設權限更小
- 平常純對話 / 一般 agent 使用更安全
- 需要 sandbox 時才額外開權限

## Compose 檔案角色

- `docker-compose.yml`

  預設啟動用，不應包含 `docker.sock` 掛載。

- `docker-compose.sandbox.yml`

  固定存在於 repo 中，只在 **需要啟用 sandbox** 時才疊加，用來掛載 Docker socket 與補上對應群組權限。

  ```yaml
  services:
    openclaw-gateway:
      volumes:
        # 將 host Docker socket 掛進容器
        - ${OPENCLAW_DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock

      group_add:
        # 讓容器內程序有權限存取 docker.sock
        - "${DOCKER_GID:-0}"
  ```

## Script 角色

- `setup.sh`  

  用於完整初始化與部署。會處理 `.env`、token、onboard、gateway 設定，以及依 `OPENCLAW_SANDBOX` 決定是否套用 sandbox。

- `enable_sandbox.sh`

  在已完成 `setup.sh` 的前提下，快速開啟 sandbox，不重跑完整初始化流程。

- `disable_sandbox.sh`

  在已完成 `setup.sh` 的前提下，快速關閉 sandbox，不重跑完整初始化流程。

## 啟用 sandbox

### 方式 1：初始化時一起啟用

在執行 `setup.sh` 前，先設定 `.env`：

```dotenv
OPENCLAW_SANDBOX=1
OPENCLAW_DOCKER_SOCKET=/var/run/docker.sock
DOCKER_GID=995
```

然後執行：

```bash
./setup.sh
```

### 方式 2：初始化完成在啟用 - 自動執行

使用 `enable_sandbox.sh`：

先加執行權限：

```bash
chmod +x scripts/enable_sandbox.sh
```

執行：

```bash
./scripts/enable_sandbox.sh
```

這份 script 會自動：

- 檢查 `docker compose`
- 查詢 Docker socket 路徑
- 查詢 `DOCKER_GID`
- 更新 `.env`
- 疊加 `docker-compose.sandbox.yml`
- 重建 `openclaw-gateway`
- 寫入 OpenClaw sandbox 設定
- 重啟 gateway 套用設定
- 驗證結果

### 方式 3: 手動啟用 sandbox 流程

如果你不想使用 `enable_sandbox.sh`，也可以手動操作。

#### 步驟 1：查詢 `DOCKER_GID`

`DOCKER_GID` 是 **host 上 `/var/run/docker.sock` 的 group id**。

啟用 sandbox 時，`openclaw-gateway` 容器通常需要這個值，才能存取 `docker.sock`。

##### macOS

```bash
stat -f '%g' /var/run/docker.sock
```

##### Linux

```bash
stat -c '%g' /var/run/docker.sock
```

#### 步驟 2：修改 `.env` (手動啟用)

將查到的值，例如 `995`，填進 `.env`：

```dotenv
DOCKER_GID=995
```

並確認以下設定已寫入：

```dotenv
OPENCLAW_SANDBOX=1
OPENCLAW_DOCKER_SOCKET=/var/run/docker.sock
```

#### 步驟 3：用 sandbox override 重建 gateway

```bash
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml up -d --force-recreate openclaw-gateway
```

#### 步驟 4：寫入 OpenClaw 內部 sandbox 設定

```bash
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config set agents.defaults.sandbox.mode non-main
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config set agents.defaults.sandbox.scope agent
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config set agents.defaults.sandbox.workspaceAccess none
```

這三個值代表：

- `mode=non-main`：啟用 sandbox
- `scope=agent`：以 agent 為作用範圍
- `workspaceAccess=none`：不直接給 workspace 存取權

#### 步驟 5：重啟 gateway 套用設定 (手動啟用)

```bash
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml restart openclaw-gateway
```

#### 步驟 6: 驗證 sandbox 是否成功啟用

- 查詢 OpenClaw 設定

  ```bash
  docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config get agents.defaults.sandbox
  ```

  預期結果類似：

  ```json
  {
    "mode": "non-main",
    "scope": "agent",
    "workspaceAccess": "none"
  }
  ```

- 檢查 gateway 容器內能否看到 Docker socket

  ```bash
  docker compose -f docker-compose.yml -f docker-compose.sandbox.yml exec openclaw-gateway ls -l /var/run/docker.sock
  ```

  如果看得到 `/var/run/docker.sock`，代表 override 掛載已生效。

## 關閉 sandbox

### 方式 1：初始化時保持關閉

在執行 `setup.sh` 前，先設定：

```dotenv
OPENCLAW_SANDBOX=0
```

然後執行：

```bash
./setup.sh
```

### 方式 2：初始化完成後再關閉

使用 `scripts/disable_sandbox.sh`：

先加執行權限：

```bash
chmod +x scripts/disable_sandbox.sh
```

執行：

```bash
./scripts/disable_sandbox.sh
```

這份 script 會自動：

- 更新 `.env`，將 `OPENCLAW_SANDBOX=0`
- 將 OpenClaw sandbox 設定重設為關閉狀態
  - `mode=off`
  - `scope=agent`
  - `workspaceAccess=none`
- 用 base compose 重建 `openclaw-gateway`
- 重啟 gateway 套用設定
- 驗證結果

### 方式 3: 手動關閉 sandbox

如果你不想使用 `scripts/disable_sandbox.sh`，也可以手動操作。

#### 步驟 1：把 OpenClaw sandbox mode 關掉

```bash
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config set agents.defaults.sandbox.mode off
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config set agents.defaults.sandbox.scope agent
docker compose -f docker-compose.yml -f docker-compose.sandbox.yml run --rm openclaw-cli config set agents.defaults.sandbox.workspaceAccess none
```

#### 步驟 2：修改 `.env` (手動關閉)

確認 `.env` 內：

```dotenv
OPENCLAW_SANDBOX=0
```

#### 步驟 3：用主 compose 重建 gateway

```bash
docker compose up -d --force-recreate openclaw-gateway
```

#### 步驟 4：重啟 gateway 套用設定 (手動關閉)

```bash
docker compose restart openclaw-gateway
```

關閉後會回到：

- 不掛 `docker.sock`
- sandbox 關閉

#### 步驟 5：驗證 sandbox 是否成功關閉

```bash
docker compose run --rm openclaw-cli config get agents.defaults.sandbox
docker compose exec openclaw-gateway ls -l /var/run/docker.sock
```

預期結果類似：

```json
{
  "mode": "off",
  "scope": "agent",
  "workspaceAccess": "none"
}
```