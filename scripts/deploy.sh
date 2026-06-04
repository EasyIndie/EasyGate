#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DOMAIN="${BASE_DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-easygate-home}"
DASHBOARD_HOST="${TRAEFIK_DASHBOARD_HOST:-}"
TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-18080}"
ROUTE_DNS=true
START_DEMO=false

info() {
  printf '\033[1;34m[deploy]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m[deploy]\033[0m %s\n' "$1"
}

error() {
  printf '\033[1;31m[deploy]\033[0m %s\n' "$1" >&2
}

usage() {
  cat <<'EOF_USAGE'
用法：
  ./scripts/deploy.sh [选项]

选项：
  --domain <domain>       主域名，例如 example.com
  --tunnel <name>         tunnel 名称，默认 easygate-home
  --dashboard <hostname>  Traefik dashboard 域名，默认 traefik.<domain>
  --port <port>           Traefik 宿主机本地调试端口，默认 18080
  --skip-route            不自动创建 *.domain 的 DNS 路由
  --demo                  部署后启动演示服务
  -h, --help              显示帮助
EOF_USAGE
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "${prompt} [${default}]: " value
  printf '%s' "${value:-$default}"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "缺少命令：$1"
    return 1
  fi
}

find_latest_credentials() {
  local search_dir="$1"
  find "$search_dir" -maxdepth 1 -type f -name "*.json" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -n 1
}

for arg in "$@"; do
  case "$arg" in
    --domain)
      shift
      BASE_DOMAIN="${1:-}"
      ;;
    --tunnel)
      shift
      TUNNEL_NAME="${1:-}"
      ;;
    --dashboard)
      shift
      DASHBOARD_HOST="${1:-}"
      ;;
    --port)
      shift
      TRAEFIK_HTTP_PORT="${1:-}"
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
      error "未知参数：$arg"
      usage
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

require_command docker || exit 1
require_command cloudflared || exit 1

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

if [[ "$BASE_DOMAIN" == "example.com" ]]; then
  error "请使用真实域名，不要使用 example.com"
  exit 1
fi

if [[ -z "$DASHBOARD_HOST" ]]; then
  DASHBOARD_HOST="traefik.${BASE_DOMAIN}"
fi

info "确认 cloudflared 登录状态"
if [[ ! -f "${HOME}/.cloudflared/cert.pem" ]]; then
  warn "未找到 ${HOME}/.cloudflared/cert.pem，将执行 cloudflared tunnel login"
  cloudflared tunnel login
else
  info "已找到 cloudflared 登录凭据"
fi

mkdir -p cloudflared

before_credentials="$(find_latest_credentials "${HOME}/.cloudflared" || true)"

info "创建 Cloudflare Tunnel：${TUNNEL_NAME}"
if ! cloudflared tunnel create "$TUNNEL_NAME"; then
  warn "创建 tunnel 失败。若 tunnel 已存在，将尝试复用本地最新凭据文件。"
fi

after_credentials="$(find_latest_credentials "${HOME}/.cloudflared" || true)"
credentials_source="${after_credentials:-$before_credentials}"

if [[ -z "$credentials_source" || ! -f "$credentials_source" ]]; then
  error "未找到 tunnel 凭据 JSON。请确认 cloudflared tunnel create 是否成功。"
  exit 1
fi

credentials_target="cloudflared/${TUNNEL_NAME}.json"
cp "$credentials_source" "$credentials_target"
info "已复制 tunnel 凭据到 ${credentials_target}"

if [[ "$ROUTE_DNS" == true ]]; then
  info "创建通配 DNS 路由：*.${BASE_DOMAIN}"
  if ! cloudflared tunnel route dns "$TUNNEL_NAME" "*.${BASE_DOMAIN}"; then
    warn "自动创建 DNS 路由失败。请在 Cloudflare DNS 中手动添加 *.${BASE_DOMAIN} -> tunnel。"
  fi
else
  warn "已跳过 DNS 路由创建"
fi

cat > .env <<EOF_ENV
BASE_DOMAIN=${BASE_DOMAIN}
TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT}
TRAEFIK_DASHBOARD_HOST=${DASHBOARD_HOST}
EOF_ENV

cat > cloudflared/config.yml <<EOF_CONFIG
tunnel: ${TUNNEL_NAME}
credentials-file: /etc/cloudflared/${TUNNEL_NAME}.json

ingress:
  - hostname: "*.${BASE_DOMAIN}"
    service: http://traefik:80
  - service: http_status:404
EOF_CONFIG

info "检查 Compose 配置"
docker compose --env-file .env config >/dev/null

info "启动 EasyGate"
docker compose up -d

if [[ "$START_DEMO" == true ]]; then
  info "启动演示服务"
  docker compose --profile demo up -d demo-api demo-test-api
fi

info "部署完成"
printf '\n后续检查：\n'
printf '  docker compose ps\n'
printf '  docker compose logs -f traefik cloudflared\n'
printf '  本地调试入口：http://127.0.0.1:%s\n' "$TRAEFIK_HTTP_PORT"
printf '  https://api.%s\n' "$BASE_DOMAIN"
printf '  https://test-api.%s\n' "$BASE_DOMAIN"
