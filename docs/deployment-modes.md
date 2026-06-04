# 部署模式

## 结论

这套方案不只能在支持 Docker 的设备上使用，但当前项目模板默认使用 Docker Compose 来降低部署复杂度。

默认模板需要：

- Docker
- Docker Compose

方案本身由两个核心组件组成：

- `cloudflared`：连接 Cloudflare Tunnel。
- Traefik：做本地反向代理和服务发现。

这两个组件都可以不通过 Docker 运行。

## 模式一：Docker 设备运行完整栈

适合主要入口设备、NAS、Linux 小主机、开发机。

特点：

- 使用本项目的 `docker-compose.yml`。
- Docker 服务通过 labels 自动发现。
- 非 Docker 服务通过 Traefik file provider 接入。
- 维护成本最低，是推荐默认模式。

## 模式二：一台 Docker 入口设备代理多台非 Docker 设备

适合家里有多台设备，但只有一台适合长期运行 Docker。

流量路径：

```text
Cloudflare Tunnel -> 入口设备 Traefik -> 局域网其他设备服务
```

示例：

```yaml
http:
  routers:
    printer-admin:
      rule: Host(`printer.example.com`)
      entryPoints:
        - web
      service: printer-admin

  services:
    printer-admin:
      loadBalancer:
        servers:
          - url: http://192.168.1.50:8080
```

这种模式下，其他设备不需要安装 Docker，也不需要安装 cloudflared 或 Traefik，只要入口设备能访问它们的局域网地址即可。

## 多台设备使用同一个域名

不建议多台设备各自独立部署 EasyGate，并同时在 Cloudflare 中绑定同一个通配入口：

```text
*.example.com -> http://traefik:80
```

原因是 Cloudflare 侧的 hostname 路由属于全局入口，同一个 hostname 或通配 hostname 不应该被多套互相独立的 EasyGate 同时接管。否则容易出现：

- 路由冲突或配置覆盖。
- 请求被分发到没有对应服务的设备。
- 多台设备使用同一个 tunnel token 时，Cloudflare 可能把它们当作同一个 tunnel 的多个 connector，从而形成负载均衡效果；这只适合同构副本，不适合每台设备承载不同服务。
- 排查故障时很难判断请求最终落到了哪台设备。

Docker 网络名和容器名只在单台设备内生效，所以它们本身不会跨设备冲突。真正需要避免的是 Cloudflare hostname 和 tunnel 路由冲突。

推荐两种安全做法：

1. 单入口模式：只在一台稳定设备上部署 EasyGate，并让它反代局域网内其他设备的服务。
2. 多入口模式：每台设备使用互不重叠的主机名，例如：

   ```text
   nas-api.example.com
   mini-api.example.com
   win-api.example.com
   test-nas-api.example.com
   test-mini-api.example.com
   ```

在 Cloudflare Free 下，建议继续使用一级子域名，不使用 `api.nas.example.com` 这类更深层级域名。

只有当多台设备部署的是完全相同的一组服务，并且你明确希望它们作为高可用副本时，才适合让它们共用同一个 tunnel 和同一组 hostname。

## 模式三：非 Docker 设备原生安装

适合不方便安装 Docker，但可以安装系统服务的设备。

做法：

- 安装 `cloudflared` 二进制，并注册为系统服务。
- 安装 Traefik 二进制，并注册为系统服务。
- 使用 Traefik file provider 管理本机服务。
- 不启用 Docker provider。

这种模式也能实现 HTTPS 入口和 localhost 服务转发，但不会有 Docker labels 自动发现能力。

## 推荐选择

- 有一台稳定设备能跑 Docker：使用模式一。
- 只有部分设备能跑 Docker：使用模式二，把能跑 Docker 的设备作为统一入口。
- 完全不能使用 Docker：使用模式三，但配置和运维会稍微多一些。

对一人公司和家庭 NAT 场景，优先推荐模式一或模式二。
