#!/usr/bin/env bash
# EasyGate shared utility library.
# Source this file from other scripts after optionally setting:
#   EASYGATE_LIB_TAG   – log prefix (default: easygate)
#   EASYGATE_HOME      – runtime directory (auto-detected if unset)

# ── Logging ───────────────────────────────────────────────────────────

info() {
  printf '\033[1;34m[%s]\033[0m %s\n' "${EASYGATE_LIB_TAG:-easygate}" "$1"
}

warn() {
  printf '\033[1;33m[%s]\033[0m %s\n' "${EASYGATE_LIB_TAG:-easygate}" "$1"
}

error() {
  printf '\033[1;31m[%s]\033[0m %s\n' "${EASYGATE_LIB_TAG:-easygate}" "$1" >&2
}

# ── EASYGATE_HOME resolution ──────────────────────────────────────────

default_easygate_home() {
  if [[ -n "${EASYGATE_HOME:-}" ]]; then
    printf '%s' "$EASYGATE_HOME"
    return
  fi

  printf '%s' "${HOME}/.easygate"
}

# Resolve once and export so all sourced functions see the same value.
EASYGATE_HOME="${EASYGATE_HOME:-$(default_easygate_home)}"
export EASYGATE_HOME
export PATH="${EASYGATE_HOME}/bin:$PATH"

CLOUDFLARED_HOME="${EASYGATE_CLOUDFLARED_HOME:-${HOME}/.cloudflared}"
COMPOSE_DIR="${EASYGATE_HOME}/compose"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
COMPOSE_ENV="${COMPOSE_DIR}/.env"

# ── Dependency checks ─────────────────────────────────────────────────

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "缺少命令：$1"
    return 1
  fi
}

# ── User input ────────────────────────────────────────────────────────

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "${prompt} [${default}]: " value
  printf '%s' "${value:-$default}"
}

# ── Python discovery ──────────────────────────────────────────────────

find_python() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return
  fi
  return 1
}

# ── Cloudflare credential helpers ─────────────────────────────────────

find_latest_credentials() {
  local search_dir="$1"
  find "$search_dir" -maxdepth 1 -type f -name "*.json" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -n 1
}

# ── Binary installation ───────────────────────────────────────────────

# install_cloudflared <should_install>
#   should_install: true  → download if missing (default)
#                    false → error if missing
install_cloudflared() {
  local should_install="${1:-true}"
  local install_dir="${EASYGATE_HOME}/bin"

  if [[ -x "${install_dir}/cloudflared" ]]; then
    info "已找到运行时 cloudflared：${install_dir}/cloudflared"
    return
  fi

  if command -v cloudflared >/dev/null 2>&1; then
    if [[ "$should_install" != true ]]; then
      info "已找到 cloudflared：$(command -v cloudflared)"
      return
    fi
    info "将安装运行时 cloudflared，避免系统旧版本产生部署警告"
  fi

  if [[ "$should_install" != true ]]; then
    error "缺少命令：cloudflared"
    exit 1
  fi

  require_command curl || exit 1

  local os arch asset url tmp_dir downloaded extracted
  os="$(uname -s)"
  arch="$(uname -m)"
  tmp_dir="${EASYGATE_HOME}/tmp/cloudflared"

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    armv7l|armv6l) arch="arm" ;;
    i386|i686) arch="386" ;;
    *) error "暂不支持的 CPU 架构：${arch}"; exit 1 ;;
  esac

  mkdir -p "$install_dir" "$tmp_dir"

  case "$os" in
    Darwin)
      asset="cloudflared-darwin-${arch}.tgz"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
      downloaded="${tmp_dir}/${asset}"
      info "下载 cloudflared：${asset}"
      curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$downloaded" "$url"
      rm -rf "${tmp_dir}/extract"
      mkdir -p "${tmp_dir}/extract"
      tar -xzf "$downloaded" -C "${tmp_dir}/extract"
      extracted="$(find "${tmp_dir}/extract" -type f -name cloudflared | head -n 1)"
      [[ -n "$extracted" ]] || { error "未能从 ${asset} 中找到 cloudflared"; exit 1; }
      cp "$extracted" "${install_dir}/cloudflared"
      ;;
    Linux)
      asset="cloudflared-linux-${arch}"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
      info "下载 cloudflared：${asset}"
      curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o "${install_dir}/cloudflared" "$url"
      ;;
    *) error "仅支持 macOS/Linux 自动安装 cloudflared"; exit 1 ;;
  esac

  chmod +x "${install_dir}/cloudflared"
  export PATH="${install_dir}:$PATH"
  cloudflared --version >/dev/null
  info "cloudflared 已安装到 ${install_dir}/cloudflared"
}

# install_traefik <should_install> [version]
#   should_install: true → download if missing, false → error if missing
#   version:         defaults to EASYGATE_TRAEFIK_VERSION or 3.1.7
install_traefik() {
  local should_install="${1:-true}"
  local traefik_version="${2:-${EASYGATE_TRAEFIK_VERSION:-3.1.7}}"

  if command -v traefik >/dev/null 2>&1; then
    info "已找到 traefik：$(command -v traefik)"
    return
  fi

  if [[ "$should_install" != true ]]; then
    error "缺少命令：traefik"
    exit 1
  fi

  require_command curl || exit 1
  require_command tar || exit 1

  local os arch asset url install_dir tmp_dir downloaded extracted
  os="$(uname -s)"
  arch="$(uname -m)"
  install_dir="${EASYGATE_HOME}/bin"
  tmp_dir="${EASYGATE_HOME}/tmp/traefik"

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    armv7l|armv6l) arch="armv7" ;;
    i386|i686) arch="386" ;;
    *) error "暂不支持的 CPU 架构：${arch}"; exit 1 ;;
  esac

  case "$os" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) error "仅支持 macOS/Linux 自动安装 Traefik"; exit 1 ;;
  esac

  mkdir -p "$install_dir" "$tmp_dir"
  asset="traefik_v${traefik_version}_${os}_${arch}.tar.gz"
  url="https://github.com/traefik/traefik/releases/download/v${traefik_version}/${asset}"
  checksums_url="https://github.com/traefik/traefik/releases/download/v${traefik_version}/traefik_v${traefik_version}_checksums.txt"
  downloaded="${tmp_dir}/${asset}"
  checksums_file="${tmp_dir}/traefik_checksums.txt"

  info "下载 Traefik：${asset}"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$downloaded" "$url"

  # Verify SHA256 checksum.
  info "验证 Traefik SHA256 校验和"
  if curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$checksums_file" "$checksums_url"; then
    local expected actual
    expected="$(grep "${asset}" "$checksums_file" | awk '{print $1}' || true)"
    actual="$(shasum -a 256 "$downloaded" 2>/dev/null | awk '{print $1}' || true)"
    if [[ -z "$expected" ]]; then
      warn "无法从 checksums 文件中找到 ${asset} 的校验和，跳过验证"
    elif [[ "$expected" != "$actual" ]]; then
      error "Traefik SHA256 校验和不匹配"
      error "期望：${expected}"
      error "实际：${actual}"
      exit 1
    else
      info "SHA256 校验通过"
    fi
  else
    warn "无法下载 Traefik checksums 文件，跳过校验和验证"
  fi

  rm -rf "${tmp_dir}/extract"
  mkdir -p "${tmp_dir}/extract"
  tar -xzf "$downloaded" -C "${tmp_dir}/extract"
  extracted="$(find "${tmp_dir}/extract" -type f -name traefik | head -n 1)"
  [[ -n "$extracted" ]] || { error "未能从 ${asset} 中找到 traefik"; exit 1; }
  cp "$extracted" "${install_dir}/traefik"
  chmod +x "${install_dir}/traefik"
  export PATH="${install_dir}:$PATH"
  traefik version >/dev/null
  info "Traefik 已安装到 ${install_dir}/traefik"
}

# ── Tunnel credentials ────────────────────────────────────────────────

# prepare_tunnel_credentials <tunnel_name>
prepare_tunnel_credentials() {
  local tunnel_name="${1:-easygate-home}"
  local target="${EASYGATE_HOME}/cloudflared/${tunnel_name}.json"
  local before_credentials after_credentials credentials_source credentials_tmp

  if [[ -f "$target" ]]; then
    info "复用已有 tunnel 凭据：${target}"
    return
  fi

  before_credentials="$(find_latest_credentials "${CLOUDFLARED_HOME}" || true)"

  info "创建 Cloudflare Tunnel：${tunnel_name}"
  if ! cloudflared tunnel create "$tunnel_name"; then
    warn "创建 tunnel 失败。若 tunnel 已存在，将尝试复用本地最新凭据文件。"
  fi

  after_credentials="$(find_latest_credentials "${CLOUDFLARED_HOME}" || true)"
  credentials_source="${after_credentials:-$before_credentials}"

  if [[ -z "$credentials_source" || ! -f "$credentials_source" ]]; then
    error "未找到 tunnel 凭据 JSON。请确认 cloudflared tunnel create 是否成功，或将已有凭据保存为 ${target}。"
    exit 1
  fi

  credentials_tmp="$(mktemp "${EASYGATE_HOME}/cloudflared/${tunnel_name}.json.XXXXXX")"
  cp "$credentials_source" "$credentials_tmp"
  chmod 600 "$credentials_tmp"
  mv -f "$credentials_tmp" "$target"
  info "已复制 tunnel 凭据到 ${target}"
}

# ── Process management (native mode) ──────────────────────────────────

native_pid_active() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

# ── PID file advisory lock (mkdir-based, portable) ───────────────────

# Acquire an advisory lock for a PID file.  Returns 0 on success.
pid_lock_acquire() {
  local name="$1"
  local lock_dir="${EASYGATE_HOME}/run/.${name}.lock"
  mkdir "$lock_dir" 2>/dev/null
}

# Release an advisory lock.
pid_lock_release() {
  local name="$1"
  local lock_dir="${EASYGATE_HOME}/run/.${name}.lock"
  rmdir "$lock_dir" 2>/dev/null || true
}

stop_pid_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      kill -0 "$pid" >/dev/null 2>&1 || break
      sleep 0.2
    done
  fi
  rm -f "$file"
}

start_process() {
  local name="$1"
  shift
  local pid_file="${EASYGATE_HOME}/run/${name}.pid"
  local log_file="${EASYGATE_HOME}/logs/${name}.log"

  # Acquire advisory lock to prevent concurrent PID file corruption.
  if ! pid_lock_acquire "$name"; then
    error "无法获取 ${name} 的 PID 锁，可能有另一个 easygate 实例正在运行"
    return 1
  fi

  stop_pid_file "$pid_file"
  info "启动 ${name}"
  nohup "$@" >"$log_file" 2>&1 &
  printf '%s\n' "$!" > "$pid_file"

  pid_lock_release "$name"
}

# ── Compose deployment detection ──────────────────────────────────────

compose_deployment_active() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  [[ -f "$COMPOSE_FILE" && -f "$COMPOSE_ENV" ]] || return 1

  docker compose -p easygate -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" ps --services --status running 2>/dev/null \
    | grep -Eq '^(traefik|cloudflared)$'
}

# ── Compose helper ────────────────────────────────────────────────────

compose() {
  if [[ ! -f "$COMPOSE_FILE" || ! -f "$COMPOSE_ENV" ]]; then
    error "未找到运行时 Compose 配置，请先执行部署"
    error "期望文件：${COMPOSE_FILE}"
    exit 1
  fi
  docker compose -p easygate -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" "$@"
}

# ── Input validation ──────────────────────────────────────────────────

# Validate a port number (1-65535).  Returns 0 if valid, 1 otherwise.
validate_port() {
  local port="$1"
  local label="${2:-port}"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    error "${label} 必须是数字：${port}"
    return 1
  fi
  if (( port < 1 || port > 65535 )); then
    error "${label} 超出范围 (1-65535)：${port}"
    return 1
  fi
  return 0
}

# ── System service registration (for reboot persistence) ────────────

# Register a systemd user service (Linux)
register_systemd() {
  local name="$1"       # e.g. "native-traefik"
  local bin_path="$2"   # absolute path to binary
  local args="$3"       # command arguments as a single string
  local description="${4:-EasyGate ${name}}"
  local after="${5:-network.target}"
  local unit_dir="${HOME}/.config/systemd/user"
  local unit_file="${unit_dir}/${name}.service"

  command -v systemctl >/dev/null 2>&1 || return 0

  mkdir -p "$unit_dir"
  # 先注销已有服务确保幂等
  systemctl --user disable "${name}.service" >/dev/null 2>&1 || true
  rm -f "$unit_file"

  cat > "$unit_file" <<EOF_SERVICE
[Unit]
Description=${description}
After=${after}

[Service]
Type=simple
ExecStart=${bin_path} ${args}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF_SERVICE

  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now "${name}.service" >/dev/null 2>&1 || true
}

# Unregister a systemd user service (Linux)
unregister_systemd() {
  local name="$1"
  local unit_file="${HOME}/.config/systemd/user/${name}.service"

  command -v systemctl >/dev/null 2>&1 || return 0

  systemctl --user disable "${name}.service" >/dev/null 2>&1 || true
  systemctl --user stop "${name}.service" >/dev/null 2>&1 || true
  rm -f "$unit_file"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Register a launchd user agent (macOS)
register_launchd() {
  local name="$1"
  local bin_path="$2"
  local args="$3"
  local plist="${HOME}/Library/LaunchAgents/com.easygate.${name}.plist"
  local log_file="${EASYGATE_HOME}/logs/${name}.log"

  command -v launchctl >/dev/null 2>&1 || return 0

  mkdir -p "${HOME}/Library/LaunchAgents"
  # 先注销避免重复
  launchctl unload "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"

  cat > "$plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.easygate.${name}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${bin_path}</string>
EOF_PLIST
  # 参数逐行写入 array
  for _arg in ${args}; do
    printf '        <string>%s</string>\n' "$_arg" >> "$plist"
  done
  cat >> "$plist" <<EOF_PLIST
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${log_file}</string>
    <key>StandardErrorPath</key>
    <string>${log_file}</string>
</dict>
</plist>
EOF_PLIST

  launchctl load "$plist" >/dev/null 2>&1 || true
}

# Unregister a launchd user agent (macOS)
unregister_launchd() {
  local name="$1"
  local plist="${HOME}/Library/LaunchAgents/com.easygate.${name}.plist"

  command -v launchctl >/dev/null 2>&1 || return 0

  launchctl unload "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
}

# ── Port conflict detection ──────────────────────────────────────────

# Check if a TCP port is already in use on localhost.
# Returns 0 if the port is free, 1 if occupied.
check_port_available() {
  local port="$1"
  local label="${2:-port}"
  if command -v lsof >/dev/null 2>&1; then
    if lsof -i "tcp:${port}" -P -n 2>/dev/null | grep -q LISTEN; then
      local proc
      proc="$(lsof -i "tcp:${port}" -P -n 2>/dev/null | awk 'NR>1{print $1; exit}')"
      error "${label} ${port} 已被占用（${proc}），请先停止该进程再部署"
      return 1
    fi
  elif command -v ss >/dev/null 2>&1; then
    if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q LISTEN; then
      error "${label} ${port} 已被占用，请先停止该进程再部署"
      return 1
    fi
  fi
  return 0
}

# Validate a domain name (basic sanity check).
validate_domain() {
  local domain="$1"
  # Must contain at least one dot, no spaces, and not be example.com.
  if [[ "$domain" == "example.com" ]]; then
    error "请使用真实域名，不要使用 example.com"
    return 1
  fi
  if [[ ! "$domain" =~ \. ]]; then
    error "域名格式不正确：${domain}（缺少顶级域）"
    return 1
  fi
  if [[ "$domain" =~ [[:space:]] ]]; then
    error "域名不能包含空格：${domain}"
    return 1
  fi
  return 0
}

# Validate a tunnel name (alphanumeric + hyphens only).
validate_tunnel_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
    error "Tunnel 名称格式不正确（仅支持字母、数字和连字符）：${name}"
    return 1
  fi
  return 0
}
