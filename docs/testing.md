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

CI 用于防止后续迭代破坏 Compose 配置、脚本语法、命名约定、文档链接和跨平台入口。

## 后续可扩展测试

后续可以继续增加：

- 使用临时 `.env` 的部署脚本非交互测试。
- 使用 `docker compose up` 启动 demo 服务的集成测试。
- 通过 curl 验证 Traefik 本地路由。
- 使用容器内 mock 服务验证 Docker labels 自动发现。
- 使用临时配置检查 `cloudflared` ingress 规则。
