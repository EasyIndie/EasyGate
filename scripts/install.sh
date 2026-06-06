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

# ── PATH 自动配置 ──────────────────────────────────────────────────────

detect_rc_file() {
  # 按优先级检测：当前 SHELL 的配置文件 > 常用默认文件
  local shell_name
  shell_name="$(basename "${SHELL:-}" 2>/dev/null || true)"
  case "$shell_name" in
    zsh)
      # macOS 用户默认 zsh，～/.zshrc 是标准配置文件
      printf '%s/.zshrc' "$HOME"
      return
      ;;
    bash)
      # Linux 用 ～/.bashrc，macOS 用 ～/.bash_profile
      case "$(uname -s)" in
        Darwin)
          if [[ -f "$HOME/.bash_profile" ]]; then
            printf '%s/.bash_profile' "$HOME"
          else
            printf '%s/.bashrc' "$HOME"
          fi
          ;;
        *) printf '%s/.bashrc' "$HOME" ;;
      esac
      return
      ;;
  esac
  # 未知 SHELL —— 探测存在的常用文件
  for f in .zshrc .bashrc .bash_profile .profile; do
    if [[ -f "$HOME/$f" ]]; then
      printf '%s/%s' "$HOME" "$f"
      return
    fi
  done
  # 退回到 .profile（几乎所有 POSIX shell 都加载）
  printf '%s/.profile' "$HOME"
}

add_to_path() {
  local rc_file="$1"
  # 路径中可能含空格（如 macOS 的 Application Support），
  # 路径部分用单引号防止 shell 解释，$PATH 保留双引号。
  local export_line="export PATH='${INSTALL_DIR}':\"\$PATH\""

  # 如果已经配置过则跳过
  if grep -qs "${INSTALL_DIR}" "$rc_file" 2>/dev/null; then
    return 0
  fi

  printf '\n# EasyGate CLI\n%s\n' "$export_line" >> "$rc_file"
  info "已将 CLI 目录写入 ${rc_file}"
}

# ── 主流程 ─────────────────────────────────────────────────────────────

REPO="${EASYGATE_REPO:-EasyIndie/EasyGate}"
REF="${EASYGATE_REF:-main}"
SOURCE_URL="${EASYGATE_CLI_URL:-https://raw.githubusercontent.com/${REPO}/${REF}/scripts/easygate}"

# CLI 校验和 —— 默认 __SKIP__ 跳过校验（开发/CI 场景）。
# Release 工作流用 sed 替换整行，嵌入真实校验和：
#   s/EASYGATE_CLI_CHECKSUM=.*/EASYGATE_CLI_CHECKSUM="<sha256>"/
EASYGATE_CLI_CHECKSUM="${EASYGATE_CLI_CHECKSUM:-__SKIP__}"

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

# 校验 CLI 文件（仅当校验和不为 __SKIP__ 时）
if [[ "$EASYGATE_CLI_CHECKSUM" != "__SKIP__" ]]; then
  require_command shasum
  info "验证 CLI 校验和"
  actual="$(shasum -a 256 "$TARGET" 2>/dev/null | awk '{print $1}')"
  if [[ "$actual" != "$EASYGATE_CLI_CHECKSUM" ]]; then
    error "easygate CLI 校验和不匹配！"
    error "期望：${EASYGATE_CLI_CHECKSUM}"
    error "实际：${actual}"
    exit 1
  fi
  info "校验通过"
fi

chmod +x "$TARGET"

printf '\n'
info "✅ 安装完成"
printf '   CLI 路径：\033[1m%s\033[0m\n' "$TARGET"
printf '   运行时目录：%s\n' "$EASYGATE_HOME"
printf '\n'

# 自动写入 shell 配置文件
case "$(uname -s)" in
  Darwin|Linux)
    rc_file="$(detect_rc_file)"
    add_to_path "$rc_file"
    export PATH="${INSTALL_DIR}:$PATH"
    info "当前会话已生效，新终端窗口自动生效"
    ;;
esac

printf '\n'

if [[ $# -gt 0 ]]; then
  exec "$TARGET" "$@"
fi

printf '   直接部署：\n'
printf '   \033[1measygate deploy --domain example.com\033[0m\n'
printf '   \033[2m（已加入 PATH，可直接使用 easygate 命令）\033[0m\n'
