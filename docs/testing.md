# 自动化测试

## 本地测试

运行：

```sh
make test
```

或直接运行：

```sh
./scripts/test.sh
```

只运行部署/清理行为测试：

```sh
make behavior-test
```

Windows 11 PowerShell：

```powershell
.\scripts\test.ps1
```

测试内容：

- 关键文件是否存在。
- 是否残留旧项目名。
- Bash 部署脚本语法。
- Bash 部署和清理脚本行为测试。
- `.env.example` 默认值。
- Traefik 网络命名是否一致。
- README 和 docs 中引用的本地文档是否存在。
- YAML 配置语法。
- Docker Compose 配置是否能渲染。
- PowerShell 测试脚本语法。
- PowerShell 部署和清理脚本行为测试。
- 清理脚本语法。
- 本机验收脚本语法。

## 可选依赖

本地测试会根据环境自动跳过部分检查：

- 没有 Docker 时，跳过 `docker compose config`。
- 没有 Ruby 时，跳过 YAML 解析检查。
- 没有 ShellCheck 时，跳过 Bash lint。
- 没有 PowerShell 时，跳过 PowerShell 语法和行为测试。

这让低配部署设备也可以运行基础测试。

## CI 测试

项目提供 GitHub Actions 工作流：

```text
.github/workflows/ci.yml
```

每次 push 或 pull request 会运行：

```text
ubuntu-latest：make test
macos-latest：make test
windows-latest：.\scripts\test.ps1
```

CI 还会运行本机验收脚本。Ubuntu 强制跑完整容器级验收；macOS 和 Windows 在 Docker daemon 不可用时会跳过运行时验收，但仍覆盖入口脚本兼容性。

## 本机验收

本机路由验收由 `scripts/local-acceptance.sh` 和 `scripts/local-acceptance.ps1` 提供：

```sh
make local-acceptance
```

它会启动 Traefik 和 demo 服务，通过 curl 验证生产域名、测试域名和未配置域名的路由行为。详细说明见 [local-acceptance.md](local-acceptance.md)。

## 行为测试

`scripts/behavior-test.sh` 和 `scripts/behavior-test.ps1` 会在临时目录中 mock `docker` 和 `cloudflared`，不接触真实 Cloudflare 账号、真实 tunnel 凭据或当前部署。

覆盖点：

- 部署脚本在同名 tunnel 已存在时复用本地凭据。
- 部署脚本可以覆盖只读 tunnel 凭据文件。
- `--skip-route` / `-SkipRoute` 不调用 DNS route。
- `--demo` / `-Demo` 会启动 demo 服务。
- 清理脚本默认保留本地配置和 tunnel 凭据。
- purge 只有确认输入 `yes` 后才删除本地生成文件。

## 依赖更新

`.github/dependabot.yml` 每周检查：

- GitHub Actions 版本。
- Docker Compose 中声明的镜像版本。

Dependabot 只创建 PR，不自动合并。镜像更新应通过 CI 和本机验收后再合并。
