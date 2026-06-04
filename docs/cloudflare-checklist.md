# Cloudflare 配置清单

## 域名和证书

- 域名使用 Cloudflare Full DNS setup，权威 nameserver 已切到 Cloudflare。
- Cloudflare Overview 显示站点已激活。
- Universal SSL 保持开启。
- 生产和测试服务使用一级子域名：

  ```text
  service.example.com
  test-service.example.com
  ```

- 不依赖 `test.service.example.com` 这类更深层级子域名，除非你已单独配置证书覆盖。

## DNS 记录

推荐让 EasyGate 接管未单独配置的一级子域名：

```text
*.example.com -> Cloudflare Tunnel
```

保留不进入 EasyGate 的具体记录，例如：

```text
www.example.com
mail.example.com
cdn.example.com
```

具体记录优先于通配记录，不会被 `*.example.com` 覆盖。

## Tunnel

推荐使用部署脚本创建或复用 tunnel：

```sh
./scripts/deploy.sh --domain example.com
```

Windows：

```powershell
.\scripts\deploy.ps1 -Domain example.com
```

如果手动配置，Cloudflare Tunnel 的 public hostname / ingress 目标应为：

```text
*.example.com -> http://traefik:80
```

不要配置为 `http://localhost:80`。在 `cloudflared` 容器里，`localhost` 指向容器自己，不是 Traefik。

## DNS 传播检查

域名刚迁到 Cloudflare 时，不同递归 DNS 可能返回不一致结果。用公共 DNS 检查：

```sh
dig @1.1.1.1 example.com NS +short
dig @8.8.8.8 example.com NS +short
dig @223.5.5.5 example.com NS +short

dig @1.1.1.1 api.example.com A +short
dig @8.8.8.8 api.example.com A +short
dig @223.5.5.5 api.example.com A +short
```

预期：

- NS 返回 Cloudflare 分配的两个 nameserver。
- 橙云代理下的子域名返回 Cloudflare IP。

如果公共 DNS 已正确、本机浏览器仍异常，优先清理本机 DNS 缓存或换网络测试。

## HTTPS 验收

启动 demo：

```sh
make demo
```

测试：

```sh
curl -I https://api.example.com
curl https://api.example.com
curl -I https://test-api.example.com
curl https://test-api.example.com
```

预期：

- HTTP 状态为 200。
- 响应头包含 `server: cloudflare`。
- 响应体包含 `Hostname:`。

验收完成后移除 demo：

```sh
docker compose --profile demo stop demo-api demo-test-api
docker compose --profile demo rm -f demo-api demo-test-api
```

## 安全和边界

- 不开放路由器 80/443 入站端口。
- 不提交 `cloudflared/*.json` 凭据文件。
- 不把 Cloudflare Free 当作大文件分发、公开网盘或视频流量出口。
- 请求体大小、Tunnel 数量和流量适用性见 [cloudflare-free-limits.md](cloudflare-free-limits.md)。

## 相关文档

- [创建 Cloudflare Tunnel](create-cloudflare-tunnel.md)
- [百度云域名迁移到 Cloudflare](baidu-domain-to-cloudflare.md)
- [与已有 nginx 共存](nginx-compatibility.md)
