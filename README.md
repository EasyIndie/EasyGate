# EasyGate

[![CI](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml)

EasyGate 是一个面向家庭 NAT、家庭实验室和一人公司的轻量入口网关。它使用 Cloudflare Free + Cloudflare Tunnel 提供公网 HTTPS 入口，用 Traefik 自动发现和分发本地服务。

你只需要维护服务名和端口，不需要为每个服务反复配置反向代理、证书和路由器端口转发。

```text
浏览器 -> Cloudflare HTTPS -> Cloudflare Tunnel -> Traefik -> Docker / localhost / 局域网服务
```

## 适合什么场景

- 家庭 NAT 下没有公网 IP，或者不想开放路由器 80/443。
- 服务数量多，后续还会持续增加。
- 服务既有 Docker 容器，也有本机端口或局域网设备服务。
- 希望尽量使用 Cloudflare Free，不引入 VPS、Kubernetes 或自建证书体系。

不适合把 Cloudflare Free 当成大文件分发、公开视频流媒体或高带宽下载出口。

## 核心能力

- **统一 HTTPS 入口**：公网 TLS 由 Cloudflare 处理，本地服务可以继续跑 HTTP。
- **无需路由器端口转发**：`cloudflared` 主动出站连接 Cloudflare。
- **Docker 自动发现**：容器通过 Traefik labels 自动接入。
- **非 Docker 服务接入**：Traefik file provider 可以转发到 `localhost` 或局域网 IP。
- **测试环境约定**：生产用 `service.example.com`，测试用 `test-service.example.com`。
- **跨平台部署**：支持 macOS、Linux、Windows 11。

## 部署前准备

1. 准备一个域名，并使用 Cloudflare Full DNS setup。
2. 在 Cloudflare 保持 Universal SSL 开启。
3. 使用 `cloudflared` CLI 创建 Cloudflare Tunnel。
4. 配置通配入口：

   ```text
   *.example.com -> http://traefik:80
   ```

如果你的域名还在普通 DNS 服务商或云厂商 DNS 上，需要先把权威 DNS 切到 Cloudflare。迁移含义是“DNS 解析迁移”，不是必须把域名注册商也转走。

- 百度云域名迁移可以参考：[docs/baidu-domain-to-cloudflare.md](docs/baidu-domain-to-cloudflare.md)。
- 切换稳定前建议保留原平台解析记录，确认无误后再清理。

Cloudflare Tunnel 创建步骤见：[docs/create-cloudflare-tunnel.md](docs/create-cloudflare-tunnel.md)。

如果 Cloudflare DNS 里已有一部分域名不需要进入 EasyGate，请保留它们的具体 DNS 记录。具体记录优先于 `*.example.com` 通配入口，通配入口只会接管未单独配置的子域名。

## 域名约定

Cloudflare Free 的 Universal SSL 在 Full DNS setup 下最省事的覆盖方式是根域名和一级子域名，所以推荐：

```text
生产环境：api.example.com
测试环境：test-api.example.com
```

避免使用：

```text
test.api.example.com
```

这种更深层级子域名可能超出免费证书默认覆盖范围。

## 快速部署

1. 创建 tunnel：

   ```sh
   cloudflared tunnel login
   cloudflared tunnel create easygate-home
   cloudflared tunnel route dns easygate-home "*.example.com"
   ```

2. 配置 EasyGate：

   ```sh
   cp .env.example .env
   cp cloudflared/config.yml.example cloudflared/config.yml
   ```

3. 编辑：

   ```text
   .env
   cloudflared/config.yml
   ```

4. 将 `<TUNNEL_ID>.json` 放入：

   ```text
   cloudflared/
   ```

5. 启动：

   ```sh
   make up
   ```

## 常用命令

```sh
make up      # 启动核心服务
make logs    # 查看 Traefik 和 cloudflared 日志
make ps      # 查看容器状态
make demo    # 启动演示服务
make down    # 停止服务
make cleanup # 清理容器和网络，保留本地配置
make purge   # 删除本地生成配置和 tunnel 凭据
make test    # 运行测试
```

演示服务启动后可以访问：

```text
https://api.example.com
https://test-api.example.com
```

把 `example.com` 替换成你的真实域名。

## 添加 Docker 服务

把服务加入共享的 `easygate-proxy` Docker 网络，并添加 Traefik labels：

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

测试服务只需要换成 `test-` 前缀：

```yaml
- traefik.http.routers.test-app.rule=Host(`test-app.example.com`)
```

完整示例见：[examples/docker-service.compose.yml](examples/docker-service.compose.yml)。

## 添加非 Docker 服务

对于直接运行在宿主机上的服务，编辑：

```text
traefik/dynamic/localhost-services.yml
```

示例：

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

如果服务在局域网其他设备上，也可以转发到它的局域网地址：

```yaml
servers:
  - url: http://192.168.1.50:8080
```

Traefik 会监听动态配置目录并自动重载。

## 多设备部署建议

最推荐：只在一台稳定设备上部署 EasyGate，让它反代局域网内其他设备服务。

```text
Cloudflare Tunnel -> 入口设备 Traefik -> 局域网其他设备
```

不建议多台设备同时接管同一个 `*.example.com`。如果确实需要多入口，每台设备应使用不重叠的一级子域名，例如：

```text
nas-api.example.com
mini-api.example.com
test-nas-api.example.com
test-mini-api.example.com
```

更多说明见：[docs/deployment-modes.md](docs/deployment-modes.md)。

## 测试

本地测试：

```sh
make test
```

Windows 11 PowerShell：

```powershell
.\scripts\test.ps1
```

GitHub Actions 会在 Ubuntu、macOS、Windows 上运行 CI，防止脚本、Compose 配置、文档链接和跨平台入口被改坏。

## 文档索引

- [Cloudflare 配置清单](docs/cloudflare-checklist.md)
- [创建 Cloudflare Tunnel](docs/create-cloudflare-tunnel.md)
- [Cloudflare Free 限制说明](docs/cloudflare-free-limits.md)
- [清理部署](docs/cleanup.md)
- [部署模式](docs/deployment-modes.md)
- [平台兼容性](docs/platform-compatibility.md)
- [与已有 nginx 共存](docs/nginx-compatibility.md)
- [百度云域名迁移到 Cloudflare 示例](docs/baidu-domain-to-cloudflare.md)
- [自动化测试](docs/testing.md)

## 运维提醒

- 不要为 EasyGate 开放路由器 80/443 入站端口。
- `cloudflared` 凭据文件不要提交到 Git。
- 如果设备上已有 nginx，保持 EasyGate 默认 `8080:80` 映射即可共存。
