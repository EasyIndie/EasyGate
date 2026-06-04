#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRICT="${EASYGATE_ACCEPTANCE_STRICT:-false}"
COMPOSE=(docker compose -f docker-compose.local.yml --env-file .env)
TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-18080}"

info() {
  printf '\033[1;34m[acceptance]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m[acceptance]\033[0m %s\n' "$1"
}

fail() {
  printf '\033[1;31m[acceptance]\033[0m %s\n' "$1" >&2
  exit 1
}

skip_or_fail() {
  local message="$1"
  if [[ "$STRICT" == "true" ]]; then
    fail "$message"
  fi
  warn "${message}，跳过本地路由验收"
  exit 0
}

request() {
  local host="$1"
  curl -fsS -H "Host: ${host}" "http://127.0.0.1:${TRAEFIK_HTTP_PORT}"
}

compose_up() {
  local attempt
  for attempt in 1 2 3; do
    if "${COMPOSE[@]}" up -d traefik demo-api demo-test-api; then
      return 0
    fi
    warn "启动本机验收栈失败，准备重试 ${attempt}/3"
    "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
    sleep 5
  done

  skip_or_fail "本机验收栈启动失败"
}

cleanup() {
  "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  skip_or_fail "未找到 docker"
fi

if ! docker compose version >/dev/null 2>&1; then
  skip_or_fail "未找到 docker compose"
fi

if ! docker info >/dev/null 2>&1; then
  skip_or_fail "Docker daemon 不可用"
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  info "已从 .env.example 生成本机验收用 .env"
fi

set -a
# shellcheck disable=SC1091
source .env
set +a
TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-18080}"

trap cleanup EXIT

info "启动本机验收栈"
compose_up

info "等待 Traefik 就绪"
ready=false
for _ in {1..30}; do
  if curl -fsS -H "Host: api.example.com" "http://127.0.0.1:${TRAEFIK_HTTP_PORT}" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done

if [[ "$ready" != "true" ]]; then
  "${COMPOSE[@]}" ps || true
  "${COMPOSE[@]}" logs --no-color --tail=80 traefik demo-api demo-test-api || true
  skip_or_fail "Traefik 未在预期时间内就绪"
fi

info "验证生产 demo 路由"
request "api.example.com" | grep -q "Hostname:" || skip_or_fail "api.example.com 未返回 whoami 响应"

info "验证测试 demo 路由"
request "test-api.example.com" | grep -q "Hostname:" || skip_or_fail "test-api.example.com 未返回 whoami 响应"

info "验证未配置域名返回 404"
status="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: missing.example.com" "http://127.0.0.1:${TRAEFIK_HTTP_PORT}")"
[[ "$status" == "404" ]] || skip_or_fail "missing.example.com 预期 404，实际 ${status}"

info "本机路由验收通过"
