# 平台兼容性

## 结论

EasyGate 的 Docker Compose 项目可以兼容：

- macOS
- Linux
- Windows 11

推荐部署方式：

- macOS：Docker Desktop + `cloudflared` CLI + `make up`
- Linux：Docker Engine + Docker Compose 插件 + `cloudflared` CLI + `make up`
- Windows 11：Docker Desktop + WSL2 后端 + `cloudflared` CLI + PowerShell

Tunnel 创建步骤见 `docs/create-cloudflare-tunnel.md`。

EasyGate 不会自动安装 Docker、Docker Compose 或 `cloudflared`。请先按对应平台安装这些工具，再运行 `make up` 或 `docker compose up -d`。

## macOS

要求：

- Docker Desktop
- Docker Compose 插件
- Bash

运行：

```sh
make up
```

## Linux

要求：

- Docker Engine
- Docker Compose 插件，也就是支持 `docker compose`
- Bash

运行：

```sh
make up
```

如果使用普通用户运行 Docker，需要确保当前用户有权限访问 Docker daemon。

## Windows 11

推荐要求：

- Docker Desktop for Windows
- 启用 WSL2 backend
- PowerShell 5.1 或 PowerShell 7+

运行：

```powershell
docker compose up -d
```

如果 PowerShell 阻止脚本执行，可以在当前会话中临时允许：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\test.ps1
```

也可以在 WSL2 发行版中使用 Linux 方式运行：

```sh
make up
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
