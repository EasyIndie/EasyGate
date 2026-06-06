#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="acceptance-native"
source "${ROOT_DIR}/scripts/lib.sh"

EASYGATE_CLI="${EASYGATE_CLI:-${ROOT_DIR}/scripts/easygate}"
STRICT="${EASYGATE_ACCEPTANCE_STRICT:-false}"
TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-18080}"
ENV_BACKUP="$(mktemp "${TMPDIR:-/tmp}/easygate-native-env.XXXXXX")"
HAD_ENV=false

fail() {
  printf '\033[1;31m[acceptance-native]\033[0m %s\n' "$1" >&2
  exit 1
}

skip_or_fail() {
  local message="$1"
  if [[ "$STRICT" == "true" ]]; then
    fail "$message"
  fi
  warn "${message}，跳过原生本机路由验收"
  exit 0
}

request() {
  local host="$1"
  curl -fsS -H "Host: ${host}" "http://127.0.0.1:${TRAEFIK_HTTP_PORT}"
}

cleanup() {
  "${ROOT_DIR}/scripts/cleanup-native.sh" >/dev/null 2>&1 || true
  if [[ "$HAD_ENV" == true ]]; then
    cp "$ENV_BACKUP" "${ROOT_DIR}/.env"
  else
    rm -f "${ROOT_DIR}/.env"
  fi
  rm -f "$ENV_BACKUP"
}

cd "$ROOT_DIR"

if [[ -f .env ]]; then
  cp .env "$ENV_BACKUP"
  HAD_ENV=true
fi

if ! command -v curl >/dev/null 2>&1; then
  skip_or_fail "未找到 curl"
fi

trap cleanup EXIT

info "启动原生本机验收栈"
if ! "$EASYGATE_CLI" deploy --native --domain example.com --demo --local-only; then
  skip_or_fail "原生本机验收栈启动失败"
fi

BASE_DOMAIN="example.com"
PROD_HOST="api.${BASE_DOMAIN}"
TEST_HOST="test-api.${BASE_DOMAIN}"

info "等待原生 Traefik 就绪"
ready=false
for _ in {1..15}; do
  if curl -fsS -H "Host: ${PROD_HOST}" "http://127.0.0.1:${TRAEFIK_HTTP_PORT}" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done

if [[ "$ready" != "true" ]]; then
  tail -n 80 "${EASYGATE_HOME}/logs/native-traefik.log" 2>/dev/null || true
  skip_or_fail "原生 Traefik 未在预期时间内就绪"
fi

info "验证原生生产 demo 路由"
request "${PROD_HOST}" | grep -q "Hostname:" || skip_or_fail "${PROD_HOST} 未返回 demo 响应"

info "验证原生测试 demo 路由"
request "${TEST_HOST}" | grep -q "Hostname:" || skip_or_fail "${TEST_HOST} 未返回 demo 响应"

info "验证未配置域名返回 404"
status="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: missing.example.com" "http://127.0.0.1:${TRAEFIK_HTTP_PORT}")"
[[ "$status" == "404" ]] || skip_or_fail "missing.example.com 预期 404，实际 ${status}"

info "原生本机路由验收通过"
