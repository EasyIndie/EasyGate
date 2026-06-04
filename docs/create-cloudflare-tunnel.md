# 创建 Cloudflare Tunnel

EasyGate 使用 `cloudflared` CLI 创建和管理 Cloudflare Tunnel。你只需要把域名接入 Cloudflare，并在本机执行 CLI 命令。

## 前提

- 域名已经接入 Cloudflare Full DNS setup。
- 本机或入口设备可以运行 `cloudflared`。
- 本项目会把公网流量交给 Traefik，再由 Traefik 分发到具体服务。
- EasyGate 不会自动安装 `cloudflared`，需要你先在部署设备上安装。

## 1. 安装 cloudflared

确认命令可用：

```sh
cloudflared --version
```

Windows PowerShell：

```powershell
cloudflared.exe --version
```

## 2. 登录 Cloudflare

```sh
cloudflared tunnel login
```

该命令会打开浏览器，登录后选择你的域名。完成后，本机会生成用于管理 tunnel 的 `cert.pem`。

## 3. 创建 tunnel

```sh
cloudflared tunnel create easygate-home
```

命令会创建 tunnel，并生成凭据文件：

```text
<TUNNEL_ID>.json
```

## 4. 添加 DNS 路由

推荐只给 Cloudflare 配一条通配入口：

```sh
cloudflared tunnel route dns easygate-home "*.example.com"
```

把 `example.com` 换成你的真实域名。

如果 CLI 不接受通配 hostname，可以在 Cloudflare DNS 中手动添加：

```text
Type:   CNAME
Name:   *
Target: <TUNNEL_ID>.cfargotunnel.com
Proxy:  Proxied
```

### 已有域名解析会不会受影响

一般不会影响已有的具体解析记录。

Cloudflare 的通配 DNS 记录只会在查询的主机名没有更具体记录时生效。例如你配置了：

```text
*.example.com -> tunnel
```

同时已有：

```text
www.example.com  -> 现有网站
mail.example.com -> 邮件服务
cdn.example.com  -> 其他云服务
```

那么 `www.example.com`、`mail.example.com`、`cdn.example.com` 会继续使用它们自己的具体 DNS 记录，不会被 `*.example.com` 接管。

通配入口只会接住没有单独配置的名称，例如：

```text
api.example.com
test-api.example.com
new-service.example.com
```

如果某个子域名不需要进入 EasyGate，请在 Cloudflare DNS 中为它创建具体记录。具体记录会优先于通配记录。

## 5. 配置 EasyGate

复制模板：

```sh
cp cloudflared/config.yml.example cloudflared/config.yml
```

编辑 `cloudflared/config.yml`：

```yaml
tunnel: easygate-home
credentials-file: /etc/cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: "*.example.com"
    service: http://traefik:80
  - service: http_status:404
```

把 `<TUNNEL_ID>.json` 放到项目的 `cloudflared/` 目录：

```text
cloudflared/<TUNNEL_ID>.json
```

该文件包含 tunnel 凭据，不要提交到 Git。

## 6. 启动

```sh
make up
```

或：

```sh
docker compose up -d
```

## 7. 验证

查看容器：

```sh
docker compose ps
```

查看日志：

```sh
docker compose logs -f cloudflared traefik
```

启动演示服务：

```sh
make demo
```

访问：

```text
https://api.example.com
https://test-api.example.com
```

## 为什么是 http://traefik:80

`traefik` 是 Docker Compose 内部服务名。`cloudflared` 和 Traefik 在同一个 Docker 网络中，所以 cloudflared 可以访问：

```text
http://traefik:80
```

不要填 `http://localhost:80`。在 cloudflared 容器里，`localhost` 指的是 cloudflared 容器自己。

## 常见问题

### 每个服务都要在 Cloudflare 里加一条 hostname 吗？

不需要。Cloudflare 只需要通配入口：

```text
*.example.com -> http://traefik:80
```

新增服务时只改 Docker labels 或 Traefik file provider。

### 可以创建多个 tunnel 吗？

可以，但不要让多套 EasyGate 同时接管同一个 hostname 或同一个 `*.example.com`。多设备部署建议先阅读 `docs/deployment-modes.md`。

### tunnel 凭据可以公开吗？

不可以。`<TUNNEL_ID>.json` 可以让 connector 加入你的 tunnel，应当只保存在本机或部署平台的 secret 中。
