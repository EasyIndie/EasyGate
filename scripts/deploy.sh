#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_easygate_home() {
  if [[ -n "${EASYGATE_HOME:-}" ]]; then
    printf '%s' "$EASYGATE_HOME"
    return
  fi

  case "$(uname -s)" in
    Darwin) printf '%s' "${HOME}/Library/Application Support/EasyGate" ;;
    *) printf '%s' "${XDG_DATA_HOME:-${HOME}/.local/share}/easygate" ;;
  esac
}

EASYGATE_HOME="$(default_easygate_home)"
export EASYGATE_HOME
export PATH="${EASYGATE_HOME}/bin:$PATH"
CLOUDFLARED_HOME="${EASYGATE_CLOUDFLARED_HOME:-${HOME}/.cloudflared}"
COMPOSE_DIR="${EASYGATE_HOME}/compose"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
COMPOSE_ENV="${COMPOSE_DIR}/.env"
BASE_DOMAIN="${BASE_DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-easygate-home}"
DASHBOARD_HOST="${TRAEFIK_DASHBOARD_HOST:-}"
TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-18080}"
ROUTE_DNS=true
START_DEMO=false
INSTALL_CLOUDFLARED=true

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
  --no-install-cloudflared
                          缺少 cloudflared 时不自动下载本地 CLI
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

install_cloudflared() {
  local install_dir="${EASYGATE_HOME}/bin"

  if [[ -x "${install_dir}/cloudflared" ]]; then
    info "已找到项目内 cloudflared：${install_dir}/cloudflared"
    return
  fi

  if command -v cloudflared >/dev/null 2>&1; then
    if [[ "$INSTALL_CLOUDFLARED" != true ]]; then
      info "已找到 cloudflared：$(command -v cloudflared)"
      return
    fi

    info "将安装项目内最新 cloudflared，避免系统旧版本产生部署警告"
  fi

  if [[ "$INSTALL_CLOUDFLARED" != true ]]; then
    error "缺少命令：cloudflared"
    exit 1
  fi

  require_command curl || exit 1

  local os arch asset url tmp_dir downloaded extracted
  os="$(uname -s)"
  arch="$(uname -m)"
  tmp_dir="${EASYGATE_HOME}/tmp/cloudflared"

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    armv7l|armv6l) arch="arm" ;;
    i386|i686) arch="386" ;;
    *)
      error "暂不支持的 CPU 架构：${arch}"
      exit 1
      ;;
  esac

  mkdir -p "$install_dir" "$tmp_dir"

  case "$os" in
    Darwin)
      if [[ "$arch" != "amd64" && "$arch" != "arm64" ]]; then
        error "macOS 暂不支持的 cloudflared 架构：${arch}"
        exit 1
      fi
      asset="cloudflared-darwin-${arch}.tgz"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
      downloaded="${tmp_dir}/${asset}"
      info "下载 cloudflared：${asset}"
      curl -fL --retry 3 --retry-delay 2 -o "$downloaded" "$url"
      rm -rf "${tmp_dir}/extract"
      mkdir -p "${tmp_dir}/extract"
      tar -xzf "$downloaded" -C "${tmp_dir}/extract"
      extracted="$(find "${tmp_dir}/extract" -type f -name cloudflared | head -n 1)"
      if [[ -z "$extracted" ]]; then
        error "未能从 ${asset} 中找到 cloudflared"
        exit 1
      fi
      cp "$extracted" "${install_dir}/cloudflared"
      ;;
    Linux)
      asset="cloudflared-linux-${arch}"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
      info "下载 cloudflared：${asset}"
      curl -fL --retry 3 --retry-delay 2 -o "${install_dir}/cloudflared" "$url"
      ;;
    *)
      error "deploy.sh 仅支持 macOS/Linux 自动安装 cloudflared；Windows 请使用 scripts/deploy.ps1"
      exit 1
      ;;
  esac

  chmod +x "${install_dir}/cloudflared"
  export PATH="${install_dir}:$PATH"
  cloudflared --version >/dev/null
  info "cloudflared 已安装到 ${install_dir}/cloudflared"
}

find_latest_credentials() {
  local search_dir="$1"
  find "$search_dir" -maxdepth 1 -type f -name "*.json" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -n 1
}

prepare_tunnel_credentials() {
  local target="${EASYGATE_HOME}/cloudflared/${TUNNEL_NAME}.json"
  local before_credentials after_credentials credentials_source credentials_tmp

  if [[ -f "$target" ]]; then
    info "复用已有 tunnel 凭据：${target}"
    return
  fi

  before_credentials="$(find_latest_credentials "${CLOUDFLARED_HOME}" || true)"

  info "创建 Cloudflare Tunnel：${TUNNEL_NAME}"
  if ! cloudflared tunnel create "$TUNNEL_NAME"; then
    warn "创建 tunnel 失败。若 tunnel 已存在，将尝试复用本地最新凭据文件。"
  fi

  after_credentials="$(find_latest_credentials "${CLOUDFLARED_HOME}" || true)"
  credentials_source="${after_credentials:-$before_credentials}"

  if [[ -z "$credentials_source" || ! -f "$credentials_source" ]]; then
    error "未找到 tunnel 凭据 JSON。请确认 cloudflared tunnel create 是否成功，或将已有凭据保存为 ${target}。"
    exit 1
  fi

  credentials_tmp="$(mktemp "${EASYGATE_HOME}/cloudflared/${TUNNEL_NAME}.json.XXXXXX")"
  cp "$credentials_source" "$credentials_tmp"
  chmod 600 "$credentials_tmp"
  mv -f "$credentials_tmp" "$target"
  info "已复制 tunnel 凭据到 ${target}"
}

compose() {
  docker compose -p easygate -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" "$@"
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

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: easygate-cloudflared
    restart: unless-stopped
    command: tunnel --config /etc/cloudflared/config.yml run
    networks:
      - easygate-proxy
    volumes:
      - "${EASYGATE_HOME}/cloudflared:/etc/cloudflared:ro"
    depends_on:
      - traefik

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

networks:
  easygate-proxy:
    name: easygate-proxy
EOF_COMPOSE
}

native_pid_active() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

assert_no_native_deployment() {
  local file
  for file in \
    run/native-cloudflared.pid \
    run/native-traefik.pid \
    run/native-demo-api.pid \
    run/native-demo-test-api.pid; do
    if native_pid_active "${EASYGATE_HOME}/${file}"; then
      error "检测到原生模式进程正在运行：${EASYGATE_HOME}/${file}。请先执行 ./scripts/cleanup-native.sh，再部署 Docker Compose 模式。"
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
install_cloudflared

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
if [[ ! -f "${CLOUDFLARED_HOME}/cert.pem" ]]; then
  warn "未找到 ${CLOUDFLARED_HOME}/cert.pem，将执行 cloudflared tunnel login"
  cloudflared tunnel login
else
  info "已找到 cloudflared 登录凭据"
fi

mkdir -p "${EASYGATE_HOME}/cloudflared" "${EASYGATE_HOME}/traefik/dynamic" "$COMPOSE_DIR"

prepare_tunnel_credentials

if [[ "$ROUTE_DNS" == true ]]; then
  info "创建通配 DNS 路由：*.${BASE_DOMAIN}"
  if ! cloudflared tunnel route dns "$TUNNEL_NAME" "*.${BASE_DOMAIN}"; then
    warn "自动创建 DNS 路由失败。请在 Cloudflare DNS 中手动添加 *.${BASE_DOMAIN} -> tunnel。"
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
printf '\n后续检查：\n'
printf '  docker compose -p easygate -f "%s" --env-file "%s" ps\n' "$COMPOSE_FILE" "$COMPOSE_ENV"
printf '  docker compose -p easygate -f "%s" --env-file "%s" logs -f traefik cloudflared\n' "$COMPOSE_FILE" "$COMPOSE_ENV"
printf '  运行时目录：%s\n' "$EASYGATE_HOME"
printf '  本地调试入口：http://127.0.0.1:%s\n' "$TRAEFIK_HTTP_PORT"
printf '  https://api.%s\n' "$BASE_DOMAIN"
printf '  https://test-api.%s\n' "$BASE_DOMAIN"
