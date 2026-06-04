# 清理部署

EasyGate 支持一键清理部署。

## 默认清理

默认清理只停止并移除 Docker Compose 创建的容器和网络，不删除本地配置和 tunnel 凭据。

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

默认清理会保留：

- `.env`
- `.easygate/`
- `cloudflared/config.yml`
- `cloudflared/<TUNNEL_ID>.json`
- Traefik 配置
- Cloudflare DNS 记录
- Cloudflare Tunnel

## 彻底清理本地文件

如果确认要删除本地生成配置和 tunnel 凭据：

macOS / Linux：

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

彻底清理会先要求输入 `yes` 确认，然后删除：

- `.env`
- `.easygate/`
- `cloudflared/config.yml`
- `cloudflared/*.json`

## 不会自动删除的 Cloudflare 资源

清理脚本不会删除 Cloudflare 上的 DNS 记录或 tunnel。原因是这些资源可能仍被其他设备或服务使用。

如果你确实要删除 Cloudflare 侧资源，请手动确认后再执行：

```sh
cloudflared tunnel route dns delete easygate-home "*.example.com"
cloudflared tunnel delete easygate-home
```

具体命令是否可用取决于当前 `cloudflared` 版本。删除前建议先确认没有其他服务依赖该 tunnel。
