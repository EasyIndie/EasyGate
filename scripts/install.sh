#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="install"
source "${ROOT_DIR}/scripts/lib.sh"

REPO="${EASYGATE_REPO:-EasyIndie/EasyGate}"
REF="${EASYGATE_REF:-main}"
SOURCE_URL="${EASYGATE_CLI_URL:-https://raw.githubusercontent.com/${REPO}/${REF}/scripts/easygate}"

INSTALL_DIR="${EASYGATE_HOME}/bin"
TARGET="${INSTALL_DIR}/easygate"

mkdir -p "$INSTALL_DIR"

if [[ -n "${EASYGATE_LOCAL_CLI:-}" ]]; then
  cp "$EASYGATE_LOCAL_CLI" "$TARGET"
else
  require_command curl || exit 1
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 "$SOURCE_URL" -o "$TARGET"
fi

chmod +x "$TARGET"

info "easygate 已安装到：${TARGET}"
info "运行时目录：${EASYGATE_HOME}"
info "可选：将 ${INSTALL_DIR} 加入 PATH"

if [[ $# -gt 0 ]]; then
  exec "$TARGET" "$@"
fi

info "部署示例：${TARGET} deploy --domain example.com"
