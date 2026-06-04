# 验收

EasyGate 验收分两类：

- 本机验收：只验证 Traefik 路由和 Docker 自动发现，不需要真实域名或 Cloudflare Tunnel。
- 公网 HTTPS 验收：验证 Cloudflare DNS、HTTPS、Tunnel、Traefik 和 demo 服务完整链路。

## 静态检查

```sh
make test
```

Windows PowerShell：

```powershell
.\scripts\test.ps1
```

测试会检查关键文件、脚本语法、Compose 配置、YAML、文档链接和跨平台入口。

## 本机路由验收

推荐直接运行：

```sh
make local-acceptance
```

Windows PowerShell：

```powershell
.\scripts\local-acceptance.ps1
```

脚本会在没有 `.env` 时从 `.env.example` 生成一个本机验收配置。它只启动 Traefik 和 demo 服务，不启动 `cloudflared`，也不需要 tunnel 凭据。

手动运行：

```sh
make local-up
```

等价命令：

```sh
docker compose -f docker-compose.local.yml --env-file .env --profile demo up -d
```

验证生产 demo：

```sh
curl -H "Host: api.example.com" http://127.0.0.1:18080
```

验证测试 demo：

```sh
curl -H "Host: test-api.example.com" http://127.0.0.1:18080
```

预期响应包含：

```text
Hostname:
IP:
RemoteAddr:
```

验证未配置域名返回 404：

```sh
curl -I -H "Host: missing.example.com" http://127.0.0.1:18080
```

清理本机验收栈：

```sh
make local-down
```

## 公网 HTTPS 验收

完成部署后启动 demo：

```sh
make demo
```

访问：

```text
https://api.example.com
https://test-api.example.com
```

或用 curl：

```sh
curl -I https://api.example.com
curl https://api.example.com
curl -I https://test-api.example.com
curl https://test-api.example.com
```

预期：

- HTTP 状态为 200。
- 响应体包含 `Hostname:`。
- 响应头里能看到 `server: cloudflare`。

如果本地 curl 出现 DNS 或 TLS 异常，先用公共 DNS 检查解析：

```sh
dig @1.1.1.1 example.com NS +short
dig @1.1.1.1 api.example.com A +short
dig @8.8.8.8 api.example.com A +short
```

域名刚迁到 Cloudflare 时，本机、运营商或代理 DNS 可能还有缓存。可以换浏览器无痕窗口、换网络，或临时指定 Cloudflare IP 验证：

```sh
curl --resolve api.example.com:443:<CLOUDFLARE_IP> https://api.example.com
```

把 `<CLOUDFLARE_IP>` 换成公共 DNS 实际返回的 Cloudflare IP。

## 公网验收后清理 demo

只移除 demo，保留 `traefik` 和 `cloudflared`：

```sh
docker compose --profile demo stop demo-api demo-test-api
docker compose --profile demo rm -f demo-api demo-test-api
```

清理后，如果没有其他服务接管这些域名，本地路由会返回 404。

## CI 行为

GitHub Actions 会在 Ubuntu、macOS、Windows 上运行检查。

- Ubuntu 强制执行完整容器级本机验收。
- macOS 和 Windows 会运行同一入口脚本；如果托管环境没有可用 Docker daemon，会明确跳过运行时验收。
