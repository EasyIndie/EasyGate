#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="uninstall"
source "${ROOT_DIR}/scripts/lib.sh"

info "停止 EasyGate 服务"
"${ROOT_DIR}/scripts/cleanup.sh" "$@"

TARGET="${EASYGATE_HOME}/bin/easygate"
if [[ -f "$TARGET" ]]; then
  rm -f "$TARGET"
  info "已删除 CLI：${TARGET}"
else
  info "CLI 未安装或已删除：${TARGET}"
fi

info "卸载完成"
