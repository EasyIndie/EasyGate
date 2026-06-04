# 平台兼容性

## 结论

EasyGate 的 Docker Compose 项目可以兼容：

- macOS
- Linux
- Windows 11

推荐部署方式：

- macOS：Docker Desktop + `scripts/bootstrap.sh`
- Linux：Docker Engine + Docker Compose 插件 + `scripts/bootstrap.sh`
- Windows 11：Docker Desktop + WSL2 后端 + `scripts/bootstrap.ps1`

## macOS

要求：

- Docker Desktop
- Docker Compose 插件
- Bash

运行：

```sh
./scripts/bootstrap.sh
```

## Linux

要求：

- Docker Engine
- Docker Compose 插件，也就是支持 `docker compose`
- Bash

运行：

```sh
./scripts/bootstrap.sh
```

如果使用普通用户运行 Docker，需要确保当前用户有权限访问 Docker daemon。

## Windows 11

推荐要求：

- Docker Desktop for Windows
- 启用 WSL2 backend
- PowerShell 5.1 或 PowerShell 7+

运行：

```powershell
.\scripts\bootstrap.ps1
```

如果 PowerShell 阻止脚本执行，可以在当前会话中临时允许：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\bootstrap.ps1
```

也可以在 WSL2 发行版中使用 Linux 方式运行：

```sh
./scripts/bootstrap.sh
```

## Windows 11 注意事项

- 推荐使用 Docker Desktop 的 Linux containers 模式。
- 项目目录建议放在 WSL2 文件系统或 Windows 用户目录下，不要放在权限复杂的系统目录。
- 当前 Compose 模板使用 `/var/run/docker.sock` 让 Traefik 读取 Docker 事件。Docker Desktop 的 Linux containers 模式可以支持这个用法。
- 如果使用 Windows containers，本项目不作为目标支持。

## 脚本兼容性

- `scripts/bootstrap.sh`：面向 macOS、Linux、WSL2。
- `scripts/bootstrap.ps1`：面向 Windows 11 PowerShell。
- 两个脚本都不会覆盖已有 `.env`。
- 两个脚本都会检查 Docker Compose、校验 `.env`、启动核心服务，并可选启动演示服务。
