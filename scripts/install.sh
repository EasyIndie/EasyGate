#!/usr/bin/env bash
set -euo pipefail

REPO="${EASYGATE_REPO:-EasyIndie/EasyGate}"
REF="${EASYGATE_REF:-main}"
SOURCE_URL="${EASYGATE_CLI_URL:-https://raw.githubusercontent.com/${REPO}/${REF}/scripts/easygate}"

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
INSTALL_DIR="${EASYGATE_HOME}/bin"
TARGET="${INSTALL_DIR}/easygate"

mkdir -p "$INSTALL_DIR"

if [[ -n "${EASYGATE_LOCAL_CLI:-}" ]]; then
  cp "$EASYGATE_LOCAL_CLI" "$TARGET"
else
  command -v curl >/dev/null 2>&1 || { printf '[install] 缺少 curl\n' >&2; exit 1; }
  curl -fsSL "$SOURCE_URL" -o "$TARGET"
fi

chmod +x "$TARGET"

printf '[install] easygate 已安装到：%s\n' "$TARGET"
printf '[install] 运行时目录：%s\n' "$EASYGATE_HOME"
printf '[install] 可选：将 %s 加入 PATH\n' "$INSTALL_DIR"

if [[ $# -gt 0 ]]; then
  exec "$TARGET" "$@"
fi

printf '[install] 部署示例：%s deploy --domain example.com\n' "$TARGET"
