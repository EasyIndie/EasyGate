#!/usr/bin/env bash
set -euo pipefail

# NOTE: This script must remain self-contained — it runs via
#   curl -fsSL ...install.sh | bash
# and has no filesystem context.  Do not source other files.

info()  { printf '\033[1;34m[install]\033[0m %s\n' "$1"; }
error() { printf '\033[1;31m[install]\033[0m %s\n' "$1" >&2; }

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "缺少命令：$1"
    exit 1
  fi
}

default_easygate_home() {
  if [[ -n "${EASYGATE_HOME:-}" ]]; then
    printf '%s' "$EASYGATE_HOME"
    return
  fi
  case "$(uname -s)" in
    Darwin) printf '%s' "${HOME}/Library/Application Support/EasyGate" ;;
    *)      printf '%s' "${XDG_DATA_HOME:-${HOME}/.local/share}/easygate" ;;
  esac
}

REPO="${EASYGATE_REPO:-EasyIndie/EasyGate}"
REF="${EASYGATE_REF:-main}"
SOURCE_URL="${EASYGATE_CLI_URL:-https://raw.githubusercontent.com/${REPO}/${REF}/scripts/easygate}"

EASYGATE_HOME="$(default_easygate_home)"
INSTALL_DIR="${EASYGATE_HOME}/bin"
TARGET="${INSTALL_DIR}/easygate"

mkdir -p "$INSTALL_DIR"

if [[ -n "${EASYGATE_LOCAL_CLI:-}" ]]; then
  info "从本地复制 CLI：${EASYGATE_LOCAL_CLI}"
  cp "$EASYGATE_LOCAL_CLI" "$TARGET"
else
  require_command curl
  info "下载 CLI：${SOURCE_URL}"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 "$SOURCE_URL" -o "$TARGET"
fi

chmod +x "$TARGET"

printf '\n'
info "✅ 安装完成"
printf '   CLI 路径：\033[1m%s\033[0m\n' "$TARGET"
printf '   运行时目录：%s\n' "$EASYGATE_HOME"
printf '\n'
printf '   添加到 PATH 以便直接使用 easygate 命令：\n'
case "$(uname -s)" in
  Darwin|Linux)
    printf '   \033[2mexport PATH="%s:$PATH"\033[0m\n' "$INSTALL_DIR"
    printf '   或 \033[2msource ~/.bashrc\033[0m/\033[2m~/.zshrc\033[0m 后永久生效：\n'
    printf '   \033[2m  echo '\''export PATH="%s:$PATH"'\'' >> ~/.bashrc\033[0m\n' "$INSTALL_DIR"
    ;;
esac
printf '\n'

if [[ $# -gt 0 ]]; then
  exec "$TARGET" "$@"
fi

printf '   直接部署：\n'
printf '   \033[1m%s deploy --domain example.com\033[0m\n' "$TARGET"
printf '   或先加入 PATH 后：\n'
printf '   \033[1measygate deploy --domain example.com\033[0m\n'
