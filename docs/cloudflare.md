# Cloudflare 参考

## Free 套餐限制

### SSL/TLS 证书覆盖范围

Cloudflare Free 的 Universal SSL 通配证书**只覆盖根域名和一级子域名**：

```
✅ api.example.com
✅ test-api.example.com
❌ test.api.example.com        （二级子域名，证书不匹配）
❌ api.nas-home.example.com    （二级子域名，证书不匹配）
```

如果需要更深层级（如 `*.internal.example.com`），可以购买 Cloudflare Advanced Certificate Manager。

### 带宽和连接

- **无固定带宽上限**，但 Cloudflare ToS 限制非 HTML 内容（视频、大文件分发）作为主要用途。
- **Tunnel 并发连接**受 `cloudflared` 进程和系统资源限制，不是 Cloudflare 硬限制。
- Free 套餐不适合大文件分发、公开网盘、持续高带宽视频流。

### DNS 记录

- 免费套餐支持所有标准 DNS 记录类型。
- 通配 `*.example.com` CNAME 记录在 Free 套餐中可用。
- DNS 传播新域名可能需要几分钟到数小时。验证方法：
  ```sh
  dig @1.1.1.1 example.com NS +short
  dig @1.1.1.1 api.example.com A +short
  ```

## 创建 Tunnel（手动）

部署脚本会自动创建和配置 Tunnel。如果需要手动管理：

### 1. 登录

```sh
cloudflared tunnel login
```

打开弹出的浏览器授权 Cloudflare 账号。凭据保存在 `~/.cloudflared/cert.pem`。

### 2. 创建 Tunnel

```sh
cloudflared tunnel create easygate-home
```

凭据 JSON 保存在 `~/.cloudflared/<tunnel-id>.json`。将其复制到 `EASYGATE_HOME/cloudflared/`：

```sh
cp ~/.cloudflared/<tunnel-id>.json ~/.easygate/cloudflared/easygate-home.json
```

### 3. 创建 DNS 路由

```sh
cloudflared tunnel route dns easygate-home "*.example.com"
```

### 4. 配置和运行

cloudflared 配置（部署脚本自动生成）：
```yaml
tunnel: easygate-home
credentials-file: /etc/cloudflared/easygate-home.json

ingress:
  - hostname: "*.example.com"
    service: http://traefik:80       # Docker 模式
    # service: http://127.0.0.1:18080 # 原生模式
  - service: http_status:404
```

### 5. 删除 Tunnel（如不再需要）

```sh
cloudflared tunnel delete easygate-home
```

在 Cloudflare Dashboard → DNS 中手动删除通配 `CNAME` 记录（如果有）。

## 域名迁移：百度云 → Cloudflare

### 迁移操作

1. 在 Cloudflare Dashboard 添加站点，输入域名。
2. Cloudflare 扫描现有 DNS 记录后，提供**两个新的 Cloudflare nameserver**。
3. 登录百度云 → 域名管理 → 修改 DNS 服务器，将 nameserver 替换为上一步提供的两个 Cloudflare nameserver。
4. 等待 DNS 传播（几分钟到 48 小时，通常较快）。
5. Cloudflare 会在迁移完成后发送邮件通知。确保 SSL/TLS 设置为 **Full** 或 **Full (strict)**。
6. 在 Cloudflare DNS 中确认或补充原百度云上的 DNS 记录（A、CNAME 等）。
7. 开启 Universal SSL 和 Always Use HTTPS。

### 注意事项

- 迁移过程**不会中断已解析的服务**，前提是两边 DNS 记录一致。
- 迁移后百度云的 DNS 服务不再生效，所有记录管理在 Cloudflare 进行。
- 如果域名还有备案需求，确认备案信息与 Cloudflare 的兼容性。
