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

安装后 CLI 自动加入 PATH（写入 `~/.zshrc` / `~/.bashrc`），立即生效。

## 日常命令

```sh
easygate ps           # 查看状态
easygate logs         # 查看日志
easygate demo         # 启动 demo 服务
easygate cleanup      # 停止服务，保留配置
easygate uninstall    # 卸载 CLI + 清理 PATH 配置
```

## 部署模式

| 模式 | 命令 | 适用场景 | 重启恢复 |
|------|------|----------|----------|
| Docker Compose | `easygate deploy` | Traefik 自动发现容器服务 | ✅ 含 `restart: unless-stopped` |
| 原生（无 Docker） | `easygate native deploy` | 纯静态文件配置 | ✅ 自动注册系统服务 |

原生模式下，部署时会自动注册 systemd（Linux）或 launchd（macOS）用户服务，设备重启后进程自动恢复。

## 平台支持

| 平台 | 推荐 CLI |
|------|----------|
| macOS / Linux | `easygate`（Bash） |
| Windows | `easygate.ps1`（PowerShell） |

## 更多文档

- [部署指南](docs/deployment.md) — 部署、管理、清理、卸载、平台兼容性
- [测试指南](docs/testing.md) — 静态检查、行为测试、路由验收
- [Cloudflare 参考](docs/cloudflare.md) — 免费套餐限制、Tunnel 创建、域名迁移
- [与 nginx 共存](docs/nginx-compatibility.md)

## License

MIT
