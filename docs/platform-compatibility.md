# 平台兼容性

## 结论

EasyGate 的 Docker Compose 项目可以兼容：

- macOS
- Linux
- Windows 11

推荐部署方式：

- macOS：Docker Desktop + standalone CLI
- Linux：Docker Engine + Docker Compose 插件 + standalone CLI
- Windows 11：Docker Desktop + WSL2 后端 + PowerShell standalone CLI

不能使用 Docker 时，三类平台都可以使用原生部署脚本：

- macOS / Linux：`easygate native deploy --domain example.com`
- Windows 11：`%LOCALAPPDATA%\EasyGate\bin\easygate.ps1 native deploy -Domain example.com`

Tunnel 创建步骤见 `docs/create-cloudflare-tunnel.md`。

EasyGate 不会自动安装 Docker 或 Docker Compose。部署脚本会在缺少 `cloudflared` CLI 时自动下载到 `EASYGATE_HOME/bin`。
原生部署脚本还会在缺少 Traefik CLI 时自动下载到 `EASYGATE_HOME/bin`。

## macOS

要求：

- Docker Desktop
- Docker Compose 插件
- Bash

运行：

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash -s -- deploy --domain example.com
```

## Linux

要求：

- Docker Engine
- Docker Compose 插件，也就是支持 `docker compose`
- Bash

运行：

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash -s -- deploy --domain example.com
```

如果使用普通用户运行 Docker，需要确保当前用户有权限访问 Docker daemon。

## Windows 11

推荐要求：

- Docker Desktop for Windows
- 启用 WSL2 backend
- PowerShell 5.1 或 PowerShell 7+

运行：

```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.ps1 -OutFile $env:TEMP\easygate-install.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\easygate-install.ps1 deploy -Domain example.com
```

如果 PowerShell 阻止脚本执行，可以在当前会话中临时允许：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\test.ps1
```

也可以在 WSL2 发行版中使用 Linux 方式运行：

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash -s -- deploy --domain example.com
```

## Windows 11 注意事项

- 推荐使用 Docker Desktop 的 Linux containers 模式。
- 项目目录建议放在 WSL2 文件系统或 Windows 用户目录下，不要放在权限复杂的系统目录。
- 当前 Compose 模板使用 `/var/run/docker.sock` 让 Traefik 读取 Docker 事件。Docker Desktop 的 Linux containers 模式可以支持这个用法。
- 如果使用 Windows containers，本项目不作为目标支持。

## 测试脚本兼容性

- `scripts/test.sh`：面向 macOS、Linux、WSL2。
- `scripts/test.ps1`：面向 Windows 11 PowerShell。
- 两个脚本都会检查关键文件、脚本语法、配置命名和文档链接。
