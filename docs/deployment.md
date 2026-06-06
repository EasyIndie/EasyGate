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

### 原生模式（无 Docker）

```sh
easygate native deploy --domain example.com
```

适用于不想安装 Docker 的设备。自动下载 Traefik 二进制，配置写入 `~/.easygate/native/`，启动后台进程并注册系统服务（systemd/launchd），设备重启后自动恢复。

**额外选项：**

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--api-port` | demo api 端口 | `19080` |
| `--test-api-port` | demo test-api 端口 | `19081` |
| `--local-only` | 仅启动 Traefik，不启动 cloudflared | 否 |

```sh
easygate native deploy --domain example.com --demo --local-only
```

## 服务管理

```sh
easygate start          # 启动服务
easygate stop           # 停止服务（保留配置和凭据）
easygate restart        # 重启服务
easygate ps             # 查看状态（compose: 容器状态 / native: PID 列表）
easygate logs           # 查看日志
easygate native logs    # 原生模式日志
easygate config         # 渲染 Compose 配置（仅 Docker 模式）
easygate home           # 显示 ~/.easygate 路径
easygate version        # 显示版本号
```

## Demo 服务

```sh
easygate demo start     # 启动 demo（api + test-api）
easygate demo stop      # 停止并移除 demo
easygate demo restart   # 重启 demo
```

部署后访问 `https://api.example.com` 和 `https://test-api.example.com`，预期看到 `traefik/whoami` 返回的 `Hostname:`、`IP:` 等信息。

## 接入服务

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

### 非 Docker 服务

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
easygate purge             # 停止服务 + 删除全部本地数据（需确认 yes）
easygate uninstall         # 停止服务 + 删除 CLI + 清理 shell PATH
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
├── compose/          运行时 Docker Compose 配置
├── native/           原生模式 Traefik 配置
├── cloudflared/     Tunnel 凭据和配置
├── run/              PID 文件
├── logs/             日志
└── traefik/          Docker 模式 Traefik 配置
```

## 安全加固

Docker Compose 模式默认应用以下安全措施：
- `read_only: true` —— 容器文件系统只读
- `cap_drop: ALL` —— 移除所有 Linux capabilities（Traefik 保留 `NET_BIND_SERVICE`）
- 资源限制 —— 每个容器有内存上限和预留值

cloudflared 镜像固定为 `2025.2.1`（非 `:latest`）。

Release 版本的 `install.sh` 内置 CLI 校验和，安装时自动验证文件完整性。
