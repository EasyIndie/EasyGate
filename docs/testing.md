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

Windows 11 PowerShell：

```powershell
.\scripts\test.ps1
```

测试内容：

- 关键文件是否存在。
- 是否残留旧项目名。
- Bash 部署脚本语法。
- `.env.example` 默认值。
- Traefik 网络命名是否一致。
- README 和 docs 中引用的本地文档是否存在。
- YAML 配置语法。
- Docker Compose 配置是否能渲染。
- PowerShell 测试脚本语法。
- 清理脚本语法。
- 本机验收脚本语法。

## 可选依赖

本地测试会根据环境自动跳过部分检查：

- 没有 Docker 时，跳过 `docker compose config`。
- 没有 Ruby 时，跳过 YAML 解析检查。
- 没有 PowerShell 时，跳过 `test.ps1` 语法检查。

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
