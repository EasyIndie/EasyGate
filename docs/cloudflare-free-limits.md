# Cloudflare Free 限制说明

## 请求数

对于本项目的默认路径：

```text
浏览器 -> Cloudflare -> Cloudflare Tunnel -> Traefik -> 服务
```

Cloudflare Free 没有公开写明一个固定的“每天 HTTP 请求数上限”。这和 Workers Free 的 `100,000 requests/day` 不同：Workers 的限制只在你使用 Workers、Pages Functions 等计算产品时适用。

本项目默认不使用 Workers 或 Pages Functions，因此不会触发 Workers Free 的每日请求数限制。

## Tunnel 数量限制

Cloudflare One 文档中列出的默认限制：

- 每个账号最多 1000 个 `cloudflared` tunnels。
- Tunnel hostname routes 和 CIDR routes 合计最多 1000 条。
- 单个 tunnel 最多 25 个活跃 `cloudflared` 副本。

对于一人公司、几台家庭设备、几十到上百个服务，这些额度通常足够。

## 需要注意的实际限制

- Free 计划的最大请求体大小为 100 MB。
- Free/Pro/Business 的 CDN 可缓存单文件大小限制为 512 MB。
- 不建议把 Cloudflare Free 当作大文件分发、公开网盘、影视流媒体或持续高带宽出口。
- 如果服务需要大量上传、长时间下载、视频流或高并发公开访问，应单独评估 Cloudflare 政策、带宽行为和升级成本。

## 适用性判断

适合：

- 个人/小团队后台。
- API、Web 管理面板、Webhook。
- 低到中等流量的网站。
- 测试服务和内部工具。

不适合：

- 大流量公开下载站。
- 公开视频/影视串流。
- 主要靠 Cloudflare 免费代理承载的大带宽业务。
- 依赖 Workers Free 处理大量动态请求的架构。
