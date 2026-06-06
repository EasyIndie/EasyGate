# EasyGate

[![CI](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml/badge.svg)](https://github.com/EasyIndie/EasyGate/actions/workflows/ci.yml)

面向家庭 NAT、家庭实验室和一人公司的轻量入口网关——用 Cloudflare Free + Cloudflare Tunnel 把本地服务暴露到公网，**不需要公网 IP，不需要开放路由器端口**。

## 它能做什么

- 让家里的 Docker 容器、树莓派、NAS 等服务通过 `https://app.example.com` 从公网访问
- Traefik 自动发现带 labels 的 Docker 容器，也支持手动配置的非 Docker 服务
- WebSocket 透明代理（`wss://`），支持实时应用
- 设备重启后自动恢复，无需手动干预

## 支持平台

| 平台 | CLI | Docker Compose | 原生（无 Docker） |
|------|-----|:---:|:---:|
| macOS | Bash | ✅ | ✅ |
| Linux (x86/ARM) | Bash | ✅ | ✅ |
| Windows | PowerShell | ✅ | — |

## 前置条件

使用 EasyGate 前，请确认满足以下条件：

### 必须

- [ ] **自己的域名**，且 DNS 托管在 Cloudflare（权威 nameserver 已切到 Cloudflare）
- [ ] Cloudflare Universal SSL 保持开启（默认是开的）
- [ ] 部署设备能访问互联网（出站到 Cloudflare API 和 Tunnel 网络）

### 部署方式二选一

**Docker Compose 模式（推荐）：**
- [ ] Docker Engine 已安装
- [ ] Docker Compose 插件可用（`docker compose version`）

**原生模式（不需要 Docker）：**
- [ ] 仅需操作系统本身（macOS / Linux）

### 不需要的

- ❌ 公网 IP
- ❌ 路由器端口转发（80/443）
- ❌ 购买 SSL 证书
- ❌ 购买服务器或 VPS
- ❌ 注册 Cloudflare 之外的服务

如果域名刚从其他注册商迁移到 Cloudflare，DNS 传播可能需几分钟到数小时：
```sh
dig @1.1.1.1 example.com NS +short      # 确认 nameserver 已切换
dig @1.1.1.1 api.example.com A +short    # 确认解析生效
```

## 安装部署

一行命令完成安装和部署。根据场景选择模式：

### Docker Compose 模式（推荐）

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash -s -- deploy --domain example.com --demo
```

安装后 CLI 在 `~/.easygate/bin/easygate`，自动写入 PATH，立即生效。部署后访问 `https://api.example.com` 验证 demo 服务。

### 原生模式（无需 Docker）

先安装 CLI：

```sh
curl -fsSL https://raw.githubusercontent.com/EasyIndie/EasyGate/main/scripts/install.sh | bash
```

再部署：

```sh
easygate native deploy --domain example.com --demo
```

原生模式会自动注册系统服务（systemd / launchd），设备重启后进程自动恢复。

**详细说明**：参见 [部署指南](docs/deployment.md) —— 涵盖 Docker / 原生部署、所有选项参数、接入自己的服务、域名约定、清理卸载。

## 日常使用

```sh
easygate start              # 启动服务
easygate stop               # 停止服务（保留配置）
easygate restart            # 重启服务
easygate ps                 # 查看状态
easygate logs               # 查看日志
easygate demo start         # 启动 demo 测试服务
easygate demo stop          # 停止 demo
easygate purge              # 删除全部本地数据
easygate uninstall          # 卸载 CLI
```

## 参考文档

| 文档 | 内容 |
|------|------|
| [部署指南](docs/deployment.md) | 完整部署流程、选项参数、接入服务、安全加固 |
| [测试指南](docs/testing.md) | 测试体系、行为测试、路由验收、CI 配置 |
| [Cloudflare 参考](docs/cloudflare.md) | Free 套餐限制、Tunnel 创建、域名迁移 |
| [与 nginx 共存](docs/nginx-compatibility.md) | 已运行 nginx 的设备如何共存 |

## License

MIT
