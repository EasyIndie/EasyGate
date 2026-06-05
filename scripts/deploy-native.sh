#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${ROOT_DIR}/.easygate/bin:$PATH"
CLOUDFLARED_HOME="${EASYGATE_CLOUDFLARED_HOME:-${HOME}/.cloudflared}"
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

info() {
  printf '\033[1;34m[deploy-native]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m[deploy-native]\033[0m %s\n' "$1"
}

error() {
  printf '\033[1;31m[deploy-native]\033[0m %s\n' "$1" >&2
}

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
  if command -v cloudflared >/dev/null 2>&1; then
    info "已找到 cloudflared：$(command -v cloudflared)"
    return
  fi

  if [[ "$INSTALL_CLOUDFLARED" != true ]]; then
    error "缺少命令：cloudflared"
    exit 1
  fi

  require_command curl || exit 1

  local os arch asset url install_dir tmp_dir downloaded extracted
  os="$(uname -s)"
  arch="$(uname -m)"
  install_dir="${ROOT_DIR}/.easygate/bin"
  tmp_dir="${ROOT_DIR}/.easygate/tmp/cloudflared"

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    armv7l|armv6l) arch="arm" ;;
    i386|i686) arch="386" ;;
    *) error "暂不支持的 CPU 架构：${arch}"; exit 1 ;;
  esac

  mkdir -p "$install_dir" "$tmp_dir"

  case "$os" in
    Darwin)
      asset="cloudflared-darwin-${arch}.tgz"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
      downloaded="${tmp_dir}/${asset}"
      info "下载 cloudflared：${asset}"
      curl -fL --retry 3 --retry-delay 2 -o "$downloaded" "$url"
      rm -rf "${tmp_dir}/extract"
      mkdir -p "${tmp_dir}/extract"
      tar -xzf "$downloaded" -C "${tmp_dir}/extract"
      extracted="$(find "${tmp_dir}/extract" -type f -name cloudflared | head -n 1)"
      [[ -n "$extracted" ]] || { error "未能从 ${asset} 中找到 cloudflared"; exit 1; }
      cp "$extracted" "${install_dir}/cloudflared"
      ;;
    Linux)
      asset="cloudflared-linux-${arch}"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
      info "下载 cloudflared：${asset}"
      curl -fL --retry 3 --retry-delay 2 -o "${install_dir}/cloudflared" "$url"
      ;;
    *) error "deploy-native.sh 仅支持 macOS/Linux 自动安装 cloudflared；Windows 请使用 scripts/deploy-native.ps1"; exit 1 ;;
  esac

  chmod +x "${install_dir}/cloudflared"
  export PATH="${install_dir}:$PATH"
  cloudflared --version >/dev/null
  info "cloudflared 已安装到 ${install_dir}/cloudflared"
}

install_traefik() {
  if command -v traefik >/dev/null 2>&1; then
    info "已找到 traefik：$(command -v traefik)"
    return
  fi

  if [[ "$INSTALL_TRAEFIK" != true ]]; then
    error "缺少命令：traefik"
    exit 1
  fi

  require_command curl || exit 1
  require_command tar || exit 1

  local os arch asset url install_dir tmp_dir downloaded extracted
  os="$(uname -s)"
  arch="$(uname -m)"
  install_dir="${ROOT_DIR}/.easygate/bin"
  tmp_dir="${ROOT_DIR}/.easygate/tmp/traefik"

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    armv7l|armv6l) arch="armv7" ;;
    i386|i686) arch="386" ;;
    *) error "暂不支持的 CPU 架构：${arch}"; exit 1 ;;
  esac

  case "$os" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) error "deploy-native.sh 仅支持 macOS/Linux 自动安装 Traefik；Windows 请使用 scripts/deploy-native.ps1"; exit 1 ;;
  esac

  mkdir -p "$install_dir" "$tmp_dir"
  asset="traefik_v${TRAEFIK_VERSION}_${os}_${arch}.tar.gz"
  url="https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/${asset}"
  downloaded="${tmp_dir}/${asset}"
  info "下载 Traefik：${asset}"
  curl -fL --retry 3 --retry-delay 2 -o "$downloaded" "$url"
  rm -rf "${tmp_dir}/extract"
  mkdir -p "${tmp_dir}/extract"
  tar -xzf "$downloaded" -C "${tmp_dir}/extract"
  extracted="$(find "${tmp_dir}/extract" -type f -name traefik | head -n 1)"
  [[ -n "$extracted" ]] || { error "未能从 ${asset} 中找到 traefik"; exit 1; }
  cp "$extracted" "${install_dir}/traefik"
  chmod +x "${install_dir}/traefik"
  export PATH="${install_dir}:$PATH"
  traefik version >/dev/null
  info "Traefik 已安装到 ${install_dir}/traefik"
}

find_latest_credentials() {
  local search_dir="$1"
  find "$search_dir" -maxdepth 1 -type f -name "*.json" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -n 1
}

find_python() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return
  fi
  return 1
}

compose_deployment_active() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1

  docker compose ps --services --status running 2>/dev/null \
    | grep -Eq '^(traefik|cloudflared)$'
}

assert_no_compose_deployment() {
  if compose_deployment_active; then
    error "检测到 Docker Compose 模式正在运行。请先执行 docker compose down 或 make cleanup，再部署原生模式。"
    exit 1
  fi
}

stop_pid_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return
  fi

  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      kill -0 "$pid" >/dev/null 2>&1 || break
      sleep 0.2
    done
  fi
  rm -f "$file"
}

start_process() {
  local name="$1"
  shift
  local pid_file="${ROOT_DIR}/.easygate/run/${name}.pid"
  local log_file="${ROOT_DIR}/.easygate/logs/${name}.log"

  stop_pid_file "$pid_file"
  info "启动 ${name}"
  nohup "$@" >"$log_file" 2>&1 &
  printf '%s\n' "$!" > "$pid_file"
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

install_traefik
if [[ "$LOCAL_ONLY" != true ]]; then
  install_cloudflared
fi

if [[ -z "$BASE_DOMAIN" ]]; then
  BASE_DOMAIN="$(prompt_default "请输入主域名" "example.com")"
fi

if [[ "$BASE_DOMAIN" == "example.com" && "$LOCAL_ONLY" != true ]]; then
  error "请使用真实域名，不要使用 example.com"
  exit 1
fi

if [[ -z "$DASHBOARD_HOST" ]]; then
  DASHBOARD_HOST="traefik.${BASE_DOMAIN}"
fi

mkdir -p .easygate/native/dynamic .easygate/run .easygate/logs cloudflared

cat > .env <<EOF_ENV
BASE_DOMAIN=${BASE_DOMAIN}
TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT}
TRAEFIK_DASHBOARD_HOST=${DASHBOARD_HOST}
EASYGATE_DEPLOY_MODE=native
EASYGATE_NATIVE_API_PORT=${NATIVE_API_PORT}
EASYGATE_NATIVE_TEST_API_PORT=${NATIVE_TEST_API_PORT}
EOF_ENV

cat > .easygate/native/traefik.yml <<EOF_TRAEFIK
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
    directory: "${ROOT_DIR}/.easygate/native/dynamic"
    watch: true
EOF_TRAEFIK

cat > .easygate/native/dynamic/services.yml <<EOF_DYNAMIC
http:
  routers:
    traefik-dashboard:
      rule: Host(\`${DASHBOARD_HOST}\`)
      entryPoints:
        - web
      service: api@internal
EOF_DYNAMIC

if [[ "$START_DEMO" == true ]]; then
  cat >> .easygate/native/dynamic/services.yml <<EOF_DEMO
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
  cat >> .easygate/native/dynamic/services.yml <<'EOF_NO_DEMO'

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

  before_credentials="$(find_latest_credentials "${CLOUDFLARED_HOME}" || true)"

  info "创建 Cloudflare Tunnel：${TUNNEL_NAME}"
  if ! cloudflared tunnel create "$TUNNEL_NAME"; then
    warn "创建 tunnel 失败。若 tunnel 已存在，将尝试复用本地最新凭据文件。"
  fi

  after_credentials="$(find_latest_credentials "${CLOUDFLARED_HOME}" || true)"
  credentials_source="${after_credentials:-$before_credentials}"

  if [[ -z "$credentials_source" || ! -f "$credentials_source" ]]; then
    error "未找到 tunnel 凭据 JSON。请确认 cloudflared tunnel create 是否成功。"
    exit 1
  fi

  credentials_target="cloudflared/${TUNNEL_NAME}.json"
  credentials_tmp="$(mktemp "cloudflared/${TUNNEL_NAME}.json.XXXXXX")"
  cp "$credentials_source" "$credentials_tmp"
  chmod 600 "$credentials_tmp"
  mv -f "$credentials_tmp" "$credentials_target"
  info "已复制 tunnel 凭据到 ${credentials_target}"

  if [[ "$ROUTE_DNS" == true ]]; then
    info "创建通配 DNS 路由：*.${BASE_DOMAIN}"
    if ! cloudflared tunnel route dns "$TUNNEL_NAME" "*.${BASE_DOMAIN}"; then
      warn "自动创建 DNS 路由失败。请在 Cloudflare DNS 中手动添加 *.${BASE_DOMAIN} -> tunnel。"
    fi
  else
    warn "已跳过 DNS 路由创建"
  fi

  cat > cloudflared/config.native.yml <<EOF_CLOUDFLARED
tunnel: ${TUNNEL_NAME}
credentials-file: ${ROOT_DIR}/cloudflared/${TUNNEL_NAME}.json

ingress:
  - hostname: "*.${BASE_DOMAIN}"
    service: http://127.0.0.1:${TRAEFIK_HTTP_PORT}
  - service: http_status:404
EOF_CLOUDFLARED
fi

if [[ "$START_DEMO" == true ]]; then
  python_bin="$(find_python)" || { error "原生 demo 需要 python3 或 python"; exit 1; }
  start_process "native-demo-api" "$python_bin" "${ROOT_DIR}/scripts/native-demo-server.py" --port "$NATIVE_API_PORT"
  start_process "native-demo-test-api" "$python_bin" "${ROOT_DIR}/scripts/native-demo-server.py" --port "$NATIVE_TEST_API_PORT"
fi

start_process "native-traefik" "$(command -v traefik)" --configFile="${ROOT_DIR}/.easygate/native/traefik.yml"

if [[ "$LOCAL_ONLY" != true ]]; then
  start_process "native-cloudflared" "$(command -v cloudflared)" tunnel --config "${ROOT_DIR}/cloudflared/config.native.yml" run
fi

info "原生部署完成"
printf '\n后续检查：\n'
printf '  ./scripts/local-acceptance-native.sh\n'
printf '  tail -f .easygate/logs/native-traefik.log\n'
if [[ "$LOCAL_ONLY" != true ]]; then
  printf '  tail -f .easygate/logs/native-cloudflared.log\n'
  printf '  https://api.%s\n' "$BASE_DOMAIN"
  printf '  https://test-api.%s\n' "$BASE_DOMAIN"
fi
