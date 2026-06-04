# 与已有 nginx 共存

## 默认不会冲突

本项目默认不会占用宿主机的 80 或 443 端口：

```yaml
ports:
  - "${TRAEFIK_HTTP_PORT:-18080}:80"
```

这表示 Traefik 容器内部监听 80，但宿主机默认只暴露 `18080` 给局域网调试。公网流量通过 Cloudflare Tunnel 进入 Docker 网络，并访问：

```text
http://traefik:80
```

因此，如果设备上已有 nginx 正在监听宿主机的 80/443，通常不会和本项目冲突。

## 会冲突的情况

以下情况会发生端口冲突：

- 把 Traefik 改成 `80:80` 或 `443:443`。
- nginx 和 Traefik 都尝试监听同一个宿主机端口。
- Cloudflare Tunnel 被配置成访问宿主机 nginx，例如 `http://localhost:80`，同时你又希望流量进入 Traefik。

## 推荐做法

- 保持本项目默认端口映射 `${TRAEFIK_HTTP_PORT:-18080}:80`。
- 如果宿主机上 `18080` 也被占用，在 `.env` 中改成另一个端口：

  ```env
  TRAEFIK_HTTP_PORT=28080
  ```

  修改后执行：

  ```sh
  docker compose --env-file .env up -d
  ```

- Cloudflare Tunnel public hostname 使用：

  ```text
  *.example.com -> http://traefik:80
  ```

- 让 nginx 继续处理原有服务，Traefik 只处理接入 EasyGate 的服务。
- 如果某个现有 nginx 服务也要接入 EasyGate，可以在 Traefik file provider 中把它作为上游：

  ```yaml
  http:
    routers:
      legacy-nginx:
        rule: Host(`legacy.example.com`)
        entryPoints:
          - web
        service: legacy-nginx

    services:
      legacy-nginx:
        loadBalancer:
          servers:
            - url: http://host.docker.internal:80
  ```

## 选择唯一公网入口

公网入口建议只保留 Cloudflare Tunnel，不要同时开放 nginx 或 Traefik 的公网 80/443。这样可以避免端口争抢、证书重复配置和访问策略分散。
