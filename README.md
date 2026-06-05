# EasyGate

[![CI](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml)

面向家庭 NAT、家庭实验室和一人公司的轻量入口网关——用 Cloudflare Free + Tunnel 提供公网 HTTPS 入口，Traefik 在本地分发服务。

```
浏览器 → Cloudflare HTTPS → Cloudflare Tunnel → Traefik → 本地服务
```

**零公网端口**：cloudflared 出站连接 Cloudflare 边缘，设备不需要公网 IP 也不需开放路由器端口。

## 一键部署

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash -s -- deploy --domain example.com
```

部署后访问 `https://api.example.com` 和 `https://test-api.example.com`（需 `--demo`）。

## 日常命令

```sh
easygate ps          # 查看状态
easygate logs        # 查看日志
easygate demo        # 启动 demo 服务
easygate cleanup     # 停止服务，保留配置
```

## 部署模式

| 模式 | 命令 | 适用场景 |
|------|------|----------|
| Docker Compose（默认） | `easygate deploy --domain example.com` | 推荐，Traefik 自动发现容器服务 |
| 原生（无 Docker） | `easygate native deploy --domain example.com` | 不需要 Docker，用文件配置路由 |

## 平台支持

| 平台 | Bash CLI | PowerShell CLI |
|------|----------|----------------|
| macOS | ✅ | ✅ |
| Linux | ✅ | ✅ |
| Windows | — | ✅ |

## 更多文档

- [部署指南](docs/deployment.md) — 部署、管理、清理、平台兼容性
- [测试指南](docs/testing.md) — 静态检查、行为测试、路由验收
- [Cloudflare 参考](docs/cloudflare.md) — 免费套餐限制、Tunnel 创建、域名迁移
- [与 nginx 共存](docs/nginx-compatibility.md)

## License

MIT
