#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PURGE=false

info() {
  printf '\033[1;34m[cleanup]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m[cleanup]\033[0m %s\n' "$1"
}

error() {
  printf '\033[1;31m[cleanup]\033[0m %s\n' "$1" >&2
}

usage() {
  cat <<'EOF_USAGE'
用法：
  ./scripts/cleanup.sh          停止并移除 EasyGate 容器和网络
  ./scripts/cleanup.sh --purge  同时删除本地生成的 .env、cloudflared/config.yml 和 tunnel 凭据
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
docker compose down --remove-orphans

if [[ "$PURGE" != true ]]; then
  info "清理完成。本地配置和 tunnel 凭据已保留。"
  exit 0
fi

warn "即将删除本地生成配置和 tunnel 凭据。该操作不会删除 Cloudflare 上的 DNS 记录或 tunnel。"
read -r -p "确认继续？输入 yes: " confirm
if [[ "$confirm" != "yes" ]]; then
  warn "已取消彻底清理"
  exit 0
fi

paths=(
  ".env"
  "cloudflared/config.yml"
)

for path in "${paths[@]}"; do
  if [[ -e "$path" ]]; then
    rm -f "$path"
    info "已删除 $path"
  fi
done

if compgen -G "cloudflared/*.json" >/dev/null; then
  rm -f cloudflared/*.json
  info "已删除 cloudflared/*.json"
fi

info "彻底清理完成。Cloudflare 侧资源如需删除，请使用 cloudflared CLI 或 Cloudflare Dashboard 手动处理。"
