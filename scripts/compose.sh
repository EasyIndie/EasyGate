#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="compose"
source "${ROOT_DIR}/scripts/lib.sh"

if [[ ! -f "$COMPOSE_FILE" || ! -f "$COMPOSE_ENV" ]]; then
  printf '[compose] 未找到运行时 Compose 配置，请先执行 ./scripts/deploy.sh\n' >&2
  printf '[compose] 期望文件：%s\n' "$COMPOSE_FILE" >&2
  exit 1
fi

exec docker compose -p easygate -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" "$@"
