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

- 关键文件存在
- 无旧项目名残留
- Bash 语法（`bash -n`）
- `.env.example` 默认值
- Traefik 网络命名（`easygate-proxy`）
- **cloudflared 版本固定**：docker-compose.yml 与 CLI 模板中均为 `2026.5.2`
- **install.sh 自包含**：禁止 `source lib.sh` 或 `BASH_SOURCE`
- **安全加固**：CLI 生成的 compose 模板含 `read_only` + `cap_drop`，且 `Cleanup-Compose` 不含 `--profile`
- **compose down 含 `--profile demo`**（确保 demo 容器也清理）
- 原生模式入口、CI 配置、文档链接有效性
- YAML 语法 + Docker Compose 配置可渲染

## 行为测试

Mock 二进制（docker、cloudflared、traefik）隔离真实环境，不需要 Cloudflare 账号。

### Bash 测试（17 个用例）

| 测试 | 验证内容 |
|------|----------|
| 部署复用凭据 | 两次部署只创建一次 Tunnel，--skip-route 跳过 DNS 路由，--demo 正常启动 |
| 模式互斥 (compose→native) | compose 运行时原生部署被阻止 |
| 原生部署 | file provider 配置 + 进程启动 |
| 模式互斥 (native→compose) | 原生运行时 compose 部署被阻止 |
| 清理保留配置 | stop 不删配置和凭据；purge 确认后删除 |
| 清理命令检查 | compose down 含 `--profile demo` 清理 demo 容器 |
| 独立 CLI | CLI 不依赖源码仓库 |
| install.sh 安装 | CLI 安装路径正确，PATH 格式合法 |
| 管道模式安装 | `curl \| bash` 模拟，无 BASH_SOURCE 依赖 |
| 输入校验 | validate_port/domain/tunnel_name 20+ 边界值 |
| uninstall | 删除 CLI + 清理 PATH + 保留非 EasyGate 内容 |
| stop 停止进程 | stop_pid_file 含 SIGKILL 兜底能终止顽固进程 |
| .mode 文件 | 部署时写入 .mode 供 detect_mode 读取 |
| cloudflared 配置 | ha-connections + loglevel 写入 compose 模式配置 |
| cloudflared 配置(原生) | ha-connections + loglevel 写入原生模式配置 |
| uninstall 清理 | 删除 PID 文件和运行时目录 |
| ps 显示 demo | ps 输出包含 demo 服务状态 |

## 本地路由验收

```sh
make local-acceptance           # Docker 模式
make local-acceptance-native    # 原生模式
```

验证 `api.example.com` 返回 `Hostname:` → `test-api.example.com` → 未配置域名 404。

`EASYGATE_ACCEPTANCE_STRICT=true` 控制严格模式（失败即退出）。

## CI

GitHub Actions 在 push、PR 和每周 cron 运行，双平台矩阵：

| 平台 | Shell | 严格 | 超时 | 备注 |
|------|-------|------|------|------|
| ubuntu-latest | Bash | ✅ | 15 min | Docker + 原生双验收 |
| macos-latest | Bash | ❌ | 15 min | Docker + 原生双验收 |

Release 工作流：`git tag <semver>`（如 `0.0.1`）→ 打包 CLI + 校验和嵌入 + cosign 签名 + SPDX SBOM。
