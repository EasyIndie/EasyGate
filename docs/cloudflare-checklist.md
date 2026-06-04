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

- 在 Cloudflare Zero Trust 中创建一个 remotely managed tunnel。
- 使用 `.env` 中的 token 安装并运行 tunnel。
- 添加这个 public hostname：

  ```text
  *.example.com -> http://traefik:80
  ```

- 不要开放路由器的 80 或 443 入站端口。

## Access 策略

暴露私有主机名前，先创建 Access applications。

推荐策略：

```text
test-*.example.com     需要登录
traefik.example.com    需要登录
grafana.example.com    需要登录
admin.example.com      需要登录
```

如果 `blog.example.com` 这类生产服务本来就是面向公网的，可以不加 Access。

## 冒烟测试

执行 `docker compose up -d` 后：

```sh
curl -I https://api.example.com
curl -I https://test-api.example.com
```

预期结果：

- 公开生产服务返回业务响应。
- 测试或私有服务跳转到 Cloudflare Access 登录，或要求登录后访问。
- 路由器入站端口保持关闭。

## 限制说明

请求数、Tunnel 数量、上传大小和大流量场景限制见 `docs/cloudflare-free-limits.md`。

## nginx 共存

如果部署设备上已有 nginx，端口共存和接入方式见 `docs/nginx-compatibility.md`。

## 百度云域名迁移

如果域名注册在百度云，切换到 Cloudflare Full DNS setup 的步骤见 `docs/baidu-domain-to-cloudflare.md`。
