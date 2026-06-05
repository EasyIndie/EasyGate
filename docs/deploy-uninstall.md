# 一键部署与清理

EasyGate 提供 macOS / Linux Bash 脚本和 Windows PowerShell 脚本。默认推荐 Docker Compose 模式；不能使用 Docker 时，可以使用原生部署模式。

## 前置依赖

Docker Compose 模式请先安装：

- Docker
- Docker Compose 插件，也就是支持 `docker compose`

部署脚本不会安装 Docker。如果缺少 `cloudflared` CLI，脚本会下载到 `EASYGATE_HOME/bin`，不会写入源码仓库或系统目录。

默认运行时目录：

- macOS: `~/Library/Application Support/EasyGate`
- Linux: `${XDG_DATA_HOME:-~/.local/share}/easygate`
- Windows: `%LOCALAPPDATA%\EasyGate`

可以用 `EASYGATE_HOME=/path/to/easygate` 覆盖。部署完成后，删除源码仓库不会影响已经生成的运行时配置、凭据和二进制。

## 部署

### Standalone CLI

不需要 clone 源码仓库，一行命令完成安装和部署：

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash -s -- deploy --domain example.com
```

显式指定运行时目录：

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | EASYGATE_HOME="$HOME/easygate" bash -s -- deploy --domain example.com
```

Windows PowerShell：

```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.ps1 -OutFile $env:TEMP\easygate-install.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\easygate-install.ps1 deploy -Domain example.com
```

后续维护：

```sh
easygate ps
easygate logs
easygate cleanup
easygate native deploy --domain example.com
easygate native cleanup
```

Windows 后续维护使用 `%LOCALAPPDATA%\EasyGate\bin\easygate.ps1`：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" ps
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" logs
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" cleanup
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native cleanup
```

### Docker Compose 模式

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
- 写入 `EASYGATE_HOME` 下的 Compose、Traefik 和 cloudflared 运行时配置。
- 启动 `traefik` 和 `cloudflared`。

常用参数：

```sh
./scripts/deploy.sh --domain example.com --tunnel easygate-home
./scripts/deploy.sh --domain example.com --demo
./scripts/deploy.sh --domain example.com --port 28080
./scripts/deploy.sh --domain example.com --skip-route
./scripts/deploy.sh --domain example.com --no-install-cloudflared
```

Windows standalone CLI：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" deploy -Domain example.com -Tunnel easygate-home
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" deploy -Domain example.com -Demo
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" deploy -Domain example.com -Port 28080
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" deploy -Domain example.com -SkipRoute
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" deploy -Domain example.com -NoInstallCloudflared
```

参数说明：

- `--demo` / `-Demo`：部署后启动 demo 服务。
- `--port` / `-Port`：修改宿主机本地调试端口，默认 `18080`。
- `--skip-route` / `-SkipRoute`：不自动创建 Cloudflare DNS 路由。
- `--no-install-cloudflared` / `-NoInstallCloudflared`：要求系统已有 `cloudflared`。

## 验证

```sh
easygate ps
easygate logs
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
easygate demo cleanup
```

## 停止并保留配置

停止并移除 EasyGate 容器和网络，保留 `EASYGATE_HOME` 下的配置、tunnel 凭据和 Cloudflare 侧资源：

```sh
easygate cleanup
```

源码仓库开发入口：

```sh
./scripts/cleanup.sh
```

Windows：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" cleanup
```

`scripts/uninstall.sh` 和 `scripts/uninstall.ps1` 只是转发到对应的 cleanup 脚本，保留它们是为了兼容旧命令。

## 彻底清理本地文件

确认不再使用这台机器上的本地配置后：

```sh
easygate cleanup --purge
```

Windows：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" cleanup -Purge
```

彻底清理会要求输入 `yes`，然后删除整个 `EASYGATE_HOME` 运行时目录。

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

## 原生部署模式

原生模式不要求 Docker。它直接运行本机 `traefik` 和 `cloudflared` 二进制，并通过 Traefik file provider 管理服务。

macOS / Linux：

```sh
easygate native deploy --domain example.com
```

Windows：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com
```

本机验收：

```sh
make local-acceptance-native
```

Windows：

```powershell
.\scripts\local-acceptance-native.ps1
```

停止原生进程：

```sh
easygate native cleanup
```

完整说明见 [native-deployment.md](native-deployment.md)。
