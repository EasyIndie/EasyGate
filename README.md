# EasyGate

[![CI](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml)

EasyGate 是一个基于 Cloudflare Free + Traefik 的轻量入口网关，用于把家庭实验室或一人公司的多个服务通过 HTTPS 暴露到公网，并且不需要在路由器上做端口转发。

公网访问流量路径：

```text
浏览器 -> Cloudflare HTTPS -> Cloudflare Tunnel -> Traefik -> Docker 或 localhost 服务
```

## 域名约定

使用 Cloudflare Free 在 Full DNS setup 下可以被 Universal SSL 覆盖的主机名：

```text
生产环境：service.example.com
测试环境：test-service.example.com
```

在免费计划下避免使用 `test.service.example.com` 这类更深层级的域名，除非你额外购买或配置自定义证书覆盖。

## Cloudflare 配置

1. 使用 Full DNS setup，把域名的 nameserver 切换到 Cloudflare。
2. 保持 Universal SSL 开启。
3. 在 Cloudflare Zero Trust 中创建一个 remotely managed tunnel。
4. 添加一个 public hostname 路由：

   ```text
   *.example.com -> http://traefik:80
   ```

5. 把 tunnel token 填入 `.env`。
6. 为私有主机名添加 Cloudflare Access 策略：

   ```text
   test-*.example.com
   traefik.example.com
   admin.example.com
   grafana.example.com
   ```

Cloudflare Access 是测试环境、管理后台和内部工具的保护层。本模板中的 Traefik 只负责本地 HTTP 路由。

完整配置清单见 `docs/cloudflare-checklist.md`。
Cloudflare Free 的限制说明见 `docs/cloudflare-free-limits.md`。
如果部署设备上已有 nginx，共存说明见 `docs/nginx-compatibility.md`。
如果部分设备不能安装 Docker，部署模式说明见 `docs/deployment-modes.md`。
如果域名注册在百度云，迁移到 Cloudflare 的步骤见 `docs/baidu-domain-to-cloudflare.md`。
一键部署说明见 `docs/one-click-deploy.md`。
macOS、Linux、Windows 11 兼容性说明见 `docs/platform-compatibility.md`。
自动化测试说明见 `docs/testing.md`。

## 一键部署

首次部署推荐使用一键脚本：

```sh
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

Windows 11 PowerShell 使用：

```powershell
.\scripts\bootstrap.ps1
```

也可以通过 Makefile 运行：

```sh
make bootstrap
```

脚本会检查 Docker Compose、交互式生成 `.env`、校验配置，并启动 Traefik 和 cloudflared。已有 `.env` 时脚本不会覆盖。

## 手动运行

```sh
cp .env.example .env
# 编辑 .env：BASE_DOMAIN、CLOUDFLARE_TUNNEL_TOKEN、TRAEFIK_DASHBOARD_HOST
docker compose up -d
```

也可以使用提供的快捷命令：

```sh
make up
make logs
make demo
```

启动演示服务：

```sh
docker compose --profile demo up -d
```

然后访问测试：

```text
https://api.example.com
https://test-api.example.com
```

把 `example.com` 替换成你的真实域名。

## 测试

运行：

```sh
make test
```

测试会检查脚本语法、Compose 配置、Traefik 配置、命名约定和文档链接。

Windows 11 PowerShell 可运行：

```powershell
.\scripts\test.ps1
```

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

测试服务使用 `test-` 主机名前缀：

```yaml
- traefik.http.routers.test-app.rule=Host(`test-app.example.com`)
```

## 添加 localhost 服务

对于直接运行在宿主机上的服务，编辑 `traefik/dynamic/localhost-services.yml`。

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

Traefik 会监听这个目录，并自动重载 file provider 路由。

## 运维注意事项

- 不要为这套服务开放路由器端口。
- 保持 `cloudflared` 和 Traefik 在同一个 Docker 网络中，这样 tunnel 才能访问 `http://traefik:80`。
- 不建议多台设备独立接管同一个 `*.example.com`；多设备部署建议使用单入口反代，或为每台设备分配不重叠的一级子域名。
- 使用 `traefik.example.com` 前，先用 Cloudflare Access 保护 Traefik dashboard。
- 如果部署在 Linux 上，`host.docker.internal` 由 `docker-compose.yml` 中的 `extra_hosts: host-gateway` 提供。
- 如果某个主机名应该是私有的，请在 Cloudflare Access 中强制登录；labels 和 file-provider 配置只负责创建路由。
