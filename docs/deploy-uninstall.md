# 一键部署与卸载

EasyGate 提供跨平台部署和卸载脚本。

## 前置依赖

脚本会检查依赖是否存在。请先安装：

- Docker
- Docker Compose 插件

如果缺少 `cloudflared` CLI，一键部署脚本会自动下载到项目本地目录 `.easygate/bin/`，不会写入系统目录。

## 一键部署

macOS / Linux：

```sh
./scripts/deploy.sh --domain example.com
```

Windows PowerShell：

```powershell
.\scripts\deploy.ps1 -Domain example.com
```

常用选项：

```sh
./scripts/deploy.sh --domain example.com --tunnel easygate-home --demo
```

```powershell
.\scripts\deploy.ps1 -Domain example.com -Tunnel easygate-home -Demo
```

如果默认本地调试端口 `18080` 被占用，可以换成其他端口：

```sh
./scripts/deploy.sh --domain example.com --port 28080
```

```powershell
.\scripts\deploy.ps1 -Domain example.com -Port 28080
```

脚本会自动完成：

- 检查 Docker、Docker Compose。
- 如果缺少 `cloudflared`，自动下载项目本地 CLI。
- 如未登录 Cloudflare，执行 `cloudflared tunnel login`。
- 创建 Cloudflare Tunnel。
- 尝试创建 `*.example.com` 通配 DNS 路由。
- 写入 `.env`。
- 写入 `cloudflared/config.yml`。
- 复制 tunnel 凭据到 `cloudflared/`。
- 启动 EasyGate。
- 可选启动演示服务。

如果你已经通过包管理器安装并维护 `cloudflared`，也可以关闭自动安装：

```sh
./scripts/deploy.sh --domain example.com --no-install-cloudflared
```

```powershell
.\scripts\deploy.ps1 -Domain example.com -NoInstallCloudflared
```

如果自动创建 DNS 路由失败，可以在 Cloudflare DNS 中手动添加：

```text
Type:   CNAME
Name:   *
Target: <TUNNEL_ID>.cfargotunnel.com
Proxy:  Proxied
```

## 一键卸载

默认卸载只停止并移除 EasyGate 容器和网络，不删除本地配置或 tunnel 凭据。

macOS / Linux：

```sh
./scripts/uninstall.sh
```

Windows PowerShell：

```powershell
.\scripts\uninstall.ps1
```

## 彻底清理本地配置

macOS / Linux：

```sh
./scripts/uninstall.sh --purge
```

Windows PowerShell：

```powershell
.\scripts\uninstall.ps1 -Purge
```

彻底清理会删除：

- `.env`
- `.easygate/`
- `cloudflared/config.yml`
- `cloudflared/*.json`

脚本不会自动删除 Cloudflare 侧的 DNS 记录或 tunnel。如果确认不再使用，请手动删除 Cloudflare 侧资源。
