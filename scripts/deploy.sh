#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="deploy"
source "${ROOT_DIR}/scripts/lib.sh"

BASE_DOMAIN="${BASE_DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-easygate-home}"
DASHBOARD_HOST="${TRAEFIK_DASHBOARD_HOST:-}"
TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-18080}"
ROUTE_DNS=true
START_DEMO=false
INSTALL_CLOUDFLARED=true
CLOUDFLARED_IMAGE="${EASYGATE_CLOUDFLARED_IMAGE:-cloudflare/cloudflared:2025.2.1}"

usage() {
  cat <<'EOF_USAGE'
用法：
  ./scripts/deploy.sh [选项]

选项：
  --domain <domain>       主域名，例如 example.com
  --tunnel <name>         tunnel 名称，默认 easygate-home
  --dashboard <hostname>  Traefik dashboard 域名，默认 traefik.<domain>
  --port <port>           Traefik 宿主机本地调试端口，默认 18080
  --no-install-cloudflared
                          缺少 cloudflared 时不自动下载本地 CLI
  --skip-route            不自动创建 *.domain 的 DNS 路由
  --demo                  部署后启动演示服务
  -h, --help              显示帮助
EOF_USAGE
}

write_runtime_compose_file() {
  cat > "$COMPOSE_FILE" <<EOF_COMPOSE
services:
  traefik:
    image: traefik:v3.1
    container_name: easygate-traefik
    restart: unless-stopped
    command:
      - --configFile=/etc/traefik/traefik.yml
    ports:
      - "\${TRAEFIK_HTTP_PORT:-18080}:80"
    networks:
      - easygate-proxy
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "${EASYGATE_HOME}/traefik/traefik.yml:/etc/traefik/traefik.yml:ro"
      - "${EASYGATE_HOME}/traefik/dynamic:/etc/traefik/dynamic:ro"
    labels:
      - traefik.enable=true
      - traefik.docker.network=easygate-proxy
      - traefik.http.routers.traefik-dashboard.rule=Host(\`\${TRAEFIK_DASHBOARD_HOST}\`)
      - traefik.http.routers.traefik-dashboard.entrypoints=web
      - traefik.http.routers.traefik-dashboard.service=api@internal
    read_only: true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 32M

  cloudflared:
    image: ${CLOUDFLARED_IMAGE}
    container_name: easygate-cloudflared
    restart: unless-stopped
    command: tunnel --config /etc/cloudflared/config.yml run
    networks:
      - easygate-proxy
    volumes:
      - "${EASYGATE_HOME}/cloudflared:/etc/cloudflared:ro"
    depends_on:
      - traefik
    read_only: true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 16M

  demo-api:
    image: traefik/whoami:v1.10
    profiles: ["demo"]
    restart: unless-stopped
    networks:
      - easygate-proxy
    labels:
      - traefik.enable=true
      - traefik.docker.network=easygate-proxy
      - traefik.http.routers.demo-api.rule=Host(\`api.\${BASE_DOMAIN}\`)
      - traefik.http.routers.demo-api.entrypoints=web
      - traefik.http.services.demo-api.loadbalancer.server.port=80
    read_only: true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: 32M
        reservations:
          memory: 8M

  demo-test-api:
    image: traefik/whoami:v1.10
    profiles: ["demo"]
    restart: unless-stopped
    networks:
      - easygate-proxy
    labels:
      - traefik.enable=true
      - traefik.docker.network=easygate-proxy
      - traefik.http.routers.demo-test-api.rule=Host(\`test-api.\${BASE_DOMAIN}\`)
      - traefik.http.routers.demo-test-api.entrypoints=web
      - traefik.http.services.demo-test-api.loadbalancer.server.port=80
    read_only: true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: 32M
        reservations:
          memory: 8M

networks:
  easygate-proxy:
    name: easygate-proxy
EOF_COMPOSE
}

# deploy.sh-specific: checks for native deployment using relative runtime paths.
assert_no_native_deployment() {
  local file
  for file in \
    run/native-cloudflared.pid \
    run/native-traefik.pid \
    run/native-demo-api.pid \
    run/native-demo-test-api.pid; do
    if native_pid_active "${EASYGATE_HOME}/${file}"; then
      error "检测到原生模式进程正在运行：${EASYGATE_HOME}/${file}。请先执行 easygate stop，再部署 Docker Compose 模式。"
      exit 1
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      shift
      [[ $# -gt 0 ]] || { error "--domain 缺少参数值"; exit 1; }
      BASE_DOMAIN="${1:-}"
      ;;
    --tunnel)
      shift
      [[ $# -gt 0 ]] || { error "--tunnel 缺少参数值"; exit 1; }
      TUNNEL_NAME="${1:-}"
      ;;
    --dashboard)
      shift
      [[ $# -gt 0 ]] || { error "--dashboard 缺少参数值"; exit 1; }
      DASHBOARD_HOST="${1:-}"
      ;;
    --port)
      shift
      [[ $# -gt 0 ]] || { error "--port 缺少参数值"; exit 1; }
      TRAEFIK_HTTP_PORT="${1:-}"
      ;;
    --no-install-cloudflared)
      INSTALL_CLOUDFLARED=false
      ;;
    --skip-route)
      ROUTE_DNS=false
      ;;
    --demo)
      START_DEMO=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "未知参数：$1"
      usage
      exit 1
      ;;
  esac
  shift
done

cd "$ROOT_DIR"

assert_no_native_deployment

require_command docker || exit 1
install_cloudflared "$INSTALL_CLOUDFLARED"

if ! docker compose version >/dev/null 2>&1; then
  error "当前 Docker 未提供 docker compose"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  error "Docker daemon 不可用，请先启动 Docker"
  exit 1
fi

if [[ -z "$BASE_DOMAIN" ]]; then
  BASE_DOMAIN="$(prompt_default "请输入主域名" "example.com")"
fi

validate_domain "$BASE_DOMAIN" || exit 1
validate_tunnel_name "$TUNNEL_NAME" || exit 1
validate_port "$TRAEFIK_HTTP_PORT" "TRAEFIK_HTTP_PORT" || exit 1

if [[ -z "$DASHBOARD_HOST" ]]; then
  DASHBOARD_HOST="traefik.${BASE_DOMAIN}"
fi

info "确认 cloudflared 登录状态"
if [[ ! -f "${CLOUDFLARED_HOME}/cert.pem" ]]; then
  warn "未找到 ${CLOUDFLARED_HOME}/cert.pem，将执行 cloudflared tunnel login"
  cloudflared tunnel login
else
  info "已找到 cloudflared 登录凭据"
fi

mkdir -p "${EASYGATE_HOME}/cloudflared" "${EASYGATE_HOME}/traefik/dynamic" "$COMPOSE_DIR"

prepare_tunnel_credentials "$TUNNEL_NAME"

if [[ "$ROUTE_DNS" == true ]]; then
  info "创建通配 DNS 路由：*.${BASE_DOMAIN}"
  route_output="$(cloudflared tunnel route dns "$TUNNEL_NAME" "*.${BASE_DOMAIN}" 2>&1)" || true
  if echo "$route_output" | grep -q "already exists"; then
    warn "DNS 通配路由已存在。若子域名无法访问，请到 Cloudflare DNS 检查是否有独立子域名记录（如 traefik.${BASE_DOMAIN}、api.${BASE_DOMAIN}）覆盖了通配符。"
  elif ! echo "$route_output" | grep -qE "Added|created"; then
    warn "自动创建 DNS 路由失败：${route_output}"
  fi
else
  warn "已跳过 DNS 路由创建"
fi

cp "${ROOT_DIR}/traefik/traefik.yml" "${EASYGATE_HOME}/traefik/traefik.yml"
cp -R "${ROOT_DIR}/traefik/dynamic/." "${EASYGATE_HOME}/traefik/dynamic/"

cat > "$COMPOSE_ENV" <<EOF_ENV
BASE_DOMAIN=${BASE_DOMAIN}
TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT}
TRAEFIK_DASHBOARD_HOST=${DASHBOARD_HOST}
EASYGATE_HOME=${EASYGATE_HOME}
EOF_ENV

cat > "${EASYGATE_HOME}/cloudflared/config.yml" <<EOF_CONFIG
tunnel: ${TUNNEL_NAME}
credentials-file: /etc/cloudflared/${TUNNEL_NAME}.json
ha-connections: 2
loglevel: warn

ingress:
  - hostname: "*.${BASE_DOMAIN}"
    service: http://traefik:80
  - service: http_status:404
EOF_CONFIG

write_runtime_compose_file

info "检查 Compose 配置"
compose config >/dev/null

info "启动 EasyGate"
compose up -d

if [[ "$START_DEMO" == true ]]; then
  info "启动演示服务"
  compose --profile demo up -d demo-api demo-test-api
fi

info "部署完成"
printf '%s\n' "compose" > "${EASYGATE_HOME}/.mode"
printf '\n后续检查：\n'
printf '  docker compose -p easygate -f "%s" --env-file "%s" ps\n' "$COMPOSE_FILE" "$COMPOSE_ENV"
printf '  docker compose -p easygate -f "%s" --env-file "%s" logs -f traefik cloudflared\n' "$COMPOSE_FILE" "$COMPOSE_ENV"
printf '  运行时目录：%s\n' "$EASYGATE_HOME"
printf '  本地调试入口：http://127.0.0.1:%s\n' "$TRAEFIK_HTTP_PORT"
printf '  https://api.%s\n' "$BASE_DOMAIN"
printf '  https://test-api.%s\n' "$BASE_DOMAIN"
