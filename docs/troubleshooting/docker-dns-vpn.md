# 關閉 VPN 後 Telegram Polling / LLM API 斷線問題

## 症狀

關閉 VPN 後，`openclaw-gateway` container 開始出現以下錯誤，重啟也沒用：

```text
[telegram] Polling stall detected (active getUpdates stuck for 250.11s); forcing restart.
error=Network request for 'getUpdates' failed!

[agent/embedded] Profile google:default timed out.
error=LLM request failed: network connection error. rawError=fetch failed
```

短連線（例如 `curl api.telegram.org`）從 container 內測試是通的，但長連線（long polling）持續 stall 後斷掉。

## 根本原因：Docker DNS 解析鏈斷裂

Docker container 預設的 DNS 解析路徑如下：

```
Container
  → 127.0.0.11 (Docker 內建 DNS)
    → 192.168.65.7 (Docker Desktop 的 host gateway)
      → Mac 主機目前使用的 DNS
```

當 VPN **開著**時，Mac 使用 VPN 提供的 DNS，能正常解析 `api.telegram.org` 等外部域名。

當 VPN **關閉**後，Mac 的 DNS 回到公司/內網 DNS server。內網 DNS 通常：

- 無法解析公司網域以外的外部域名，或
- 解析速度不穩定，導致 long polling 的 TCP 連線在等待過程中被視為死連線而切斷。

Telegram long polling (`getUpdates`) 是一個會掛著等幾十秒才回應的 HTTP 請求，特別容易受到 DNS 不穩或 NAT/防火牆的 idle TCP timeout 影響。

## 解決方案

在 `docker-compose.yml` 的 `openclaw-gateway` service 加上 `dns`，強制 container 跳過 host DNS chain，直接使用公共 DNS：

```yaml
services:
  openclaw-gateway:
    # ... 其他設定 ...

    # 內網 DNS 無法穩定解析外部域名，強制使用公共 DNS
    # 確保關閉 VPN 後 Telegram polling / LLM API 仍能正常運作
    dns:
      - 1.1.1.1
      - 8.8.8.8
```

設定後重啟 container：

```bash
docker compose down && docker compose up -d
```

## 驗證

確認 container 內的 `/etc/resolv.conf` 已改為公共 DNS：

```bash
docker exec openclaw-gateway cat /etc/resolv.conf
```

預期輸出：

```text
nameserver 1.1.1.1
nameserver 8.8.8.8
```

接著觀察 log，polling 應持續穩定運作，不再出現 stall：

```bash
docker compose logs -f openclaw-gateway
```

## 為什麼官方 docker-compose 沒有這個設定

這是環境特有的問題。多數人的網路環境（家用路由器或標準公司網路）的 DNS 都能正常解析外部域名，不需要這個設定。

只有當 host 的 DNS 是**無法解析外部網域的內網 DNS**，且又要在不開 VPN 的情況下使用時，才需要加上這個覆蓋。

## 常見疑問：Mac 網路介面已設定 8.8.8.8，Docker 不是也會吃到嗎？

理論上是這樣，但實際上不可靠，原因有三：

1. **Docker Desktop 不即時同步 DNS 變更**：VPN 斷線時 Mac 的 DNS 切回 Ethernet 的設定，但 Docker Desktop VM 可能仍快取 VPN 的 DNS，有一段空窗期。

2. **傳遞路徑多且脆弱**：`container → 127.0.0.11 → 192.168.65.7 → Mac system resolver → 8.8.8.8`，中間任何一層異常都會失效。

3. **macOS 多介面 DNS 優先序複雜**：VPN 與 Ethernet 同時存在時，`scutil --dns` 的 resolver 順序並非單純依介面排序，VPN 斷線後其 DNS 條目有時不會立即清除。

`dns:` 寫進 docker-compose.yml 後，container 的 `/etc/resolv.conf` **直接就是** `nameserver 1.1.1.1`，完全跳過 Docker Desktop 的 DNS 同步機制，行為確定且不受 Mac 當下網路狀態影響。因此即使 Mac Ethernet 已設公共 DNS，保留這個設定仍然值得。
