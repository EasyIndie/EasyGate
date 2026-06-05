#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PURGE=false

info() {
  printf '\033[1;34m[cleanup-native]\033[0m %s\n' "$1"
}

usage() {
  cat <<'EOF_USAGE'
用法：
  ./scripts/cleanup-native.sh [--purge]

默认只停止原生模式进程，保留配置、日志和 tunnel 凭据。
--purge 会删除 .easygate/native、.easygate/run、.easygate/logs、cloudflared/config.native.yml。
EOF_USAGE
}

stop_pid_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return
  fi

  local pid name
  pid="$(cat "$file" 2>/dev/null || true)"
  name="$(basename "$file" .pid)"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      kill -0 "$pid" >/dev/null 2>&1 || break
      sleep 0.2
    done
    info "已停止 ${name}"
  fi
  rm -f "$file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf '未知参数：%s\n' "$1" >&2; usage; exit 1 ;;
  esac
  shift
done

cd "$ROOT_DIR"

for pid_file in \
  .easygate/run/native-cloudflared.pid \
  .easygate/run/native-traefik.pid \
  .easygate/run/native-demo-api.pid \
  .easygate/run/native-demo-test-api.pid; do
  stop_pid_file "$pid_file"
done

if [[ "$PURGE" == true ]]; then
  rm -rf .easygate/native .easygate/run .easygate/logs
  rm -f cloudflared/config.native.yml
  info "已删除原生模式本地运行配置"
else
  info "原生模式进程已停止，配置和凭据已保留"
fi
