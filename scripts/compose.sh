#!/usr/bin/env bash
set -euo pipefail

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
COMPOSE_FILE="${EASYGATE_HOME}/compose/docker-compose.yml"
COMPOSE_ENV="${EASYGATE_HOME}/compose/.env"

if [[ ! -f "$COMPOSE_FILE" || ! -f "$COMPOSE_ENV" ]]; then
  printf '[compose] 未找到运行时 Compose 配置，请先执行 ./scripts/deploy.sh\n' >&2
  printf '[compose] 期望文件：%s\n' "$COMPOSE_FILE" >&2
  exit 1
fi

exec docker compose -p easygate -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" "$@"
