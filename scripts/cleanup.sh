#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="cleanup"
source "${ROOT_DIR}/scripts/lib.sh"

PURGE=false

usage() {
  cat <<'EOF_USAGE'
用法：
  ./scripts/cleanup.sh          停止并移除 EasyGate 容器和网络
  ./scripts/cleanup.sh --purge  同时删除 EASYGATE_HOME 运行时目录
EOF_USAGE
}

for arg in "$@"; do
  case "$arg" in
    --purge)
      PURGE=true
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

if ! command -v docker >/dev/null 2>&1; then
  error "未找到 docker，无法清理 Compose 部署"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  error "当前 Docker 未提供 docker compose"
  exit 1
fi

info "停止并移除 EasyGate 容器和网络"
if [[ -f "$COMPOSE_FILE" && -f "$COMPOSE_ENV" ]]; then
  docker compose -p easygate -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" down --remove-orphans
else
  warn "未找到运行时 Compose 配置：${COMPOSE_FILE}，跳过 docker compose down"
fi

if [[ "$PURGE" != true ]]; then
  info "清理完成。本地配置和 tunnel 凭据已保留。"
  exit 0
fi

warn "即将删除运行时目录 ${EASYGATE_HOME}，包括本地配置、二进制和 tunnel 凭据。该操作不会删除 Cloudflare 上的 DNS 记录或 tunnel。"
confirm="${EASYGATE_CONFIRM_PURGE:-}"
if [[ -z "$confirm" ]]; then
  read -r -p "确认继续？输入 yes: " confirm
fi
if [[ "$confirm" != "yes" ]]; then
  warn "已取消彻底清理"
  exit 0
fi

if [[ -e "$EASYGATE_HOME" ]]; then
  rm -rf "$EASYGATE_HOME"
  info "已删除 ${EASYGATE_HOME}"
fi

info "彻底清理完成。Cloudflare 侧资源如需删除，请使用 cloudflared CLI 或 Cloudflare Dashboard 手动处理。"
