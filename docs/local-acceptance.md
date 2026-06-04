# 本机测试验收

本机验收分两层：

1. 静态检查：不需要 Docker。
2. 本地路由验收：需要 Docker，但不需要真实域名或 Cloudflare Tunnel。

## 1. 静态检查

```sh
make test
```

该命令会检查脚本语法、YAML、文档链接、命名约定等基础质量。

## 2. 准备本地配置

复制 `.env`：

```sh
cp .env.example .env
```

默认 `example.com` 就可以用于本地验收。

## 3. 启动本地验收栈

推荐直接运行自动验收：

```sh
make local-acceptance
```

Windows PowerShell：

```powershell
.\scripts\local-acceptance.ps1
```

下面是手动验收步骤。

本地验收栈只启动 Traefik 和 demo 服务，不启动 cloudflared，因此不需要 tunnel 凭据：

```sh
make local-up
```

等价命令：

```sh
docker compose -f docker-compose.local.yml --env-file .env up -d
```

## 4. 验证 Docker 自动发现

生产 demo：

```sh
curl -H "Host: api.example.com" http://127.0.0.1:18080
```

测试 demo：

```sh
curl -H "Host: test-api.example.com" http://127.0.0.1:18080
```

预期响应中可以看到 whoami 服务信息，例如：

```text
Hostname:
IP:
RemoteAddr:
```

## 5. 验证 Traefik dashboard

```sh
curl -I -H "Host: traefik.example.com" http://127.0.0.1:18080/dashboard/
```

预期返回 HTTP 200 或 相关 dashboard 响应。

## 6. 验证未配置域名不会误路由

```sh
curl -I -H "Host: missing.example.com" http://127.0.0.1:18080
```

预期返回 `404`。

如果你在 `.env` 中修改了 `TRAEFIK_HTTP_PORT`，把上面的 `18080` 替换成实际端口即可。

## 7. 清理本地验收栈

```sh
make local-down
```

## 8. 完整公网验收

完成 Cloudflare Tunnel 配置后，再运行正式栈：

```sh
make up
make demo
```

然后访问：

```text
https://api.example.com
https://test-api.example.com
```

把 `example.com` 替换成你的真实域名。

## CI 中的行为

GitHub Actions 会在 Ubuntu、macOS、Windows 矩阵里运行本机验收脚本。

- Ubuntu runner 强制执行完整容器级路由验收。
- macOS 和 Windows runner 会运行同一入口脚本；如果托管环境没有可用 Docker daemon，会明确跳过运行时验收。

这样可以同时覆盖脚本兼容性和 Linux 上的真实 Docker 路由行为。
