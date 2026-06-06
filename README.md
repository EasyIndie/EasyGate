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

CLI 安装到 `~/.easygate/bin/easygate`，自动加入 PATH（写入 `~/.zshrc` / `~/.bashrc`），立即生效。安装后可随时用 `easygate uninstall` 卸载。

## 日常命令

```sh
easygate deploy --domain example.com --demo  # 部署 + 启动 demo
easygate start                                # 启动已停止的服务
easygate stop                                 # 停止服务，保留配置
easygate restart                              # 重启服务
easygate ps                                   # 查看状态
easygate demo start                           # 启动 demo 服务
easygate demo stop                            # 停止 demo 服务
easygate purge                                # 删除全部本地数据（需确认）
easygate uninstall                            # 卸载 CLI
```

## 部署模式

| 模式 | 说明 | 重启恢复 |
|------|------|----------|
| Docker Compose | `easygate deploy`，Traefik 自动发现容器服务 | ✅ `restart: unless-stopped` |
| 原生（无 Docker） | `easygate native deploy`，纯文件配置 | ✅ 自动注册 systemd/launchd 服务 |

Docker 可用时默认走 Compose 模式，也可通过 `easygate native deploy` 强制原生。两种模式互斥。

## 平台支持

| 平台 | 推荐 CLI |
|------|----------|
| macOS / Linux | `easygate`（Bash） |
| Windows | `easygate.ps1`（PowerShell） |

所有命令跨平台一致——`deploy`、`start`、`stop`、`restart`、`demo`、`purge`、`uninstall`。

## 更多文档

- [部署指南](docs/deployment.md) — 详解部署、管理、接入服务、清理、卸载
- [测试指南](docs/testing.md) — 测试体系、行为测试、路由验收
- [Cloudflare 参考](docs/cloudflare.md) — 免费套餐限制、Tunnel 创建、域名迁移
- [与 nginx 共存](docs/nginx-compatibility.md)

## License

MIT
