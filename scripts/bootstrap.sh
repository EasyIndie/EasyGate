#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
ENV_EXAMPLE="${ROOT_DIR}/.env.example"

info() {
  printf '\033[1;34m[EasyGate]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m[EasyGate]\033[0m %s\n' "$1"
}

error() {
  printf '\033[1;31m[EasyGate]\033[0m %s\n' "$1" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "缺少命令：$1"
    return 1
  fi
}

compose() {
  docker compose "$@"
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value

  read -r -p "${prompt} [${default}]: " value
  printf '%s' "${value:-$default}"
}

prompt_secret() {
  local prompt="$1"
  local value

  read -r -s -p "${prompt}: " value
  printf '\n' >&2
  printf '%s' "$value"
}

write_env() {
  local base_domain="$1"
  local tunnel_token="$2"
  local dashboard_host="$3"

  cat >"${ENV_FILE}" <<EOF_ENV
BASE_DOMAIN=${base_domain}
CLOUDFLARE_TUNNEL_TOKEN=${tunnel_token}
TRAEFIK_DASHBOARD_HOST=${dashboard_host}
EOF_ENV
}

load_env() {
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

validate_env() {
  local failed=0

  if [[ -z "${BASE_DOMAIN:-}" || "${BASE_DOMAIN}" == "example.com" ]]; then
    error ".env 中的 BASE_DOMAIN 还没有设置为真实域名"
    failed=1
  fi

  if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" || "${CLOUDFLARE_TUNNEL_TOKEN}" == "replace-with-cloudflare-tunnel-token" ]]; then
    error ".env 中的 CLOUDFLARE_TUNNEL_TOKEN 还没有设置"
    failed=1
  fi

  if [[ -z "${TRAEFIK_DASHBOARD_HOST:-}" ]]; then
    error ".env 中的 TRAEFIK_DASHBOARD_HOST 不能为空"
    failed=1
  fi

  return "${failed}"
}

main() {
  cd "${ROOT_DIR}"

  info "开始部署 EasyGate"

  require_command docker || {
    error "请先安装 Docker 和 Docker Compose 插件"
    exit 1
  }

  if ! docker compose version >/dev/null 2>&1; then
    error "当前 Docker 未提供 'docker compose'，请安装 Docker Compose 插件"
    exit 1
  fi

  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ ! -f "${ENV_EXAMPLE}" ]]; then
      error "缺少 .env.example，无法生成 .env"
      exit 1
    fi

    info "首次运行，正在生成 .env"
    base_domain="$(prompt_default "请输入主域名" "example.com")"
    dashboard_host="$(prompt_default "请输入 Traefik dashboard 域名" "traefik.${base_domain}")"
    tunnel_token="$(prompt_secret "请输入 Cloudflare Tunnel token")"
    write_env "${base_domain}" "${tunnel_token}" "${dashboard_host}"
    info ".env 已生成"
  else
    warn ".env 已存在，本脚本不会覆盖现有配置"
  fi

  load_env
  validate_env || {
    error "请修正 .env 后重新运行"
    exit 1
  }

  info "检查 Compose 配置"
  compose --env-file "${ENV_FILE}" config >/dev/null

  info "启动 Traefik 和 cloudflared"
  compose --env-file "${ENV_FILE}" up -d traefik cloudflared

  read -r -p "是否启动演示服务 api.${BASE_DOMAIN} 和 test-api.${BASE_DOMAIN}？[y/N]: " start_demo
  case "${start_demo}" in
    y|Y|yes|YES)
      info "启动演示服务"
      compose --env-file "${ENV_FILE}" --profile demo up -d demo-api demo-test-api
      ;;
    *)
      info "跳过演示服务"
      ;;
  esac

  info "部署完成"
  printf '\n后续检查：\n'
  printf '  docker compose ps\n'
  printf '  docker compose logs -f traefik cloudflared\n'
  printf '  https://%s\n' "${TRAEFIK_DASHBOARD_HOST}"
}

main "$@"
