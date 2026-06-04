# EasyGate

[![CI](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml)

EasyGate 是一个面向家庭 NAT、家庭实验室和一人公司的轻量入口网关。它用 Cloudflare Free + Cloudflare Tunnel 提供公网 HTTPS 入口，用 Traefik 在本地分发 Docker、宿主机和局域网服务。

```text
浏览器 -> Cloudflare HTTPS -> Cloudflare Tunnel -> Traefik -> 本地服务
```

公网 TLS 由 Cloudflare 处理，本地服务可以继续使用 HTTP。部署设备不需要公网 IP，也不需要开放路由器 80/443 入站端口。

## 当前能力

- Cloudflare Tunnel 出站连接，避免家庭 NAT 和路由器端口转发。
- Traefik Docker provider 自动发现带 labels 的容器服务。
- Traefik file provider 接入宿主机端口或局域网 IP 服务。
- 默认使用一级子域名：`service.example.com`、`test-service.example.com`。
- 提供 macOS / Linux Bash 脚本和 Windows PowerShell 脚本。
- 提供 demo 服务、本机验收脚本、清理脚本和 CI 检查。

不适合把 Cloudflare Free 当作大文件分发、公开网盘、公开视频流或持续高带宽出口。限制说明见 [docs/cloudflare-free-limits.md](docs/cloudflare-free-limits.md)。

## 前置条件

1. 域名使用 Cloudflare Full DNS setup，权威 nameserver 已切到 Cloudflare。
2. Cloudflare Universal SSL 保持开启。
3. 部署设备已安装 Docker 和 Docker Compose 插件。
4. 部署设备能访问 Cloudflare API 和 Tunnel 网络。

EasyGate 不会安装 Docker。部署脚本在缺少 `cloudflared` CLI 时会下载到项目本地 `.easygate/bin/`。

如果域名刚迁移到 Cloudflare，DNS 传播可能需要几分钟到数小时。可以用以下命令确认：

```sh
dig @1.1.1.1 example.com NS +short
dig @1.1.1.1 api.example.com A +short
```

## 快速部署

macOS / Linux：

```sh
./scripts/deploy.sh --domain example.com
```

Windows PowerShell：

```powershell
.\scripts\deploy.ps1 -Domain example.com
```

脚本会完成：

- 检查 Docker 和 Docker Compose。
- 按需准备 `cloudflared` CLI。
- 引导 Cloudflare 登录。
- 创建或复用 Cloudflare Tunnel。
- 尝试创建 `*.example.com` 通配 DNS 路由。
- 写入 `.env` 和 `cloudflared/config.yml`。
- 复制 tunnel 凭据到 `cloudflared/`。
- 启动 `traefik` 和 `cloudflared`。

常用选项：

```sh
./scripts/deploy.sh --domain example.com --demo
./scripts/deploy.sh --domain example.com --port 28080
./scripts/deploy.sh --domain example.com --no-install-cloudflared
./scripts/deploy.sh --domain example.com --skip-route
```

Windows 对应参数：

```powershell
.\scripts\deploy.ps1 -Domain example.com -Demo
.\scripts\deploy.ps1 -Domain example.com -Port 28080
.\scripts\deploy.ps1 -Domain example.com -NoInstallCloudflared
.\scripts\deploy.ps1 -Domain example.com -SkipRoute
```

部署后查看状态：

```sh
docker compose ps
docker compose logs -f traefik cloudflared
```

## Demo 验收

启动 demo：

```sh
make demo
```

访问：

```text
https://api.example.com
https://test-api.example.com
```

预期看到 `traefik/whoami` 返回的 `Hostname:`、`IP:`、`RemoteAddr:` 等文本。

本地不经过 Cloudflare 的路由验证：

```sh
curl -H "Host: api.example.com" http://127.0.0.1:18080
curl -H "Host: test-api.example.com" http://127.0.0.1:18080
```

验收完成后只移除 demo 服务，保留 EasyGate 基础入口：

```sh
docker compose --profile demo stop demo-api demo-test-api
docker compose --profile demo rm -f demo-api demo-test-api
```

完整验收说明见 [docs/local-acceptance.md](docs/local-acceptance.md)。

## 常用命令

```sh
make up                # 启动 Traefik 和 cloudflared
make demo              # 启动 demo 服务
make ps                # 查看容器状态
make logs              # 查看核心服务日志
make config            # 渲染 Compose 配置
make down              # 停止并移除 Compose 容器和网络
make cleanup           # 同 make down，保留本地配置和凭据
make purge             # 删除本地生成配置、本地 CLI 和 tunnel 凭据
make test              # 静态检查
make behavior-test     # 部署和清理脚本行为测试
make local-acceptance  # 本机路由验收
```

## 接入 Docker 服务

服务容器加入共享网络 `easygate-proxy`，并添加 Traefik labels：

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

测试服务推荐用 `test-` 前缀：

```yaml
- traefik.http.routers.test-app.rule=Host(`test-app.example.com`)
```

完整示例见 [examples/docker-service.compose.yml](examples/docker-service.compose.yml)。

## 接入非 Docker 服务

编辑：

```text
traefik/dynamic/localhost-services.yml
```

宿主机端口示例：

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
          - url: http://host.docker.internal:8080
```

局域网设备服务可以写成：

```yaml
servers:
  - url: http://192.168.1.50:8080
```

Traefik 会监听动态配置目录并自动重载。

## 域名约定

Cloudflare Free 的 Universal SSL 默认覆盖根域名和一级子域名。推荐：

```text
api.example.com
test-api.example.com
```

避免依赖更深层级域名：

```text
test.api.example.com
```

如果 Cloudflare DNS 里已有不需要进入 EasyGate 的具体记录，保留它们即可。具体记录优先于 `*.example.com` 通配记录。

## 清理

停止并移除 EasyGate 容器和网络，保留 `.env`、`cloudflared/config.yml` 和 tunnel 凭据：

```sh
make cleanup
```

彻底删除本地生成配置、本地 CLI 和 tunnel 凭据：

```sh
make purge
```

清理脚本不会删除 Cloudflare 上的 DNS 记录或 tunnel。更多说明见 [docs/cleanup.md](docs/cleanup.md)。

## 文档

- [一键部署与清理](docs/deploy-uninstall.md)
- [Cloudflare 配置清单](docs/cloudflare-checklist.md)
- [创建 Cloudflare Tunnel](docs/create-cloudflare-tunnel.md)
- [本机测试验收](docs/local-acceptance.md)
- [部署模式](docs/deployment-modes.md)
- [与已有 nginx 共存](docs/nginx-compatibility.md)
- [平台兼容性](docs/platform-compatibility.md)
- [自动化测试](docs/testing.md)
- [百度云域名迁移到 Cloudflare](docs/baidu-domain-to-cloudflare.md)
