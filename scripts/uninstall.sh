#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYGATE_LIB_TAG="uninstall"
source "${ROOT_DIR}/scripts/lib.sh"

cleanup_shell_config() {
  local rc_file install_dir

  # 检测 shell 配置文件（与 install.sh 的 detect_rc_file 保持一致）
  local shell_name
  shell_name="$(basename "${SHELL:-}" 2>/dev/null || true)"
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash)
      case "$(uname -s)" in
        Darwin) rc_file="${HOME}/.bash_profile"; [[ -f "$rc_file" ]] || rc_file="${HOME}/.bashrc" ;;
        *)      rc_file="${HOME}/.bashrc" ;;
      esac
      ;;
    *)
      for f in .zshrc .bashrc .bash_profile .profile; do
        if [[ -f "$HOME/$f" ]]; then
          rc_file="$HOME/$f"
          break
        fi
      done
      rc_file="${rc_file:-$HOME/.profile}"
      ;;
  esac

  install_dir="${EASYGATE_HOME}/bin"

  if [[ ! -f "$rc_file" ]]; then
    return
  fi

  # 删除 EasyGate CLI 的 PATH 配置行（含注释头和 export 行）
  if grep -qs "${install_dir}" "$rc_file" 2>/dev/null; then
    # 删除 "# EasyGate CLI" 注释行以及紧随的 export 行
    if [[ "$(uname -s)" == "Darwin" ]]; then
      sed -i '' '/^# EasyGate CLI$/,/^export PATH=.*easygate.*bin.*$/d' "$rc_file"
      sed -i '' '/export PATH=.*easygate.*bin.*PATH/d' "$rc_file"
    else
      sed -i '/^# EasyGate CLI$/,/^export PATH=.*easygate.*bin.*$/d' "$rc_file"
      sed -i '/export PATH=.*easygate.*bin.*PATH/d' "$rc_file"
    fi
    info "已从 ${rc_file} 移除 EasyGate PATH 配置"
  fi
}

info "停止 EasyGate 服务"
"${ROOT_DIR}/scripts/cleanup.sh" "$@"

TARGET="${EASYGATE_HOME}/bin/easygate"
if [[ -f "$TARGET" ]]; then
  rm -f "$TARGET"
  info "已删除 CLI：${TARGET}"
else
  info "CLI 未安装或已删除：${TARGET}"
fi

cleanup_shell_config

info "卸载完成"
