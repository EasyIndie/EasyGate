# 测试指南

三层测试体系：静态检查 → 行为测试（mock）→ 本地路由验收。

```sh
make test               # 全部：静态 + 行为 + YAML 验证
make behavior-test      # 仅行为测试（无需 Cloudflare 账号）
make local-acceptance   # 本地 Docker 路由验证
make local-acceptance-native  # 本地原生路由验证
make lint               # ShellCheck（需安装 shellcheck）
```

## 静态检查

40+ 项断言覆盖：

- 关键文件存在（`.sh` 和 `.ps1` 双版本）
- 无旧项目名残留
- Bash 语法（`bash -n`）+ PowerShell 语法（`PSParser.Tokenize`）
- `.env.example` 默认值
- Traefik 网络命名（`easygate-proxy`）
- **cloudflared 版本固定**：三个文件中均为 `2025.2.1`
- **install.sh 自包含**：禁止 `source lib.sh` 或 `BASH_SOURCE`
- **安全加固**：`deploy.sh`/`deploy.ps1` 生成模板含 `read_only` + `cap_drop`
- **Demo 专用 compose 命令不含 `--profile`**
- 原生模式入口、CI 配置、文档链接有效性
- YAML 语法 + Docker Compose 配置可渲染

## 行为测试

Mock 二进制（docker、cloudflared、traefik）隔离真实环境，不需要 Cloudflare 账号。

### Bash 测试（13 个用例）

| 测试 | 验证内容 |
|------|----------|
| 部署复用凭据 | 两次部署只创建一次 Tunnel |
| `--skip-route` | 跳过 DNS 路由 |
| `--demo` | demo 正常启动 |
| 清理保留配置 | stop 不删配置和凭据 |
| 清理 uninstall | uninstall 删除全部数据 + 清理 PATH |
| 清理命令检查 | compose 命令不含 `--profile` |
| 原生部署 | file provider 配置 + 进程启动 |
| 模式互斥 | compose 和 native 双向阻止 |
| 独立 CLI | CLI 不依赖源码仓库 |
| install.sh 安装 | CLI 安装路径正确，PATH 格式合法 |
| **管道模式安装** | `curl \| bash` 模拟，无 BASH_SOURCE 依赖 |
| **输入校验** | validate_port/domain/tunnel_name 20+ 边界值 |
| **uninstall** | 删除 CLI + 清理 PATH + 保留非 EasyGate 内容 |

### PowerShell 测试（8 个用例）

覆盖部署、原生部署、清理、模式互斥、安装验证等核心路径。独立 CLI 测试在 Windows PS7 上暂跳过（已知 `$args` 兼容问题）。

## 本地路由验收

```sh
make local-acceptance           # Docker 模式
make local-acceptance-native    # 原生模式
```

验证 `api.example.com` 返回 `Hostname:` → `test-api.example.com` → 未配置域名 404。

`EASYGATE_ACCEPTANCE_STRICT=true` 控制严格模式（失败即退出）。

## CI

GitHub Actions 在 push、PR 和每周 cron 运行，三平台矩阵：

| 平台 | Shell | 严格 | 超时 | 失败上传日志 |
|------|-------|------|------|-------------|
| ubuntu-latest | Bash | ✅ | 15 min | ✅ |
| macos-latest | Bash | ❌ | 15 min | ✅ |
| windows-latest | PowerShell | ❌ | 15 min | — |

Release 工作流：`git tag v*` → 打包 CLI + 校验和嵌入 + cosign 签名 + SPDX SBOM。
