# 清理

清理前先区分目标：

- 只结束 demo 验收：移除 demo 容器，保留 EasyGate 基础入口。
- 暂停 EasyGate：停止并移除 Compose 容器和网络，保留本地配置。
- 彻底清理本机：删除本地生成配置、CLI 和 tunnel 凭据。

## 只清理 demo

公网或本机验收完成后，推荐只移除 demo 服务：

```sh
./scripts/compose.sh --profile demo stop demo-api demo-test-api
./scripts/compose.sh --profile demo rm -f demo-api demo-test-api
```

清理后 `traefik` 和 `cloudflared` 会继续运行，`api.example.com`、`test-api.example.com` 如果没有其他服务接管，会返回 404。

## 停止 EasyGate，保留配置

macOS / Linux：

```sh
make cleanup
```

或：

```sh
./scripts/cleanup.sh
```

Windows PowerShell：

```powershell
.\scripts\cleanup.ps1
```

默认清理会停止并移除 Docker Compose 创建的容器和网络，保留：

- `.env`
- `EASYGATE_HOME`
- Traefik 配置
- Cloudflare DNS 记录
- Cloudflare Tunnel

## 彻底清理本地文件

确认这台机器不再需要本地配置和 tunnel 凭据后：

```sh
make purge
```

或：

```sh
./scripts/cleanup.sh --purge
```

Windows PowerShell：

```powershell
.\scripts\cleanup.ps1 -Purge
```

脚本会要求输入 `yes`，然后删除：

- `.env`
- `EASYGATE_HOME`

## Cloudflare 侧资源

清理脚本不会删除 Cloudflare 上的 DNS 记录或 tunnel。原因是这些资源可能仍被其他设备或服务使用。

如果确认要删除 Cloudflare 侧资源，请在 Cloudflare Dashboard 中手动删除，或使用 `cloudflared` CLI 处理。删除前先确认没有其他服务依赖同一个 tunnel 或通配 DNS 路由。
