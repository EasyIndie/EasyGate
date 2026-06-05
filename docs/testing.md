# 测试指南

项目有三层测试体系：静态检查 → 行为测试（mock）→ 本地路由验收。

```sh
make test               # 静态检查 + 行为测试 + YAML 验证
make behavior-test      # 仅行为测试（mock，无需真实 Cloudflare 账号）
make local-acceptance   # 本地 Docker 路由验证
make local-acceptance-native  # 本地原生路由验证
make lint               # 仅 ShellCheck（需安装 shellcheck）
```

## 静态检查

`make test`（`scripts/test.sh` / `scripts/test.ps1`）执行：

- 关键文件存在（`.sh` 和 `.ps1` 双版本）
- 无旧项目名残留
- Bash 脚本语法（`bash -n`）
- ShellCheck（可选，非阻断）
- `.env.example` 默认值
- Traefik 网络命名一致性
- cloudflared 和原生模式入口
- 文档链接有效性
- Docker Compose 配置可渲染

## 行为测试

`make behavior-test` 使用 mock 二进制（docker、cloudflared、traefik）隔离真实环境，**不需要**真实 Cloudflare 账号或 Tunnel。

覆盖场景：

| 测试 | 验证内容 |
|------|----------|
| 部署复用凭据 | 第二次部署不重复创建 Tunnel |
| `--skip-route` | 跳过 DNS 路由但其他流程正常 |
| `--demo` | demo 服务正常启动 |
| 清理保留配置 | 默认 cleanup 不删配置和凭据 |
| 清理 purge | `--purge` + 确认 `yes` 后删除数据 |
| 原生部署 | file provider 配置 + 进程启动 |
| 模式互斥 | Compose 模式阻止原生部署，反之亦然 |
| 独立 CLI | CLI 不依赖源码仓库（仅 Bash） |

## 本地路由验收

绕开 Cloudflare Tunnel，直接验证 Traefik 本地路由。

### Docker 模式

```sh
make local-acceptance
```

流程：启动 Traefik + demo → 验证 `api.example.com` 返回 `Hostname:` → 验证 `test-api.example.com` 返回 `Hostname:` → 验证未配置域名返回 `404` → 清理。

### 原生模式

```sh
make local-acceptance-native
```

用 `easygate native deploy --domain example.com --demo --local-only` 启动原生 Traefik + Python demo 服务器，执行相同路由验证。

用 `EASYGATE_ACCEPTANCE_STRICT=true` 控制严格模式：失败时退出而非跳过。

## CI

GitHub Actions 在 `push`、`pull_request` 和每周 cron 时运行，矩阵覆盖三平台：

| 平台 | Shell | 严格 | 备注 |
|------|-------|------|------|
| ubuntu-latest | Bash | ✅ | — |
| macos-latest | Bash | ❌ | Docker 可能不可用 |
| windows-latest | PowerShell | ❌ | PS7 独立 CLI 子命令已知问题 |

`git tag v*` 触发 Release 工作流，生成 SHA256SUMS（cosign 签名）和 SPDX SBOM。
