# 原生部署模式

原生模式适合不想在入口设备上运行 Docker 的场景。它直接运行本机 `traefik` 和 `cloudflared` 二进制，Traefik 只启用 file provider，不启用 Docker provider。

当前实现是运行时目录托管进程模式：

- macOS / Linux：`easygate native deploy` 后台启动进程并写入 `EASYGATE_HOME/run/*.pid`。
- Windows：`easygate.ps1 native deploy` 使用 `Start-Process` 启动进程并写入 `EASYGATE_HOME\run\*.pid`。
- 运行配置写入 `EASYGATE_HOME/native/`。
- 原生 tunnel 配置写入 `EASYGATE_HOME/cloudflared/config.native.yml`，不会覆盖 Docker Compose 模式的 `config.yml`。

如果需要开机自启，可以在验收通过后把生成的命令接入 `systemd`、launchd、Windows Task Scheduler 或 Windows Service。项目脚本不直接写系统服务，避免跨平台权限差异。

## 重复部署与互斥

同一模式重复部署是允许的。原生部署脚本会先停止 `EASYGATE_HOME/run/*.pid` 中记录的旧进程，再重新生成配置并启动新进程。

原生模式和 Docker Compose 模式不能同时运行：

- 原生部署脚本发现 Compose 模式的 `traefik` 或 `cloudflared` 正在运行时，会拒绝继续部署。
- Docker Compose 部署脚本发现原生模式 PID 仍在运行时，会拒绝继续部署。

切换模式前先执行对应清理命令：

```sh
easygate cleanup
easygate native cleanup
```

## 部署

macOS / Linux：

```sh
easygate native deploy --domain example.com
```

Windows PowerShell：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com
```

脚本会：

- 按需准备 `traefik` CLI。
- 按需准备 `cloudflared` CLI。
- 引导 Cloudflare 登录。
- 创建或复用 Cloudflare Tunnel。
- 尝试创建 `*.example.com` 通配 DNS 路由。
- 写入 `EASYGATE_HOME/native/.env`、`EASYGATE_HOME/native/traefik.yml`、`EASYGATE_HOME/native/dynamic/services.yml`。
- 写入 `EASYGATE_HOME/cloudflared/config.native.yml`。
- 启动原生 `traefik` 和 `cloudflared` 进程。

常用参数：

```sh
easygate native deploy --domain example.com --demo
easygate native deploy --domain example.com --port 28080
easygate native deploy --domain example.com --skip-route
easygate native deploy --domain example.com --no-install-traefik
easygate native deploy --domain example.com --no-install-cloudflared
```

Windows：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com -Demo
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com -Port 28080
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com -SkipRoute
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com -NoInstallTraefik
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native deploy -Domain example.com -NoInstallCloudflared
```

## 接入服务

原生模式没有 Docker labels 自动发现能力。所有路由都通过 file provider 管理：

```text
EASYGATE_HOME/native/dynamic/services.yml
```

示例：

```yaml
http:
  routers:
    local-api:
      rule: Host(`api.example.com`)
      entryPoints:
        - web
      service: local-api

  services:
    local-api:
      loadBalancer:
        servers:
          - url: http://127.0.0.1:8080
```

Traefik 会监听这个目录并热加载配置。

## 本机验收

macOS / Linux：

```sh
make local-acceptance-native
```

Windows PowerShell：

```powershell
.\scripts\local-acceptance-native.ps1
```

本机验收只启动原生 Traefik 和 demo HTTP 服务，不启动 `cloudflared`，也不需要真实域名或 tunnel 凭据。

## 清理

停止原生模式进程，保留配置、日志和 tunnel 凭据：

```sh
easygate native cleanup
```

Windows：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native cleanup
```

删除原生模式本地运行配置：

```sh
easygate native cleanup --purge
```

Windows：

```powershell
& "$env:LOCALAPPDATA\EasyGate\bin\easygate.ps1" native cleanup -Purge
```

`purge-native` 会删除：

- `EASYGATE_HOME/native/`
- `EASYGATE_HOME/run/`
- `EASYGATE_HOME/logs/`
- `EASYGATE_HOME/cloudflared/config.native.yml`

不会删除 `EASYGATE_HOME/cloudflared/*.json` tunnel 凭据，也不会删除 Cloudflare 侧 DNS 记录或 tunnel。
