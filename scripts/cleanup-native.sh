#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="cleanup-native"
source "${ROOT_DIR}/scripts/lib.sh"

PURGE=false

usage() {
  cat <<'EOF_USAGE'
用法：
  ./scripts/cleanup-native.sh [--purge]

默认只停止原生模式进程，保留配置、日志和 tunnel 凭据。
--purge 会删除 EASYGATE_HOME 下的 native 配置、run、logs 和 cloudflared/config.native.yml。
EOF_USAGE
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

# 注销系统服务（如有已注册的）
case "$(uname -s)" in
  Linux)
    unregister_systemd "native-traefik" || true
    unregister_systemd "native-cloudflared" || true
    ;;
  Darwin)
    unregister_launchd "native-traefik" || true
    unregister_launchd "native-cloudflared" || true
    ;;
esac

for pid_file in \
  "${EASYGATE_HOME}/run/native-cloudflared.pid" \
  "${EASYGATE_HOME}/run/native-traefik.pid" \
  "${EASYGATE_HOME}/run/native-demo-api.pid" \
  "${EASYGATE_HOME}/run/native-demo-test-api.pid"; do
  stop_pid_file "$pid_file"
done

if [[ "$PURGE" == true ]]; then
  rm -rf "${EASYGATE_HOME}/native" "${EASYGATE_HOME}/run" "${EASYGATE_HOME}/logs"
  rm -f "${EASYGATE_HOME}/cloudflared/config.native.yml"
  info "已删除原生模式本地运行配置"
else
  info "原生模式进程已停止，配置和凭据已保留"
fi
