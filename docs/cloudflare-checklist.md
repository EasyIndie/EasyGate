# Cloudflare 配置清单

## DNS 和 TLS

- 使用 Cloudflare Free，并采用 Full DNS setup。
- 将域名的权威 nameserver 切换到 Cloudflare。
- 保持 Universal SSL 开启。
- 只使用一级子域名：

  ```text
  service.example.com
  test-service.example.com
  ```

- 在免费计划下不要使用 `test.service.example.com`，除非你额外购买或配置自定义证书覆盖。

## Tunnel

- 使用 `cloudflared` CLI 创建 tunnel。
- 详细步骤见 `docs/create-cloudflare-tunnel.md`。
- 推荐只配置一个通配入口：

  ```text
  *.example.com -> http://traefik:80
  ```

- 已有的具体 DNS 记录会优先于通配记录。`*.example.com` 只会接管没有单独配置的子域名。
- 如果某个域名不需要进入 EasyGate，请在 Cloudflare DNS 中为它保留或创建具体记录。
- 不要开放路由器的 80 或 443 入站端口。

## 冒烟测试

执行 `docker compose up -d` 后：

```sh
curl -I https://api.example.com
curl -I https://test-api.example.com
```

预期结果：

- 公开生产服务返回业务响应。
- 测试服务返回对应测试服务响应。
- 路由器入站端口保持关闭。

## 限制说明

请求数、Tunnel 数量、上传大小和大流量场景限制见 `docs/cloudflare-free-limits.md`。

## nginx 共存

如果部署设备上已有 nginx，端口共存和接入方式见 `docs/nginx-compatibility.md`。

## 百度云域名迁移

如果域名注册在百度云，切换到 Cloudflare Full DNS setup 的步骤见 `docs/baidu-domain-to-cloudflare.md`。
