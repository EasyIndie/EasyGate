# 一键部署

## 使用方式

首次部署推荐运行：

```sh
./scripts/bootstrap.sh
```

或者：

```sh
make bootstrap
```

Windows 11 PowerShell 推荐运行：

```powershell
.\scripts\bootstrap.ps1
```

脚本会自动完成：

- 检查 Docker 是否存在。
- 检查 Docker Compose 插件是否可用。
- 首次运行时交互式生成 `.env`。
- 校验 `.env` 中的域名和 Cloudflare Tunnel token。
- 执行 `docker compose config` 检查配置。
- 启动 Traefik 和 cloudflared。
- 可选启动演示服务。

## 不覆盖现有配置

如果 `.env` 已存在，脚本不会覆盖它。这样可以避免误删已有 tunnel token 或域名配置。

需要重新生成时，可以手动备份并删除 `.env` 后再次运行脚本。

## 仍需手动完成的 Cloudflare 配置

一键部署脚本不会替你登录 Cloudflare 或创建 tunnel。运行脚本前仍需完成：

1. 将域名切到 Cloudflare Full DNS setup。
2. 创建 Cloudflare Tunnel。
3. 获取 tunnel token。
4. 添加 public hostname：

   ```text
   *.example.com -> http://traefik:80
   ```

5. 为测试服务、管理后台、内部工具配置 Cloudflare Access。

## 常见失败原因

- 设备未安装 Docker。
- Docker 版本过旧，没有 `docker compose` 插件。
- Windows 11 没有启用 Docker Desktop WSL2 后端，或正在使用 Windows containers。
- `.env` 中仍然是 `example.com`。
- `.env` 中没有填写 `CLOUDFLARE_TUNNEL_TOKEN`。
- Cloudflare Tunnel public hostname 没有指向 `http://traefik:80`。
