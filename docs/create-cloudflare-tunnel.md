# 创建 Cloudflare Tunnel

EasyGate 使用 Cloudflare Tunnel 把公网 HTTPS 流量送到本地 Traefik。推荐用部署脚本创建和配置 tunnel；手动步骤只在你想完全自管 `cloudflared` 时使用。

## 推荐方式：部署脚本

macOS / Linux：

```sh
./scripts/deploy.sh --domain example.com
```

Windows PowerShell：

```powershell
.\scripts\deploy.ps1 -Domain example.com
```

脚本会：

- 按需准备 `cloudflared` CLI。
- 引导 `cloudflared tunnel login`。
- 创建或复用 `easygate-home` tunnel。
- 尝试创建 `*.example.com` DNS 路由。
- 生成 `.env` 和 `cloudflared/config.yml`。
- 复制 tunnel 凭据到 `cloudflared/easygate-home.json`。
- 启动 `traefik` 和 `cloudflared`。

如果同名 tunnel 已存在，脚本会复用本地最新凭据文件。凭据文件会以受限权限写入项目目录，不要提交到 Git。

## 手动方式

确认 CLI 可用：

```sh
cloudflared --version
```

登录 Cloudflare：

```sh
cloudflared tunnel login
```

创建 tunnel：

```sh
cloudflared tunnel create easygate-home
```

命令会生成：

```text
~/.cloudflared/<TUNNEL_ID>.json
```

创建通配 DNS 路由：

```sh
cloudflared tunnel route dns easygate-home "*.example.com"
```

如果 CLI 创建失败，可以在 Cloudflare DNS 手动添加：

```text
Type:   CNAME
Name:   *
Target: <TUNNEL_ID>.cfargotunnel.com
Proxy:  Proxied
```

## EasyGate 配置

复制模板：

```sh
cp .env.example .env
cp cloudflared/config.yml.example cloudflared/config.yml
```

编辑 `.env`：

```env
BASE_DOMAIN=example.com
TRAEFIK_HTTP_PORT=18080
TRAEFIK_DASHBOARD_HOST=traefik.example.com
```

编辑 `cloudflared/config.yml`：

```yaml
tunnel: easygate-home
credentials-file: /etc/cloudflared/easygate-home.json

ingress:
  - hostname: "*.example.com"
    service: http://traefik:80
  - service: http_status:404
```

把 tunnel 凭据复制到项目目录：

```sh
cp ~/.cloudflared/<TUNNEL_ID>.json cloudflared/easygate-home.json
chmod 600 cloudflared/easygate-home.json
```

启动：

```sh
make up
```

## 为什么目标是 http://traefik:80

`cloudflared` 和 Traefik 在同一个 Docker 网络中，`traefik` 是 Compose 服务名。因此 ingress 目标应为：

```text
http://traefik:80
```

不要填 `http://localhost:80`。在 `cloudflared` 容器里，`localhost` 指向 `cloudflared` 容器自己。

## 通配入口和具体记录

推荐 Cloudflare 侧只配置一个通配入口：

```text
*.example.com -> tunnel
```

已有具体记录会继续优先生效：

```text
www.example.com
mail.example.com
cdn.example.com
```

通配入口只接管没有单独配置的名称。**所有接入 EasyGate 的子域名必须是一级子域名**——Cloudflare Free 的 Universal SSL 证书不覆盖二级或更深层级子域名：

```text
✅ api.example.com
✅ test-api.example.com
✅ new-service.example.com
❌ api.nas.example.com        （证书不覆盖）
❌ test.service.example.com   （证书不覆盖）
```

详见 [cloudflare-free-limits.md](cloudflare-free-limits.md)。

## 验证

```sh
docker compose ps
docker compose logs -f cloudflared traefik
```

启动 demo：

```sh
make demo
```

访问：

```text
https://api.example.com
https://test-api.example.com
```

## 常见问题

### 每个服务都要在 Cloudflare 里加一条 hostname 吗？

不需要。Cloudflare 只需要通配入口。新增服务时只改 Docker labels 或 Traefik file provider。

### 可以创建多个 tunnel 吗？

可以，但不要让多套 EasyGate 同时接管同一个 hostname 或同一个 `*.example.com`。多设备部署见 [deployment-modes.md](deployment-modes.md)。

### tunnel 凭据可以公开吗？

不可以。`cloudflared/*.json` 可以让 connector 加入你的 tunnel，只应保存在部署设备或 secret 管理系统中。
