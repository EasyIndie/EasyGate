#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="deploy-native"
source "${ROOT_DIR}/scripts/lib.sh"

BASE_DOMAIN="${BASE_DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-easygate-home}"
DASHBOARD_HOST="${TRAEFIK_DASHBOARD_HOST:-}"
TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-18080}"
NATIVE_API_PORT="${EASYGATE_NATIVE_API_PORT:-19080}"
NATIVE_TEST_API_PORT="${EASYGATE_NATIVE_TEST_API_PORT:-19081}"
TRAEFIK_VERSION="${EASYGATE_TRAEFIK_VERSION:-3.1.7}"
ROUTE_DNS=true
START_DEMO=false
LOCAL_ONLY=false
INSTALL_CLOUDFLARED=true
INSTALL_TRAEFIK=true

usage() {
  cat <<'EOF_USAGE'
用法：
  ./scripts/deploy-native.sh [选项]

选项：
  --domain <domain>       主域名，例如 example.com
  --tunnel <name>         tunnel 名称，默认 easygate-home
  --dashboard <hostname>  Traefik dashboard 域名，默认 traefik.<domain>
  --port <port>           原生 Traefik 本地监听端口，默认 18080
  --api-port <port>       原生 demo api 端口，默认 19080
  --test-api-port <port>  原生 demo test-api 端口，默认 19081
  --no-install-cloudflared
                          缺少 cloudflared 时不自动下载本地 CLI
  --no-install-traefik    缺少 traefik 时不自动下载本地 CLI
  --skip-route            不自动创建 *.domain 的 DNS 路由
  --demo                  部署后启动原生 demo 服务
  --local-only            只启动 Traefik 和 demo，不创建或启动 cloudflared
  -h, --help              显示帮助
EOF_USAGE
}

assert_no_compose_deployment() {
  if compose_deployment_active; then
    error "检测到 Docker Compose 模式正在运行。请先执行 docker compose down 或 make cleanup，再部署原生模式。"
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) shift; [[ $# -gt 0 ]] || { error "--domain 缺少参数值"; exit 1; }; BASE_DOMAIN="${1:-}" ;;
    --tunnel) shift; [[ $# -gt 0 ]] || { error "--tunnel 缺少参数值"; exit 1; }; TUNNEL_NAME="${1:-}" ;;
    --dashboard) shift; [[ $# -gt 0 ]] || { error "--dashboard 缺少参数值"; exit 1; }; DASHBOARD_HOST="${1:-}" ;;
    --port) shift; [[ $# -gt 0 ]] || { error "--port 缺少参数值"; exit 1; }; TRAEFIK_HTTP_PORT="${1:-}" ;;
    --api-port) shift; [[ $# -gt 0 ]] || { error "--api-port 缺少参数值"; exit 1; }; NATIVE_API_PORT="${1:-}" ;;
    --test-api-port) shift; [[ $# -gt 0 ]] || { error "--test-api-port 缺少参数值"; exit 1; }; NATIVE_TEST_API_PORT="${1:-}" ;;
    --no-install-cloudflared) INSTALL_CLOUDFLARED=false ;;
    --no-install-traefik) INSTALL_TRAEFIK=false ;;
    --skip-route) ROUTE_DNS=false ;;
    --demo) START_DEMO=true ;;
    --local-only) LOCAL_ONLY=true; ROUTE_DNS=false ;;
    -h|--help) usage; exit 0 ;;
    *) error "未知参数：$1"; usage; exit 1 ;;
  esac
  shift
done

cd "$ROOT_DIR"

assert_no_compose_deployment

install_traefik "$INSTALL_TRAEFIK" "$TRAEFIK_VERSION"
if [[ "$LOCAL_ONLY" != true ]]; then
  install_cloudflared "$INSTALL_CLOUDFLARED"
fi

if [[ -z "$BASE_DOMAIN" ]]; then
  BASE_DOMAIN="$(prompt_default "请输入主域名" "example.com")"
fi

if [[ "$LOCAL_ONLY" != true ]]; then
  validate_domain "$BASE_DOMAIN" || exit 1
fi
validate_tunnel_name "$TUNNEL_NAME" || exit 1
validate_port "$TRAEFIK_HTTP_PORT" "TRAEFIK_HTTP_PORT" || exit 1
validate_port "$NATIVE_API_PORT" "NATIVE_API_PORT" || exit 1
validate_port "$NATIVE_TEST_API_PORT" "NATIVE_TEST_API_PORT" || exit 1

if [[ -z "$DASHBOARD_HOST" ]]; then
  DASHBOARD_HOST="traefik.${BASE_DOMAIN}"
fi

mkdir -p "${EASYGATE_HOME}/native/dynamic" "${EASYGATE_HOME}/run" "${EASYGATE_HOME}/logs" "${EASYGATE_HOME}/cloudflared" "${EASYGATE_HOME}/lib"

cat > "${EASYGATE_HOME}/native/.env" <<EOF_ENV
BASE_DOMAIN=${BASE_DOMAIN}
TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT}
TRAEFIK_DASHBOARD_HOST=${DASHBOARD_HOST}
EASYGATE_DEPLOY_MODE=native
EASYGATE_NATIVE_API_PORT=${NATIVE_API_PORT}
EASYGATE_NATIVE_TEST_API_PORT=${NATIVE_TEST_API_PORT}
EASYGATE_HOME=${EASYGATE_HOME}
EOF_ENV

cat > "${EASYGATE_HOME}/native/traefik.yml" <<EOF_TRAEFIK
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true

entryPoints:
  web:
    address: "127.0.0.1:${TRAEFIK_HTTP_PORT}"

providers:
  file:
    directory: "${EASYGATE_HOME}/native/dynamic"
    watch: true
EOF_TRAEFIK

cat > "${EASYGATE_HOME}/native/dynamic/services.yml" <<EOF_DYNAMIC
http:
  routers:
    traefik-dashboard:
      rule: Host(\`${DASHBOARD_HOST}\`)
      entryPoints:
        - web
      service: api@internal
EOF_DYNAMIC

if [[ "$START_DEMO" == true ]]; then
  cat >> "${EASYGATE_HOME}/native/dynamic/services.yml" <<EOF_DEMO
    demo-api:
      rule: Host(\`api.${BASE_DOMAIN}\`)
      entryPoints:
        - web
      service: demo-api
    demo-test-api:
      rule: Host(\`test-api.${BASE_DOMAIN}\`)
      entryPoints:
        - web
      service: demo-test-api

  services:
    demo-api:
      loadBalancer:
        servers:
          - url: http://127.0.0.1:${NATIVE_API_PORT}
    demo-test-api:
      loadBalancer:
        servers:
          - url: http://127.0.0.1:${NATIVE_TEST_API_PORT}
EOF_DEMO
else
  cat >> "${EASYGATE_HOME}/native/dynamic/services.yml" <<'EOF_NO_DEMO'

  services: {}
EOF_NO_DEMO
fi

if [[ "$LOCAL_ONLY" != true ]]; then
  info "确认 cloudflared 登录状态"
  if [[ ! -f "${CLOUDFLARED_HOME}/cert.pem" ]]; then
    warn "未找到 ${CLOUDFLARED_HOME}/cert.pem，将执行 cloudflared tunnel login"
    cloudflared tunnel login
  else
    info "已找到 cloudflared 登录凭据"
  fi

  prepare_tunnel_credentials "$TUNNEL_NAME"

  if [[ "$ROUTE_DNS" == true ]]; then
    info "创建通配 DNS 路由：*.${BASE_DOMAIN}"
    if ! cloudflared tunnel route dns "$TUNNEL_NAME" "*.${BASE_DOMAIN}"; then
      warn "自动创建 DNS 路由失败。请在 Cloudflare DNS 中手动添加 *.${BASE_DOMAIN} -> tunnel。"
    fi
  else
    warn "已跳过 DNS 路由创建"
  fi

  cat > "${EASYGATE_HOME}/cloudflared/config.native.yml" <<EOF_CLOUDFLARED
tunnel: ${TUNNEL_NAME}
credentials-file: ${EASYGATE_HOME}/cloudflared/${TUNNEL_NAME}.json

ingress:
  - hostname: "*.${BASE_DOMAIN}"
    service: http://127.0.0.1:${TRAEFIK_HTTP_PORT}
  - service: http_status:404
EOF_CLOUDFLARED
fi

if [[ "$START_DEMO" == true ]]; then
  python_bin="$(find_python)" || { error "原生 demo 需要 python3 或 python"; exit 1; }
  cp "${ROOT_DIR}/scripts/native-demo-server.py" "${EASYGATE_HOME}/lib/native-demo-server.py"
  start_process "native-demo-api" "$python_bin" "${EASYGATE_HOME}/lib/native-demo-server.py" --port "$NATIVE_API_PORT"
  start_process "native-demo-test-api" "$python_bin" "${EASYGATE_HOME}/lib/native-demo-server.py" --port "$NATIVE_TEST_API_PORT"
fi

start_process "native-traefik" "$(command -v traefik)" --configFile="${EASYGATE_HOME}/native/traefik.yml"

if [[ "$LOCAL_ONLY" != true ]]; then
  start_process "native-cloudflared" "$(command -v cloudflared)" tunnel --config "${EASYGATE_HOME}/cloudflared/config.native.yml" run
fi

# Register system services for auto-restart on reboot.
case "$(uname -s)" in
  Linux)
    register_systemd "native-traefik" "$(command -v traefik)" \
      "--configFile=${EASYGATE_HOME}/native/traefik.yml" \
      "EasyGate Traefik" "network.target"
    if [[ "$LOCAL_ONLY" != true ]]; then
      register_systemd "native-cloudflared" "$(command -v cloudflared)" \
        "tunnel --config ${EASYGATE_HOME}/cloudflared/config.native.yml run" \
        "EasyGate Cloudflared Tunnel" "network.target"
    fi
    ;;
  Darwin)
    register_launchd "native-traefik" "$(command -v traefik)" \
      "--configFile=${EASYGATE_HOME}/native/traefik.yml"
    if [[ "$LOCAL_ONLY" != true ]]; then
      register_launchd "native-cloudflared" "$(command -v cloudflared)" \
        "tunnel --config ${EASYGATE_HOME}/cloudflared/config.native.yml run"
    fi
    ;;
esac

info "原生部署完成"
printf '\n后续检查：\n'
printf '  ./scripts/local-acceptance-native.sh\n'
printf '  运行时目录：%s\n' "$EASYGATE_HOME"
printf '  tail -f "%s/logs/native-traefik.log"\n' "$EASYGATE_HOME"
if [[ "$LOCAL_ONLY" != true ]]; then
  printf '  tail -f "%s/logs/native-cloudflared.log"\n' "$EASYGATE_HOME"
  printf '  https://api.%s\n' "$BASE_DOMAIN"
  printf '  https://test-api.%s\n' "$BASE_DOMAIN"
fi
