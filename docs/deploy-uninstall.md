# 一键部署与清理

EasyGate 提供 macOS / Linux Bash 脚本和 Windows PowerShell 脚本。推荐优先使用脚本完成首次部署，手动配置只适合需要完全自管 `cloudflared` 的场景。

## 前置依赖

请先安装：

- Docker
- Docker Compose 插件，也就是支持 `docker compose`

部署脚本不会安装 Docker。如果缺少 `cloudflared` CLI，脚本会下载到项目本地 `.easygate/bin/`，不会写入系统目录。

## 部署

macOS / Linux：

```sh
./scripts/deploy.sh --domain example.com
```

Windows PowerShell：

```powershell
.\scripts\deploy.ps1 -Domain example.com
```

脚本会：

- 检查 Docker daemon 和 Compose 插件。
- 准备 `cloudflared` CLI。
- 如果本机没有 Cloudflare 登录凭据，引导执行 `cloudflared tunnel login`。
- 创建 Cloudflare Tunnel；如果同名 tunnel 已存在，复用本地最新 tunnel 凭据。
- 尝试创建 `*.example.com` 通配 DNS 路由。
- 写入 `.env` 和 `cloudflared/config.yml`。
- 启动 `traefik` 和 `cloudflared`。

常用参数：

```sh
./scripts/deploy.sh --domain example.com --tunnel easygate-home
./scripts/deploy.sh --domain example.com --demo
./scripts/deploy.sh --domain example.com --port 28080
./scripts/deploy.sh --domain example.com --skip-route
./scripts/deploy.sh --domain example.com --no-install-cloudflared
```

Windows：

```powershell
.\scripts\deploy.ps1 -Domain example.com -Tunnel easygate-home
.\scripts\deploy.ps1 -Domain example.com -Demo
.\scripts\deploy.ps1 -Domain example.com -Port 28080
.\scripts\deploy.ps1 -Domain example.com -SkipRoute
.\scripts\deploy.ps1 -Domain example.com -NoInstallCloudflared
```

参数说明：

- `--demo` / `-Demo`：部署后启动 demo 服务。
- `--port` / `-Port`：修改宿主机本地调试端口，默认 `18080`。
- `--skip-route` / `-SkipRoute`：不自动创建 Cloudflare DNS 路由。
- `--no-install-cloudflared` / `-NoInstallCloudflared`：要求系统已有 `cloudflared`。

## 验证

```sh
docker compose ps
docker compose logs -f traefik cloudflared
```

如果启动了 demo：

```text
https://api.example.com
https://test-api.example.com
```

DNS 刚迁移到 Cloudflare 时，可以用公共 DNS 检查：

```sh
dig @1.1.1.1 example.com NS +short
dig @1.1.1.1 api.example.com A +short
```

Cloudflare 橙云代理正常时，子域名通常会返回 Cloudflare IP，而不是你的家庭公网 IP。

## 只清理 demo

公网验收完成后，如果只想移除 demo，保留 EasyGate 基础入口：

```sh
docker compose --profile demo stop demo-api demo-test-api
docker compose --profile demo rm -f demo-api demo-test-api
```

## 停止并保留配置

停止并移除 EasyGate 容器和网络，保留 `.env`、`cloudflared/config.yml`、tunnel 凭据和 Cloudflare 侧资源：

```sh
make cleanup
```

或：

```sh
./scripts/cleanup.sh
```

Windows：

```powershell
.\scripts\cleanup.ps1
```

`scripts/uninstall.sh` 和 `scripts/uninstall.ps1` 只是转发到对应的 cleanup 脚本，保留它们是为了兼容旧命令。

## 彻底清理本地文件

确认不再使用这台机器上的本地配置后：

```sh
make purge
```

或：

```sh
./scripts/cleanup.sh --purge
```

Windows：

```powershell
.\scripts\cleanup.ps1 -Purge
```

彻底清理会要求输入 `yes`，然后删除：

- `.env`
- `.easygate/`
- `cloudflared/config.yml`
- `cloudflared/*.json`

不会删除 Cloudflare 上的 DNS 记录或 tunnel。

## 手动 DNS 路由

如果自动创建 DNS 路由失败，可以在 Cloudflare DNS 中手动添加：

```text
Type:   CNAME
Name:   *
Target: <TUNNEL_ID>.cfargotunnel.com
Proxy:  Proxied
```

已有具体记录会优先于通配记录。不要删除邮件、官网、CDN 等不需要进入 EasyGate 的具体 DNS 记录。
