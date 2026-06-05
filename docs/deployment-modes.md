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

## 部署模式速查

在选择部署方案前，先确认你的设备组合和目标。下面用一张表说明常见模式是否可行：

| 部署场景 | 是否可行 | 说明 |
|---------|---------|------|
| 单台设备，Docker 入口 | ✅ | 默认推荐模式。一台设备跑 Traefik + cloudflared，**同时**代理 Docker 容器和局域网服务（模式一） |
| 单台设备，无 Docker，原生安装 | ✅ | cloudflared + Traefik 二进制直接运行，纯 file provider 管理服务（模式二） |
| 多台不同设备，各自独立部署，**同一个域名** | ❌ | Cloudflare 路由冲突，请求随机分发到错误设备 |
| 多台不同设备，各自独立部署，**不同子域名** | ✅ | 每台设备用互不重叠的子域名，如 `nas-api.y.com`、`win-api.y.com` |
| 多台设备，运行相同服务，高可用副本 | ✅ | 共用同一 tunnel 和 hostname，Cloudflare 做负载均衡 |

### 为什么不能多设备共用同一个域名？

部署 EasyGate 时，脚本会创建一条通配 DNS 路由：

```text
*.example.com → <tunnel-id>.cfargotunnel.com
```

这是 Cloudflare 侧的**全局入口配置**。如果多台设备各自独立部署，每台都会尝试声明同一条路由，导致：

1. **路由覆盖**：后面部署的会覆盖前面部署的 DNS 路由，甚至可能出现你改 DNS 我改 DNS 的竞态覆盖。
2. **请求随机分发**：如果多台设备复用了同一组 tunnel 凭据，Cloudflare 会将其视为同一个 tunnel 的多个 connector，请求被负载均衡到任意一台。用户无法控制访问到哪台设备。
3. **排查困难**：出问题时无法判断请求最终落到哪台设备，日志分散在多个机器上。
4. **服务不一致**：每台设备运行的服务不同，A 设备有 `api.y.com` 对应的服务但 B 设备没有，请求落到 B 就会 404。

Docker 网络名和容器名只在单台设备内生效，不会跨设备冲突。**真正需要避免的是 Cloudflare hostname 和 tunnel 路由冲突。**

### 正确做法

- **想要统一入口**：参考模式一，用一台设备作为网关，反代局域网内其他设备。
- **想要多台设备各自对外**：为每台设备分配互不重叠的子域名，例如：

  ```text
  nas-api.example.com       → 设备 A（NAS）
  mini-api.example.com      → 设备 B（小主机）
  win-api.example.com       → 设备 C（Windows）
  test-nas-api.example.com  → 设备 A 上的测试服务
  ```

  在 Cloudflare Free 下，**必须**使用一级子域名（`api.example.com`），不能使用 `api.nas.example.com` 这类更深层级域名——Free 的 Universal SSL 通配证书只覆盖根域名和一级子域名，更深层级的域名会因证书不匹配导致 TLS 连接失败。详见 [cloudflare-free-limits.md](cloudflare-free-limits.md)。
- **只有多台设备部署完全相同的服务且作为高可用副本时**，才适合共用同一个 tunnel 和同一组 hostname，此时 Cloudflare 的负载均衡行为反而是你需要的。


## 模式一：Docker 入口设备

适合有一台稳定设备能跑 Docker 的场景：NAS、Linux 小主机、开发机。

使用本项目的 `docker-compose.yml` 启动 Traefik + cloudflared。Traefik 同时启用两个 provider，**可以混合接入 Docker 容器和局域网服务**：

```yaml
# traefik/traefik.yml
providers:
  docker:    # 自动发现带 labels 的 Docker 容器
    ...
  file:      # 手动配置宿主机端口或局域网 IP 服务
    ...
```

### 接入 Docker 容器服务

容器加入 `easygate-proxy` 网络并添加 labels，Traefik 自动发现：

```yaml
services:
  app:
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

### 接入宿主机或局域网服务

编辑 `traefik/dynamic/localhost-services.yml`，手动声明非 Docker 服务：

```yaml
# 宿主机端口
http:
  routers:
    local-api:
      rule: Host(`local-api.example.com`)
      entryPoints: [web]
      service: local-api
  services:
    local-api:
      loadBalancer:
        servers:
          - url: http://host.docker.internal:8080

# 局域网其他设备
    printer-admin:
      loadBalancer:
        servers:
          - url: http://192.168.1.50:8080
```

局域网设备不需要安装 Docker、cloudflared 或 Traefik，只要入口设备能访问它们的 IP 和端口即可。

特点：

- Docker 服务通过 labels 自动发现，零配置接入。
- 非 Docker 服务编辑 YAML 后，Traefik 自动热加载。
- 维护成本和配置复杂度最低，是推荐默认模式。

## 模式二：非 Docker 设备原生安装

适合不方便安装 Docker，但可以安装系统服务的设备。

做法：

- 使用 `easygate native deploy` 或 `easygate.ps1 native deploy` 准备 `cloudflared` 和 Traefik 二进制。
- 通过项目托管进程运行原生 Traefik 和 `cloudflared`。
- 使用 Traefik file provider 管理本机服务。
- 不启用 Docker provider。

这种模式也能实现 HTTPS 入口和 localhost 服务转发，但不会有 Docker labels 自动发现能力。

当前项目已经提供原生模式的部署、清理、本机验收和 CI 覆盖。长期自启可以在验收通过后自行接入 `systemd`、launchd、Windows Task Scheduler 或 Windows Service。具体命令见 [native-deployment.md](native-deployment.md)。

## 模式间切换与互斥

模式一和模式二在同一台设备上切换部署时，**需要先清理旧模式再部署新模式**。两者不能同时运行。

| 切换方向 | 需要清理的内容 |
|---------|--------------|
| 模式一 → 模式二 | `easygate cleanup` 停止容器，释放端口；后续原生 Traefik 需使用不同端口或先确认 80/18080 已空闲 |
| 模式二 → 模式一 | `easygate native cleanup` 停止原生进程，释放端口后再 `easygate deploy --domain example.com` |

两套模式可以共用同一组 cloudflared tunnel 凭据文件（`cloudflared/*.json`），但**不能同时运行**——同时运行会被 Cloudflare 视为同一个 tunnel 的多个 connector，形成非预期的负载均衡。

脚本层面已经做了互斥保护：

- Docker Compose 部署脚本发现原生模式 PID 仍在运行时，会拒绝继续部署。
- 原生部署脚本发现 Compose 模式的 `traefik` 或 `cloudflared` 服务正在运行时，会拒绝继续部署。
- 同一模式重复部署是允许的：Compose 模式会重新渲染运行时配置并启动容器；原生模式会先停止自己管理的旧 PID，再重新启动进程。

核心原则：**一套 tunnel 凭据 + 一台设备 + 一个运行中的 cloudflared 实例**。切换模式时，确保旧的 cloudflared/Traefik 进程已完全停止。

## 推荐选择

- 有一台稳定设备能跑 Docker：使用模式一，可以同时接入 Docker 容器和局域网服务。
- 完全不能使用 Docker：使用模式二，但每个服务都需要手动编辑 YAML 配置。
- 多台设备场景：在能跑 Docker 的设备上部署模式一作为统一入口，反代其他设备。

对一人公司和家庭 NAT 场景，优先推荐模式一。
