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

`make test`（`scripts/test.sh` / `scripts/test.ps1`）执行 40+ 项断言：

- 所有关键文件存在（`.sh` 和 `.ps1` 双版本）
- 无旧项目名残留
- Bash 脚本语法（`bash -n`）+ PowerShell 语法（`PSParser.Tokenize`）
- ShellCheck（可选，非阻断）
- `.env.example` 默认值（BASE_DOMAIN、TRAEFIK_HTTP_PORT、TRAEFIK_DASHBOARD_HOST）
- Traefik 网络命名一致性（`easygate-proxy`）
- Cloudflared 版本固定检查：`deploy.ps1`、`easygate.ps1`、`docker-compose.yml` 均使用 `cloudflared:2025.2.1`（非 `:latest`）
- install.sh 自包含检查：不得 source `lib.sh` 或使用 `BASH_SOURCE`（`curl | bash` 安全）
- 安全加固检查：`deploy.sh` 和 `deploy.ps1` 生成的 Compose 配置含 `read_only:` 和 `cap_drop:`
- Cleanup-Compose 回归检查：`easygate.ps1` 的 cleanup 函数不含 `--profile`（防止只停 demo）
- 原生模式入口（`--local-only`、`traefik_v`、互斥检查）
- GitHub Actions 配置（Node 24 opt-in、SHA256SUMS）
- 文档链接有效性
- YAML 语法 + Docker Compose 配置可渲染

## 行为测试

`make behavior-test`（`scripts/behavior-test.sh` / `scripts/behavior-test.ps1`）使用 mock 二进制（docker、cloudflared、traefik）隔离真实环境，**不需要**真实 Cloudflare 账号或 Tunnel。

### Bash 测试（13 个用例）

| 测试 | 验证内容 |
|------|----------|
| 部署复用凭据 | 第二次部署不重复创建 Tunnel，生成正确配置 |
| `--skip-route` | 跳过 DNS 路由但其他流程正常 |
| `--demo` | demo 服务正常启动 |
| 清理保留配置 | 默认 cleanup 不删配置和凭据 |
| 清理 purge | `--purge` + 确认 `yes` 后删除运行时目录 |
| 清理命令检查 | compose down 不含 `--profile`（回归检测） |
| 原生部署 | file provider 配置 + 进程启动 |
| 模式互斥 | Compose 模式阻止原生部署，反之亦然 |
| 独立 CLI | CLI 不依赖源码仓库 |
| install.sh 安装 | CLI 安装到正确路径，PATH 行格式有效 |
| **install.sh 管道模式** | 模拟 `curl \| bash` stdin 安装，无 `BASH_SOURCE`/`lib.sh` 依赖 |
| **输入校验** | `validate_port/domain/tunnel_name` 的 20+ 边界值测试 |
| **uninstall** | 删除 CLI 二进制 + 清理 shell 配置 + 保留非 EasyGate 内容 |

### PowerShell 测试（8 个用例）

覆盖部署、原生部署、清理、模式互斥、安装验证等核心路径。独立 CLI 测试在 Windows PS7 上暂跳过（已知 `$args` 兼容性问题）。

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

| 平台 | Shell | 严格 | 超时 | 失败上传日志 |
|------|-------|------|------|-------------|
| ubuntu-latest | Bash | ✅ | 15 min | ✅ |
| macos-latest | Bash | ❌ | 15 min | ✅ |
| windows-latest | PowerShell | ❌ | 15 min | — |

`git tag v*` 触发 Release 工作流：
- 打包 CLI + 安装脚本
- 计算并嵌入 CLI SHA256 校验和到 `dist/install.sh`
- 生成 SHA256SUMS + cosign keyless 签名
- 生成 SPDX SBOM
