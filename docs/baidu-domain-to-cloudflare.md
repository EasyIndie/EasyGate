# 百度云注册域名迁移到 Cloudflare

## 迁移含义

这里的“迁移到 Cloudflare”指的是把域名的权威 DNS 从百度云切换到 Cloudflare，也就是 Cloudflare Full DNS setup。

这不等于把域名注册商从百度云转移到 Cloudflare。域名仍然可以继续在百度云续费和管理实名信息，但 DNS 解析记录改到 Cloudflare 管理。

## 迁移前准备

1. 在百度云导出现有 DNS 解析记录。
2. 记录所有正在使用的记录类型：
   - `A`
   - `AAAA`
   - `CNAME`
   - `MX`
   - `TXT`
   - `SRV`
   - `CAA`
   - 子域名相关记录
3. 特别确认邮件相关记录：
   - `MX`
   - SPF 对应的 `TXT`
   - DKIM 对应的 `TXT`
   - DMARC 对应的 `TXT`
4. 迁移前把重要记录的 TTL 调低，例如 300 秒，等待旧 TTL 过期后再切换。

## Cloudflare 侧操作

1. 登录 Cloudflare。
2. 添加站点，输入根域名，例如：

   ```text
   example.com
   ```

3. 选择 Free 计划。
4. Cloudflare 会扫描现有 DNS 记录。
5. 仔细核对扫描结果，补齐没有自动识别的记录。
6. 确认 Cloudflare 分配的两个 nameserver，格式通常类似：

   ```text
   name1.ns.cloudflare.com
   name2.ns.cloudflare.com
   ```

7. 暂时不要删除百度云上的 DNS 记录，等切换稳定后再清理。

## 百度云侧操作

1. 登录百度智能云控制台。
2. 进入域名服务或域名管理。
3. 找到目标域名。
4. 进入 DNS 服务器或“修改 DNS”页面。
5. 选择使用自定义 DNS 服务器。
6. 填入 Cloudflare 分配的两个 nameserver。
7. 保存修改。

百度云官方文档说明，如果不希望使用百度智能云的域名服务器解析域名，可以通过“修改 DNS”功能修改成自定义 DNS 服务器。

## 等待生效

nameserver 变更需要等待全球 DNS 传播。通常可能从几分钟到 24 小时不等。

可以用以下方式检查：

```sh
dig NS example.com
dig +trace example.com
```

当查询结果显示 Cloudflare 分配的 nameserver 后，说明权威 DNS 已经切到 Cloudflare。

也可以回到 Cloudflare 控制台点击检查 nameserver。

## 是否删除百度云解析记录

切换到 Cloudflare nameserver 后，百度云上的原 DNS 解析记录通常不会再作为权威解析生效。此时真正对外生效的是 Cloudflare DNS 中的记录。

但不建议立刻删除百度云上的原解析记录。推荐做法：

1. 切换 nameserver 后，先保留百度云原解析记录。
2. 在 Cloudflare 中确认所有记录都已完整迁移。
3. 验证网站、API、邮件、证书和 EasyGate 服务都正常。
4. 稳定运行一段时间后，再清理百度云上的旧解析记录。

保留原记录的好处是方便回滚：如果切换后发现邮件、业务域名或某些子域名异常，可以把 nameserver 改回百度云，并快速恢复到原解析状态。

如果确认以后不会回滚，也可以删除百度云上的旧解析记录，减少误操作和维护成本。删除前务必确认 Cloudflare DNS 已经包含所有必要记录，尤其是 `MX`、SPF、DKIM、DMARC 等邮件相关记录。

## 切换后配置 EasyGate

1. 在 Cloudflare 确认 Universal SSL 已开启。
2. 创建 Cloudflare Tunnel。
3. 添加 public hostname：

   ```text
   *.example.com -> http://traefik:80
   ```

4. 按 `docs/create-cloudflare-tunnel.md` 创建 tunnel，并配置通配入口：

   ```text
   *.example.com -> http://traefik:80
   ```

5. 在 `.env` 中填入：

   ```text
   BASE_DOMAIN=example.com
   TRAEFIK_DASHBOARD_HOST=traefik.example.com
   ```

## 验证清单

- `dig NS example.com` 返回 Cloudflare nameserver。
- Cloudflare Overview 页面显示站点已激活。
- Cloudflare DNS 中保留了所有必要记录。
- 邮件收发正常，尤其是 `MX`、SPF、DKIM、DMARC。
- `https://api.example.com` 可以访问。
- `https://test-api.example.com` 可以访问测试服务。
- 家庭路由器没有开放 80/443 入站端口。

## 回滚方式

如果切换后出现严重问题，可以回到百度云域名管理，把 DNS 服务器改回百度云原来的 nameserver。

回滚前提是你保留了百度云上的原解析记录，且知道原 nameserver。正式稳定前不要立刻删除百度云 DNS 记录。
