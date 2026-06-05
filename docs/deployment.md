# 部署指南

## 前置条件

1. 域名使用 Cloudflare Full DNS（权威 nameserver 已切到 Cloudflare）。
2. Cloudflare Universal SSL 保持开启。
3. 部署设备能访问 Cloudflare API 和 Tunnel 网络。
4. Docker Compose 模式需要 Docker + Docker Compose 插件。原生模式不需要 Docker。

EasyGate **不会**安装 Docker。部署脚本在缺少 `cloudflared`（或原生模式的 `traefik`）时会自动下载到运行时目录，不写入源码仓库。

## 两种部署模式

| | Docker Compose | 原生 |
|---|---|---|
| 依赖 | Docker | 仅操作系统 |
| Traefik | 容器 `traefik:v3.1` | 本地二进制 `v3.1.7` |
| 服务发现 | Docker provider（自动发现 label 容器）+ file provider | file provider（纯静态配置） |
| 适用场景 | 推荐，自动发现服务 | 不需要 Docker，手动配置路由 |
| 命令 | `easygate deploy ...` | `easygate native deploy ...` |

两种模式**互斥**——不能同时运行。部署脚本会自动检测并阻止冲突。

## 安装独立 CLI

不需要 clone 源码仓库，一行安装：

**macOS / Linux：**
```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash
```

**Windows PowerShell：**
```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.ps1 -OutFile $env:TEMP\easygate-install.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\easygate-install.ps1
```

安装后 CLI 位于 `EASYGATE_HOME/bin/easygate`。默认路径：

| 平台 | 默认 EASYGATE_HOME |
|------|-------------------|
| macOS | `~/Library/Application Support/EasyGate` |
| Linux | `~/.local/share/easygate` |
| Windows | `%LOCALAPPDATA%\EasyGate` |

用 `EASYGATE_HOME` 环境变量可自定义位置。

## Docker Compose 部署

```sh
easygate deploy --domain example.com
```

脚本会完成：
- 检查 Docker 和 Docker Compose
- 按需安装 `cloudflared` CLI 到运行时目录
- 引导 Cloudflare 登录（`cloudflared tunnel login`）
- 创建或复用 Cloudflare Tunnel（默认名 `easygate-home`）
- 创建 `*.example.com` 通配 DNS 路由
- 生成运行时 Compose、Traefik 和 cloudflared 配置
- 复制 tunnel 凭据到运行时目录
- 启动 `traefik` + `cloudflared`

### 常用选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--domain` | 主域名 | 交互式输入 |
| `--tunnel` | Tunnel 名称 | `easygate-home` |
| `--dashboard` | Dashboard 域名 | `traefik.<domain>` |
| `--port` | 本地调试端口 | `18080` |
| `--demo` | 部署后启动 demo 服务 | 否 |
| `--skip-route` | 不自动创建 DNS 路由 | 否 |
| `--no-install-cloudflared` | 不自动下载 cloudflared | 否 |

```sh
easygate deploy --domain example.com --demo --port 28080
```

## 原生部署（无 Docker）

```sh
easygate native deploy --domain example.com
```

适用于不想安装 Docker 的设备。会自动下载 Traefik 二进制到 `EASYGATE_HOME/bin/`（默认版本 `3.1.7`，可用 `EASYGATE_TRAEFIK_VERSION` 覆盖）。

与 Docker Compose 模式的区别：
- 不依赖 Docker 和 Docker provider
- Traefik 配置写入 `EASYGATE_HOME/native/traefik.yml`
- 动态路由写 `EASYGATE_HOME/native/dynamic/services.yml`
- cloudflared 配置写 `EASYGATE_HOME/cloudflared/config.native.yml`
- Traefik 和 cloudflared 作为后台进程运行，PID 文件在 `EASYGATE_HOME/run/`
- 日志输出到 `EASYGATE_HOME/logs/`

原生模式额外选项：

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--api-port` | demo api 端口 | `19080` |
| `--test-api-port` | demo test-api 端口 | `19081` |
| `--no-install-traefik` | 不自动下载 Traefik | 否 |
| `--local-only` | 仅启动 Traefik + demo，不启动 cloudflared | 否 |

```sh
easygate native deploy --domain example.com --demo --local-only
```

## 日常管理

```sh
easygate ps            # 查看容器状态
easygate logs          # 查看核心日志（traefik + cloudflared）
easygate config        # 渲染 Compose 配置
easygate up            # 启动已停止的栈
easygate down          # 停止栈（保留配置）
easygate home          # 显示 EASYGATE_HOME 路径
easygate version       # 显示版本号
easygate native logs   # 原生模式日志
```

## 接入服务

### Docker 服务

让服务容器加入共享网络 `easygate-proxy` 并添加 Traefik labels：

```yaml
services:
  app:
    image: your-image:latest
    networks:
      - easygate-proxy
    labels:
      - traefik.enable=true
      - traefik.docker.network=easygate-proxy
      - traefik.http.routers.app.rule=Host(`app.example.com`)
      - traefik.http.routers.app.entrypoints=web
      - traefik.http.services.app.loadbalancer.server.port=3000

networks:
  easygate-proxy:
    external: true
```

测试服务推荐用 `test-` 前缀：`test-app.example.com`。

完整示例见 `examples/docker-service.compose.yml`。

### 非 Docker 服务

编辑 `EASYGATE_HOME/traefik/dynamic/localhost-services.yml`（Docker 模式）或 `EASYGATE_HOME/native/dynamic/services.yml`（原生模式）：

```yaml
http:
  routers:
    local-api:
      rule: Host(`local-api.example.com`)
      entryPoints:
        - web
      service: local-api

  services:
    local-api:
      loadBalancer:
        servers:
          - url: http://192.168.1.50:8080
```

Traefik 监听配置目录并自动热重载。

## 域名约定

Cloudflare Free 的 Universal SSL 通配证书**只覆盖根域名和一级子域名**：

```
✅ api.example.com
✅ test-api.example.com
❌ test.api.example.com        （二级子域名，证书不匹配）
❌ api.nas-home.example.com    （二级子域名，证书不匹配）
```

如果 Cloudflare DNS 已有不需要走 EasyGate 的具体记录，保留即可——具体记录优先于 `*.example.com` 通配。

## 平台兼容性

所有脚本同时提供 Bash (`.sh`) 和 PowerShell (`.ps1`) 版本。遵循以下惯例：

| 操作 | macOS / Linux | Windows |
|------|--------------|---------|
| 安装 CLI | `bash install.sh` | `powershell -File install.ps1` |
| 部署 | `easygate deploy` 或 `./scripts/deploy.sh` | `easygate.ps1 deploy` 或 `.\scripts\deploy.ps1` |
| 清理 | `easygate cleanup` | `easygate.ps1 cleanup` |
| 原生部署 | `easygate native deploy` | `easygate.ps1 native deploy` |

Windows 上需要注意：
- 入口脚本是 `%LOCALAPPDATA%\EasyGate\bin\easygate.ps1`
- 部署前可能需要 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
- 文件路径使用 Windows 风格，脚本内部自动适配
- PowerShell 7 对 `ValueFromRemainingArguments` 有已知兼容性问题——独立 CLI 的位置子命令（如 `deploy`）在 Bash CI 中覆盖测试

## 清理

停止并移除容器/进程，保留配置和凭据：

```sh
easygate cleanup                 # Docker Compose 模式
easygate native cleanup          # 原生模式
```

彻底删除所有本地数据（包括配置、凭据、二进制）：

```sh
easygate cleanup --purge         # Docker Compose 模式（需确认 yes）
easygate native cleanup --purge  # 原生模式
```

卸载 CLI 二进制：

```sh
easygate uninstall               # 先 cleanup 再删 CLI
```

清理操作**不会删除** Cloudflare 上的 DNS 记录或 Tunnel。这些需要用 `cloudflared` CLI 或 Cloudflare Dashboard 手动处理。
