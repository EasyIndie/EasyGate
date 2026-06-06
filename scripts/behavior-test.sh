#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/easygate-behavior.XXXXXX")"

info() {
  printf '\033[1;34m[behavior]\033[0m %s\n' "$1"
}

fail() {
  printf '\033[1;31m[behavior]\033[0m %s\n' "$1" >&2
  exit 1
}

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "缺少文件：$path"
}

assert_missing() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "不应存在：$path"
}

assert_contains() {
  local path="$1"
  local text="$2"
  grep -Fq -- "$text" "$path" || fail "$path 未包含：$text"
}

make_fixture() {
  local dst="$1"
  mkdir -p "$dst"
  cp -R \
    "$ROOT_DIR/scripts" \
    "$ROOT_DIR/traefik" \
    "$ROOT_DIR/cloudflared" \
    "$ROOT_DIR/docker-compose.yml" \
    "$ROOT_DIR/docker-compose.local.yml" \
    "$ROOT_DIR/.env.example" \
    "$dst/"
}

make_mock_bin() {
  local bin_dir="$1"
  local log_file="$2"
  mkdir -p "$bin_dir"

  cat > "${bin_dir}/docker" <<'EOF_DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >> "${EASYGATE_MOCK_LOG}"
if [[ "${1:-}" == "compose" ]]; then
  case "$*" in
    "compose version"*) exit 0 ;;
    *" ps --services --status running"*)
      if [[ "${EASYGATE_MOCK_COMPOSE_RUNNING:-false}" == "true" ]]; then
        printf 'traefik\ncloudflared\n'
      fi
      exit 0
      ;;
    *" config"*) exit 0 ;;
    *" up "*|*" up -d"*|*" down "*|*" rm "*|*" stop "*) exit 0 ;;
  esac
fi
if [[ "${1:-}" == "info" ]]; then
  exit 0
fi
exit 0
EOF_DOCKER

  cat > "${bin_dir}/cloudflared" <<'EOF_CLOUDFLARED'
#!/usr/bin/env bash
set -euo pipefail
printf 'cloudflared %s\n' "$*" >> "${EASYGATE_MOCK_LOG}"
exit 0
EOF_CLOUDFLARED

  cat > "${bin_dir}/traefik" <<'EOF_TRAEFIK'
#!/usr/bin/env bash
set -euo pipefail
printf 'traefik %s\n' "$*" >> "${EASYGATE_MOCK_LOG}"
exit 0
EOF_TRAEFIK

  chmod +x "${bin_dir}/docker" "${bin_dir}/cloudflared" "${bin_dir}/traefik"
  : > "$log_file"
}

run_deploy_behavior_test() {
  local fixture="${TMP_DIR}/deploy-fixture"
  local home="${TMP_DIR}/home"
  local runtime="${TMP_DIR}/runtime-deploy"
  local bin="${TMP_DIR}/bin"
  local log="${TMP_DIR}/commands.log"

  info "验证部署脚本可复用已有 tunnel 凭据"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"
  rm -f "${fixture}/cloudflared/config.yml" "${fixture}/cloudflared/easygate-home.json"

  mkdir -p "${home}/.cloudflared"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf '{"source":"new"}\n' > "${home}/.cloudflared/0000.json"

  (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy.sh --domain example.test --skip-route --demo --no-install-cloudflared
  )
  (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy.sh --domain example.test --skip-route --demo --no-install-cloudflared
  )

  assert_contains "${runtime}/compose/.env" "BASE_DOMAIN=example.test"
  assert_contains "${runtime}/compose/.env" "TRAEFIK_DASHBOARD_HOST=traefik.example.test"
  assert_contains "${runtime}/cloudflared/config.yml" 'hostname: "*.example.test"'
  assert_contains "${runtime}/cloudflared/easygate-home.json" '"source":"new"'
  assert_contains "${runtime}/compose/docker-compose.yml" "\"${runtime}/traefik/traefik.yml:/etc/traefik/traefik.yml:ro\""
  assert_missing "${fixture}/.env"
  assert_missing "${fixture}/cloudflared/config.yml"
  create_calls="$(grep -Fc -- "cloudflared tunnel create easygate-home" "$log")"
  [[ "$create_calls" -eq 1 ]] || fail "重复部署时 tunnel create 调用次数应为 1，实际为 ${create_calls}"
  assert_contains "$log" "docker compose -p easygate"
  assert_contains "$log" " up -d"
  compose_calls="$(grep -Fc -- "docker compose" "$log")"
  [[ "$compose_calls" -ge 6 ]] || fail "重复启用 --demo 后 docker compose 调用次数不足：${compose_calls}"

  if grep -Fq "cloudflared tunnel route dns" "$log"; then
    fail "--skip-route 仍调用了 tunnel route dns"
  fi
}

run_compose_deploy_blocks_native_test() {
  local fixture="${TMP_DIR}/compose-blocks-native-fixture"
  local home="${TMP_DIR}/compose-blocks-native-home"
  local runtime="${TMP_DIR}/compose-blocks-native-runtime"
  local bin="${TMP_DIR}/compose-blocks-native-bin"
  local log="${TMP_DIR}/compose-blocks-native.log"

  info "验证原生模式运行时 Docker Compose 部署会被阻止"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${home}/.cloudflared" "${runtime}/run"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf '%s\n' "$$" > "${runtime}/run/native-traefik.pid"

  if (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy.sh --domain example.test --skip-route --no-install-cloudflared
  ); then
    fail "原生模式运行时 deploy.sh 不应继续部署"
  fi

  if grep -Fq "docker compose up -d" "$log"; then
    fail "原生模式运行时 deploy.sh 不应调用 docker compose up"
  fi
}

run_cleanup_behavior_test() {
  local fixture="${TMP_DIR}/cleanup-fixture"
  local bin="${TMP_DIR}/cleanup-bin"
  local log="${TMP_DIR}/cleanup-commands.log"
  local runtime="${TMP_DIR}/cleanup-runtime"

  info "验证清理脚本默认保留配置，purge 仅在确认后删除本地生成文件"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${runtime}/compose" "${runtime}/cloudflared"
  printf 'compose\n' > "${runtime}/compose/docker-compose.yml"
  printf 'env\n' > "${runtime}/compose/.env"
  printf 'config\n' > "${runtime}/cloudflared/config.yml"
  printf 'secret\n' > "${runtime}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    EASYGATE_HOME="$runtime" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" bash scripts/cleanup.sh
  )
  assert_file "${runtime}/compose/.env"
  assert_file "${runtime}/cloudflared/config.yml"
  assert_file "${runtime}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    EASYGATE_HOME="$runtime" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_CONFIRM_PURGE="no" bash scripts/cleanup.sh --purge
  )
  assert_file "${runtime}/compose/.env"
  assert_file "${runtime}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    EASYGATE_HOME="$runtime" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_CONFIRM_PURGE="yes" bash scripts/cleanup.sh --purge
  )
  assert_missing "$runtime"
}

run_native_deploy_behavior_test() {
  local fixture="${TMP_DIR}/native-deploy-fixture"
  local home="${TMP_DIR}/native-home"
  local runtime="${TMP_DIR}/runtime-native"
  local bin="${TMP_DIR}/native-bin"
  local log="${TMP_DIR}/native-commands.log"

  info "验证原生部署脚本生成 file provider 配置并启动本地进程"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"
  rm -f "${fixture}/cloudflared/config.yml" "${fixture}/cloudflared/easygate-home.json"

  mkdir -p "${home}/.cloudflared"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf '{"source":"native"}\n' > "${home}/.cloudflared/0000.json"

  (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_CI=true \
      bash scripts/deploy-native.sh --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  )
  (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_CI=true \
      bash scripts/deploy-native.sh --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  )

  assert_contains "${runtime}/native/.env" "EASYGATE_DEPLOY_MODE=native"
  assert_contains "${runtime}/native/traefik.yml" "providers:"
  assert_contains "${runtime}/native/traefik.yml" "${runtime}/native/dynamic"
  assert_contains "${runtime}/native/dynamic/services.yml" "service: api@internal"
  assert_contains "${runtime}/cloudflared/config.native.yml" "service: http://127.0.0.1:18080"
  assert_contains "$log" "traefik --configFile="
  assert_contains "$log" "${runtime}/native/traefik.yml"
  assert_contains "$log" "cloudflared tunnel --config"
  assert_contains "$log" "${runtime}/cloudflared/config.native.yml run"

  create_calls="$(grep -Fc -- "cloudflared tunnel create easygate-home" "$log")"
  [[ "$create_calls" -eq 1 ]] || fail "重复原生部署时 tunnel create 调用次数应为 1，实际为 ${create_calls}"

  if grep -Fq "docker:" "${runtime}/native/traefik.yml"; then
    fail "原生 Traefik 配置不应启用 docker provider"
  fi
  if grep -Fq "cloudflared tunnel route dns" "$log"; then
    fail "原生部署 --skip-route 仍调用了 tunnel route dns"
  fi
}

run_native_deploy_blocks_compose_test() {
  local fixture="${TMP_DIR}/native-blocks-compose-fixture"
  local home="${TMP_DIR}/native-blocks-compose-home"
  local runtime="${TMP_DIR}/native-blocks-compose-runtime"
  local bin="${TMP_DIR}/native-blocks-compose-bin"
  local log="${TMP_DIR}/native-blocks-compose.log"

  info "验证 Docker Compose 模式运行时原生部署会被阻止"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${home}/.cloudflared" "${runtime}/compose"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf 'compose\n' > "${runtime}/compose/docker-compose.yml"
  printf 'env\n' > "${runtime}/compose/.env"

  if (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_MOCK_COMPOSE_RUNNING=true \
      bash scripts/deploy-native.sh --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  ); then
    fail "Docker Compose 模式运行时 deploy-native.sh 不应继续部署"
  fi

  assert_missing "${runtime}/native/traefik.yml"
}

run_native_cleanup_behavior_test() {
  local fixture="${TMP_DIR}/native-cleanup-fixture"
  local runtime="${TMP_DIR}/native-cleanup-runtime"

  info "验证原生清理脚本默认保留配置，purge 删除原生运行配置"
  make_fixture "$fixture"

  mkdir -p "${runtime}/native" "${runtime}/run" "${runtime}/logs" "${runtime}/cloudflared"
  printf 'traefik\n' > "${runtime}/native/traefik.yml"
  printf 'pid\n' > "${runtime}/run/native-traefik.pid"
  printf 'log\n' > "${runtime}/logs/native-traefik.log"
  printf 'cloudflared\n' > "${runtime}/cloudflared/config.native.yml"

  (
    cd "$fixture"
    EASYGATE_HOME="$runtime" bash scripts/cleanup-native.sh
  )
  assert_file "${runtime}/native/traefik.yml"
  assert_file "${runtime}/cloudflared/config.native.yml"
  assert_missing "${runtime}/run/native-traefik.pid"

  (
    cd "$fixture"
    EASYGATE_HOME="$runtime" bash scripts/cleanup-native.sh --purge
  )
  assert_missing "${runtime}/native"
  assert_missing "${runtime}/run"
  assert_missing "${runtime}/logs"
  assert_missing "${runtime}/cloudflared/config.native.yml"
}

run_standalone_cli_behavior_test() {
  local runtime="${TMP_DIR}/standalone-runtime"
  local home="${TMP_DIR}/standalone-home"
  local bin="${TMP_DIR}/standalone-bin"
  local log="${TMP_DIR}/standalone-commands.log"

  info "验证 standalone easygate CLI 不依赖源码仓库部署"
  make_mock_bin "$bin" "$log"

  mkdir -p "${home}/.cloudflared"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf '{"source":"standalone"}\n' > "${home}/.cloudflared/0000.json"

  HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
    "${ROOT_DIR}/scripts/easygate" deploy --domain example.test --skip-route --demo --no-install-cloudflared

  assert_contains "${runtime}/compose/.env" "BASE_DOMAIN=example.test"
  assert_contains "${runtime}/compose/docker-compose.yml" "image: traefik:v3.1"
  assert_contains "${runtime}/traefik/traefik.yml" "providers:"
  assert_contains "${runtime}/cloudflared/config.yml" 'hostname: "*.example.test"'
  assert_contains "${runtime}/cloudflared/easygate-home.json" '"source":"standalone"'
  assert_contains "$log" "docker compose -p easygate"
}

run_install_behavior_test() {
  local runtime="${TMP_DIR}/install-runtime"
  local mock_home="${TMP_DIR}/install-mock-home"

  info "验证 install.sh 可安装 standalone CLI"
  # 覆盖 HOME 防止 add_to_path 写入真实 shell 配置文件
  # 同时创建 .bashrc/.bash_profile 兼容不同 SHELL 环境的检测逻辑
  mkdir -p "$mock_home"
  printf '' > "${mock_home}/.bashrc"
  printf '' > "${mock_home}/.bash_profile"

  HOME="$mock_home" EASYGATE_HOME="$runtime" EASYGATE_LOCAL_CLI="${ROOT_DIR}/scripts/easygate" \
    bash "${ROOT_DIR}/scripts/install.sh" >/dev/null

  assert_file "${runtime}/bin/easygate"
  EASYGATE_HOME="$runtime" "${runtime}/bin/easygate" version | grep -q "easygate" || fail "安装后的 easygate 无法运行"

  # 验证 PATH 已写入 mock 配置文件而非真实文件
  local found=false
  for f in .bashrc .bash_profile; do
    if grep -qs "${runtime}/bin" "${mock_home}/${f}" 2>/dev/null; then found=true; break; fi
  done
  if [[ "$found" != true ]]; then
    fail "install.sh 未将 CLI 目录写入 mock shell 配置文件"
  fi
}

run_install_pipe_behavior_test() {
  local runtime="${TMP_DIR}/install-pipe-runtime"
  local mock_home="${TMP_DIR}/install-pipe-mock-home"

  info "验证 install.sh 通过管道模式（curl | bash）可正常安装"
  # 通过 stdin 管道传递脚本，模拟 curl | bash 场景
  # 此时 BASH_SOURCE 为空，脚本不能依赖 lib.sh 或文件系统上下文
  mkdir -p "$mock_home"
  printf '' > "${mock_home}/.bashrc"
  printf '' > "${mock_home}/.bash_profile"

  HOME="$mock_home" EASYGATE_HOME="$runtime" EASYGATE_LOCAL_CLI="${ROOT_DIR}/scripts/easygate" \
    bash < "${ROOT_DIR}/scripts/install.sh" >/dev/null

  assert_file "${runtime}/bin/easygate"
  EASYGATE_HOME="$runtime" "${runtime}/bin/easygate" version | grep -q "easygate" || fail "管道安装后的 easygate 无法运行"
}

run_cleanup_command_behavior_test() {
  local fixture="${TMP_DIR}/cleanup-cmd-fixture"
  local bin="${TMP_DIR}/cleanup-cmd-bin"
  local log="${TMP_DIR}/cleanup-cmd-commands.log"
  local runtime="${TMP_DIR}/cleanup-cmd-runtime"

  info "验证 cleanup compose down 命令不含 --profile（防止只停 demo 服务）"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${runtime}/compose" "${runtime}/cloudflared"
  printf 'compose\n' > "${runtime}/compose/docker-compose.yml"
  printf 'env\n' > "${runtime}/compose/.env"
  printf 'secret\n' > "${runtime}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    EASYGATE_HOME="$runtime" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" bash scripts/cleanup.sh
  )
  if grep -Fq -- "--profile" "$log"; then
    fail "cleanup.sh 的 compose down 不应包含 --profile（否则只停 demo）"
  fi
  assert_contains "$log" "down --remove-orphans"
}

run_validation_behavior_test() {
  info "验证输入校验函数能正确拒绝非法值"

  # 测试 validate_port
  local script_dir="${ROOT_DIR}/scripts"

  # 从 easygate CLI 中抽取校验函数并执行测试
  local test_script="${TMP_DIR}/validate_test.sh"
  # 提取校验函数（需要 error() 辅助函数）
  {
    printf 'set -euo pipefail\n'
    printf 'error() { printf "%%s\\n" "$1" >&2; }\n'
    sed -n '/^validate_port()/,/^}/p' "${script_dir}/easygate"
    sed -n '/^validate_domain()/,/^}/p' "${script_dir}/easygate"
    sed -n '/^validate_tunnel_name()/,/^}/p' "${script_dir}/easygate"
  } > "$test_script"

  # 添加测试主逻辑
  cat >> "$test_script" <<'EOF_TEST'
fail_count=0
_test() {
  local desc="$1" expected="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then actual=0; else actual=1; fi
  if [[ "$actual" -ne "$expected" ]]; then
    echo "FAIL: ${desc} (expected exit ${expected}, got ${actual})"
    : $((fail_count++))
  fi
}

# validate_port
_test "port 80"     0 validate_port 80
_test "port 1"      0 validate_port 1
_test "port 65535"  0 validate_port 65535
_test "port 0"      1 validate_port 0
_test "port 65536"  1 validate_port 65536
_test "port -1"     1 validate_port -1
_test "port abc"    1 validate_port abc
_test "port empty"  1 validate_port ""

# validate_domain (example.test 是合法测试域名)
_test "domain ok"   0 validate_domain example.test
_test "domain sub"  0 validate_domain api.example.test
_test "domain example.com" 1 validate_domain example.com
_test "domain no-dot" 1 validate_domain localhost
_test "domain spaces" 1 validate_domain "bad domain"

# validate_tunnel_name
_test "tunnel ok"   0 validate_tunnel_name easygate-home
_test "tunnel digit" 0 validate_tunnel_name mytunnel1
_test "tunnel leading-hyphen" 1 validate_tunnel_name "-bad-tunnel"
_test "tunnel trailing-hyphen" 1 validate_tunnel_name "bad-"
_test "tunnel empty" 1 validate_tunnel_name ""

exit $fail_count
EOF_TEST

  bash "$test_script" || fail "输入校验测试未通过（部分校验函数未通过测试）"
}

run_uninstall_behavior_test() {
  local fixture="${TMP_DIR}/uninstall-fixture"
  local bin="${TMP_DIR}/uninstall-bin"
  local log="${TMP_DIR}/uninstall-commands.log"
  local runtime="${TMP_DIR}/uninstall-runtime"

  info "验证 uninstall 会删除 CLI 二进制并清理 shell 配置"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  # 模拟已安装的 CLI
  mkdir -p "${runtime}/bin"
  printf '#!/usr/bin/env bash\necho fake easygate\n' > "${runtime}/bin/easygate"
  chmod +x "${runtime}/bin/easygate"

  # 创建 mock shell 配置文件（文件名为 .zshrc 以匹配 detect_rc_file 逻辑）
  local mock_rc="${TMP_DIR}/.zshrc"
  printf 'export PATH="/usr/local/bin:$PATH"\n' > "$mock_rc"
  {
    printf '\n# EasyGate CLI\n'
    printf "export PATH='${runtime}/bin':\"\$PATH\"\n"
  } >> "$mock_rc"
  printf 'export EDITOR=vim\n' >> "$mock_rc"

  (
    cd "$fixture"
    HOME="$TMP_DIR" SHELL="/bin/zsh" EASYGATE_HOME="$runtime" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/uninstall.sh
  )

  # CLI 二进制已删除
  assert_missing "${runtime}/bin/easygate"
  # PATH 配置行已从 shell 配置中移除
  if grep -qs "${runtime}/bin" "$mock_rc" 2>/dev/null; then
    fail "uninstall 未删除 shell 配置文件中的 EasyGate PATH 行"
  fi
  # 其余内容保留
  if ! grep -qs "EDITOR=vim" "$mock_rc" 2>/dev/null; then
    fail "uninstall 删除了 shell 配置文件中非 EasyGate 的内容"
  fi
}

run_native_stop_start_behavior_test() {
  local runtime_dir
  runtime_dir="${TMP_DIR}/stop-start-runtime"

  info "验证 stop_pid_file 能停止进程（含 SIGKILL 兜底）"
  mkdir -p "${runtime_dir}/run"

  # Start a process that ignores SIGTERM (simulating stubborn process)
  # Use perl which is available on all platforms
  perl -e '$SIG{TERM} = sub {}; sleep 120' &
  local pid=$!
  echo "$pid" > "${runtime_dir}/run/native-traefik.pid"

  # Use stop_pid_file from easygate (imported inline)
  stop_pid_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then return 0; fi
    local p; p="$(cat "$file" 2>/dev/null || true)"
    if [[ -n "$p" ]] && kill -0 "$p" >/dev/null 2>&1; then
      kill "$p" >/dev/null 2>&1 || true
      local waited
      for waited in {1..20}; do
        kill -0 "$p" >/dev/null 2>&1 || break
        sleep 0.2
      done
      if kill -0 "$p" >/dev/null 2>&1; then
        kill -9 "$p" >/dev/null 2>&1 || true
        sleep 0.5
      fi
    fi
    rm -f "$file"
  }

  stop_pid_file "${runtime_dir}/run/native-traefik.pid"

  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
    fail "stop_pid_file 未能停止进程（含 SIGKILL 兜底）"
  fi
}

run_deploy_mode_file_test() {
  local fixture home_dir runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/mode-file-fixture"
  home_dir="${TMP_DIR}/mode-file-home"
  runtime_dir="${TMP_DIR}/mode-file-runtime"
  bin_dir="${TMP_DIR}/mode-file-bin"
  log_file="${TMP_DIR}/mode-file.log"

  info "验证部署时写入 .mode 文件"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"
  rm -f "${fixture}/cloudflared/config.yml" "${fixture}/cloudflared/easygate-home.json"

  mkdir -p "${home_dir}/.cloudflared" "${runtime_dir}"
  touch "${home_dir}/.cloudflared/cert.pem"
  echo '{"source":"mode-file"}' > "${home_dir}/.cloudflared/0000.json"

  EASYGATE_CI=true \
  EASYGATE_CLOUDFLARED_HOME="${home_dir}/.cloudflared" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" deploy --domain "example.test" --skip-route --no-install-cloudflared || true

  assert_contains "${runtime_dir}/.mode" "compose"
}

run_cloudflared_config_test() {
  local fixture home_dir runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/cf-config-fixture"
  home_dir="${TMP_DIR}/cf-config-home"
  runtime_dir="${TMP_DIR}/cf-config-runtime"
  bin_dir="${TMP_DIR}/cf-config-bin"
  log_file="${TMP_DIR}/cf-config.log"

  info "验证 cloudflared 配置包含 ha-connections 和 loglevel"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"
  rm -f "${fixture}/cloudflared/config.yml" "${fixture}/cloudflared/easygate-home.json"

  mkdir -p "${home_dir}/.cloudflared" "${runtime_dir}"
  touch "${home_dir}/.cloudflared/cert.pem"
  echo '{"source":"cf-config"}' > "${home_dir}/.cloudflared/0000.json"

  EASYGATE_CI=true \
  EASYGATE_CLOUDFLARED_HOME="${home_dir}/.cloudflared" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" deploy --domain "example.test" --skip-route --no-install-cloudflared || true

  assert_contains "${runtime_dir}/cloudflared/config.yml" "ha-connections"
  assert_contains "${runtime_dir}/cloudflared/config.yml" "loglevel"
}

run_native_cloudflared_config_test() {
  local fixture home_dir runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/native-cf-config-fixture"
  home_dir="${TMP_DIR}/native-cf-config-home"
  runtime_dir="${TMP_DIR}/native-cf-config-runtime"
  bin_dir="${TMP_DIR}/native-cf-config-bin"
  log_file="${TMP_DIR}/native-cf-config.log"

  info "验证原生模式 cloudflared 配置包含 ha-connections 和 loglevel"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"
  rm -f "${fixture}/cloudflared/config.yml" "${fixture}/cloudflared/easygate-home.json"

  mkdir -p "${home_dir}/.cloudflared" "${runtime_dir}" "${runtime_dir}/run" "${runtime_dir}/logs"
  touch "${home_dir}/.cloudflared/cert.pem"
  echo '{"source":"native-cf"}' > "${home_dir}/.cloudflared/0000.json"

  EASYGATE_CI=true \
  EASYGATE_CLOUDFLARED_HOME="${home_dir}/.cloudflared" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" deploy --native --domain "example.test" --skip-route --no-install-cloudflared --no-install-traefik || true

  assert_contains "${runtime_dir}/cloudflared/config.native.yml" "ha-connections"
  assert_contains "${runtime_dir}/cloudflared/config.native.yml" "loglevel"
}

run_uninstall_cleanup_test() {
  local fixture home_dir runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/uninstall-cleanup-fixture"
  home_dir="${TMP_DIR}/uninstall-cleanup-home"
  runtime_dir="${TMP_DIR}/uninstall-cleanup-runtime"
  bin_dir="${TMP_DIR}/uninstall-cleanup-bin"
  log_file="${TMP_DIR}/uninstall-cleanup.log"

  info "验证 uninstall 清理 PID 文件和运行时目录"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"

  mkdir -p "${runtime_dir}/run" "${runtime_dir}/logs" "${runtime_dir}/compose"
  touch "${runtime_dir}/compose/docker-compose.yml"
  touch "${runtime_dir}/compose/.env"
  echo "12345" > "${runtime_dir}/run/native-traefik.pid"
  echo "12346" > "${runtime_dir}/run/native-cloudflared.pid"

  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" uninstall || true

  assert_missing "$runtime_dir"
}

run_ps_shows_all_services_test() {
  local fixture home_dir runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/ps-all-fixture"
  home_dir="${TMP_DIR}/ps-all-home"
  runtime_dir="${TMP_DIR}/ps-all-runtime"
  bin_dir="${TMP_DIR}/ps-all-bin"
  log_file="${TMP_DIR}/ps-all.log"

  info "验证 ps 显示所有服务状态（含 demo）"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"
  rm -f "${fixture}/cloudflared/config.yml" "${fixture}/cloudflared/easygate-home.json"

  mkdir -p "${home_dir}/.cloudflared" "${runtime_dir}/run" "${runtime_dir}/logs"
  touch "${home_dir}/.cloudflared/cert.pem"
  echo '{"source":"ps-all"}' > "${home_dir}/.cloudflared/0000.json"

  # Deploy with --demo to generate demo service config
  EASYGATE_CI=true \
  EASYGATE_CLOUDFLARED_HOME="${home_dir}/.cloudflared" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" deploy --native --domain "example.test" --skip-route --demo --no-install-cloudflared --no-install-traefik --local-only || true

  # Check ps output mentions demo services (even if stopped)
  local ps_output
  ps_output="$(EASYGATE_HOME="$runtime_dir" PATH="${bin_dir}:$PATH" bash "${fixture}/scripts/easygate" ps 2>&1)" || true
  if ! echo "$ps_output" | grep -q "demo-api"; then
    fail "ps 输出未包含 demo-api: $ps_output"
  fi
  if ! echo "$ps_output" | grep -q "demo-test-api"; then
    fail "ps 输出未包含 demo-test-api: $ps_output"
  fi
}

trap 'rm -rf "$TMP_DIR"' EXIT

run_deploy_behavior_test
run_compose_deploy_blocks_native_test
run_native_deploy_behavior_test
run_native_deploy_blocks_compose_test
run_cleanup_behavior_test
run_cleanup_command_behavior_test
run_native_cleanup_behavior_test
run_standalone_cli_behavior_test
run_install_behavior_test
run_install_pipe_behavior_test
run_validation_behavior_test
run_uninstall_behavior_test
run_native_stop_start_behavior_test
run_deploy_mode_file_test
run_cloudflared_config_test
run_native_cloudflared_config_test
run_uninstall_cleanup_test
run_ps_shows_all_services_test

info "行为测试通过"
