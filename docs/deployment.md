# 部署指南

## 前置条件

1. 域名使用 Cloudflare Full DNS（权威 nameserver 已切到 Cloudflare）。
2. Cloudflare Universal SSL 保持开启。
3. 部署设备能访问 Cloudflare API 和 Tunnel 网络。
4. Docker Compose 模式需要 Docker + Docker Compose 插件。原生模式不需要。

EasyGate **不会**安装 Docker。部署脚本在缺少 `cloudflared`（或原生模式的 `traefik`）时会自动下载。

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash
```

安装后 CLI 在 `~/.easygate/bin/easygate`，自动加入 PATH，即装即用。

Windows：
```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.ps1 -OutFile $env:TEMP\easygate-install.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\easygate-install.ps1
```

## 部署

### Docker Compose 模式（推荐）

```sh
easygate deploy --domain example.com
```

脚本自动完成：检查 Docker → 安装 cloudflared → Cloudflare 登录 → 创建/复用 Tunnel → DNS 路由 → 生成配置 → 启动服务。

**常用选项：**

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--domain` | 主域名 | 交互式输入 |
| `--tunnel` | Tunnel 名称 | `easygate-home` |
| `--dashboard` | Dashboard 域名 | `traefik.<domain>` |
| `--port` | 本地调试端口 | `18080` |
| `--demo` | 部署后启动 demo 服务 | 否 |
| `--skip-route` | 不自动创建 DNS 路由 | 否 |
| `--no-install-cloudflared` | 不自动下载 cloudflared | 否 |

### 原生模式（无 Docker）

适用于不想安装 Docker 的设备。自动下载 Traefik 二进制，配置写入 `~/.easygate/native/`（Linux/macOS）或 `%LOCALAPPDATA%\EasyGate\native\`（Windows），启动后台进程并注册系统服务，设备重启后自动恢复：

- **Linux**：注册 systemd user service
- **macOS**：注册 LaunchAgent
- **Windows**：注册计划任务（用户登录时自动启动）

**macOS / Linux：**
```sh
easygate deploy --native --domain example.com
```

**Windows：**
```powershell
easygate.ps1 deploy -Native -Domain example.com
```

> `install.ps1` 已自动将 EasyGate 目录添加到 PATH，新终端窗口可直接使用 `easygate.ps1` 命令。

**额外选项：**

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--api-port` | demo api 端口 | `19080` |
| `--test-api-port` | demo test-api 端口 | `19081` |
| `--local-only` | 仅启动 Traefik，不启动 cloudflared | 否 |
| `--no-install-cloudflared` | 不自动下载 cloudflared | 否 |
| `--no-install-traefik` | 不自动下载 Traefik | 否 |

**macOS / Linux：**
```sh
easygate deploy --native --domain example.com --demo --local-only
```

**Windows：**
```powershell
easygate.ps1 deploy -Native -Domain example.com -Demo -LocalOnly
```

## 服务管理

所有命令自动检测部署模式。Windows 用户将 `easygate` 替换为 `easygate.ps1`：

```sh
easygate start          # 启动服务
easygate stop           # 停止服务（保留配置和凭据）
easygate restart        # 重启服务
easygate ps             # 查看状态
easygate logs           # 查看日志
easygate config         # 查看配置
easygate version        # 显示版本号
easygate home           # 显示运行时目录路径
```

Windows 也可通过计划任务手动触发：
```powershell
schtasks /run /tn EasyGate        # 触发自动启动
schtasks /end /tn EasyGate        # 停止任务进程
```

## Demo 服务

两种模式均支持，自动检测：

```sh
easygate demo start     # 启动 demo（api + test-api）
easygate demo stop      # 停止并移除 demo
easygate demo restart   # 重启 demo
```

Windows 用户将 `easygate` 替换为 `easygate.ps1`，命令相同。

部署后访问 `https://api.example.com` 和 `https://test-api.example.com`，预期看到 `traefik/whoami` 返回的 `Hostname:`、`IP:` 等信息。

## 接入服务

### 自定义服务（推荐）

使用 `easygate service` 命令，自动检测部署模式：

```sh
easygate service add --name my-app --host app.example.com --url http://192.168.1.100:8080
easygate service list
easygate service remove my-app
```

配置即时生效，Traefik 自动热加载。

### Docker 服务

让容器加入共享网络并添加 Traefik labels：

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

完整示例见 `examples/docker-service.compose.yml`。

### 非 Docker 服务（手动配置）

编辑 `~/.easygate/traefik/dynamic/localhost-services.yml`（Docker 模式）或 `~/.easygate/native/dynamic/services.yml`（原生模式）：

```yaml
http:
  routers:
    local-api:
      rule: Host(`local-api.example.com`)
      entryPoints: [web]
      service: local-api
  services:
    local-api:
      loadBalancer:
        servers:
          - url: http://192.168.1.50:8080
```

Traefik 监听配置目录并自动热重载。

## 域名约定

Cloudflare Free 的 Universal SSL 通配证书只覆盖根域名和一级子域名：

```
✅ api.example.com
❌ test.api.example.com     （二级子域名，证书不匹配）
❌ api.nas-home.example.com （二级子域名，证书不匹配）
```

## 清理

```sh
easygate uninstall         # 停止服务 + 删除全部数据 + 清理 shell PATH
```

清理不会删除 Cloudflare 上的 DNS 记录或 Tunnel——需用 `cloudflared` CLI 或 Dashboard 手动处理。

## 运行时目录

| 平台 | 默认路径 |
|------|---------|
| macOS / Linux | `~/.easygate` |
| Windows | `%LOCALAPPDATA%\EasyGate` |

```
~/.easygate/
├── bin/              CLI 和运行时二进制
├── lib/              辅助脚本（service-helper.py 等）
├── compose/          运行时 Docker Compose 配置
├── native/           原生模式 Traefik 配置与动态服务
├── cloudflared/     Tunnel 凭据和配置
├── run/              PID 文件
├── logs/             日志（自动轮转，单文件上限 10MB）
└── traefik/          Docker 模式 Traefik 配置
```

## 安全加固

Docker Compose 模式默认应用以下安全措施：
- `read_only: true` —— 容器文件系统只读
- `cap_drop: ALL` —— 移除所有 Linux capabilities（Traefik 保留 `NET_BIND_SERVICE`）
- 资源限制 —— 每个容器有内存上限和预留值

cloudflared 镜像固定为 `2025.2.1`（非 `:latest`）。

Release 版本的 `install.sh` 内置 CLI 校验和，安装时自动验证文件完整性。
