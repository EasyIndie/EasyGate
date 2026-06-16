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
      bash ${fixture}/scripts/easygate deploy --domain example.test --skip-route --demo --no-install-cloudflared
  )
  (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash ${fixture}/scripts/easygate deploy --domain example.test --skip-route --demo --no-install-cloudflared
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
      bash ${fixture}/scripts/easygate deploy --domain example.test --skip-route --no-install-cloudflared
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
      bash ${fixture}/scripts/easygate deploy --native --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  )
  (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_CI=true \
      bash ${fixture}/scripts/easygate deploy --native --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  )

  assert_contains "${runtime}/native/.env" "EASYGATE_DEPLOY_MODE=native"
  assert_contains "${runtime}/native/traefik.yml" "providers:"
  assert_contains "${runtime}/native/traefik.yml" "${runtime}/native/dynamic"
  assert_contains "${runtime}/native/dynamic/services.yml" "service: api@internal"
  assert_contains "${runtime}/cloudflared/config.native.yml" "service: http://127.0.0.1:18080"

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
      bash ${fixture}/scripts/easygate deploy --native --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  ); then
    fail "Docker Compose 模式运行时 deploy-native.sh 不应继续部署"
  fi

  assert_missing "${runtime}/native/traefik.yml"
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

  info "验证 cleanup compose down 包含 --profile demo（确保 demo 容器也清理）"
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
  assert_contains "$log" "--profile demo"
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
      bash ${fixture}/scripts/easygate uninstall
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

  EASYGATE_MOCK_LOG="$log_file" \
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

  EASYGATE_MOCK_LOG="$log_file" \
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

  EASYGATE_MOCK_LOG="$log_file" \
  EASYGATE_CI=true \
  EASYGATE_CLOUDFLARED_HOME="${home_dir}/.cloudflared" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" deploy --native --domain "example.test" --skip-route --no-install-cloudflared --no-install-traefik || true

  assert_contains "${runtime_dir}/cloudflared/config.native.yml" "ha-connections"
  assert_contains "${runtime_dir}/cloudflared/config.native.yml" "loglevel"
}

run_uninstall_cleanup_test() {
  local fixture home_dir runtime_dir bin_dir log_file backup_dir
  fixture="${TMP_DIR}/uninstall-cleanup-fixture"
  home_dir="${TMP_DIR}/uninstall-cleanup-home"
  runtime_dir="${TMP_DIR}/uninstall-cleanup-runtime"
  bin_dir="${TMP_DIR}/uninstall-cleanup-bin"
  log_file="${TMP_DIR}/uninstall-cleanup.log"
  backup_dir="${home_dir}/.easygate.uninstall-backup"

  info "验证 uninstall 清理运行时目录并备份自定义服务"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"

  mkdir -p "${runtime_dir}/run" "${runtime_dir}/logs" "${runtime_dir}/compose" \
    "${runtime_dir}/traefik/dynamic"
  touch "${runtime_dir}/compose/docker-compose.yml"
  touch "${runtime_dir}/compose/.env"
  echo "12345" > "${runtime_dir}/run/native-traefik.pid"
  echo "12346" > "${runtime_dir}/run/native-cloudflared.pid"

  # 模拟自定义服务 YAML
  cat > "${runtime_dir}/traefik/dynamic/localhost-services.yml" <<'EOF_SERVICE'
http:
  routers:
    my-app:
      rule: Host(`myapp.example.com`)
      entryPoints:
        - web
      service: my-app
  services:
    my-app:
      loadBalancer:
        servers:
          - url: http://192.168.1.100:8080
EOF_SERVICE

  HOME="$home_dir" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" uninstall || true

  # 运行时目录已被删除
  assert_missing "$runtime_dir"

  # 自定义服务配置已备份到 EASYGATE_HOME 之外
  assert_file "${backup_dir}/services.yml"
  assert_contains "${backup_dir}/services.yml" "my-app"
  assert_contains "${backup_dir}/services.yml" "myapp.example.com"

  # 清理备份
  rm -rf "$backup_dir"
}

run_uninstall_backup_restore_test() {
  local fixture home_dir runtime_dir bin_dir log_file backup_dir
  fixture="${TMP_DIR}/backup-restore-fixture"
  home_dir="${TMP_DIR}/backup-restore-home"
  runtime_dir="${TMP_DIR}/backup-restore-runtime"
  bin_dir="${TMP_DIR}/backup-restore-bin"
  log_file="${TMP_DIR}/backup-restore.log"
  backup_dir="${home_dir}/.easygate.uninstall-backup"

  info "验证 uninstall 正确备份自定义服务配置"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"

  # 模拟 compose 模式部署，包含自定义服务
  mkdir -p "${runtime_dir}/run" "${runtime_dir}/logs" "${runtime_dir}/compose" \
    "${runtime_dir}/traefik/dynamic"
  touch "${runtime_dir}/compose/docker-compose.yml"
  touch "${runtime_dir}/compose/.env"
  echo "compose" > "${runtime_dir}/.mode"

  # 创建一个包含多个自定义服务的 YAML
  cat > "${runtime_dir}/traefik/dynamic/localhost-services.yml" <<'EOF_SERVICE'
http:
  routers:
    my-app:
      rule: Host(`myapp.example.com`)
      entryPoints:
        - web
      service: my-app
    another-app:
      rule: Host(`another.example.com`)
      entryPoints:
        - web
      service: another-app
  services:
    my-app:
      loadBalancer:
        servers:
          - url: http://192.168.1.100:8080
    another-app:
      loadBalancer:
        servers:
          - url: http://192.168.1.101:3000
EOF_SERVICE

  HOME="$home_dir" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" uninstall || true

  # 运行时目录已删除
  assert_missing "$runtime_dir"

  # 备份已创建且内容完整
  assert_file "${backup_dir}/services.yml"
  assert_contains "${backup_dir}/services.yml" "my-app"
  assert_contains "${backup_dir}/services.yml" "another-app"
  assert_contains "${backup_dir}/services.yml" "192.168.1.100"
  assert_contains "${backup_dir}/services.yml" "192.168.1.101"

  # .env 也备份了
  assert_file "${backup_dir}/compose.env"

  info "  ✓ 卸载后自定义服务配置完整保留在备份目录"

  # 清理
  rm -rf "$backup_dir"
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
  EASYGATE_MOCK_LOG="$log_file" \
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

run_local_only_test() {
  local fixture home_dir runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/local-only-fixture"
  home_dir="${TMP_DIR}/local-only-home"
  runtime_dir="${TMP_DIR}/local-only-runtime"
  bin_dir="${TMP_DIR}/local-only-bin"
  log_file="${TMP_DIR}/local-only.log"

  info "验证 --local-only 模式跳过 cloudflared（仅启动 Traefik）"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"
  rm -f "${fixture}/cloudflared/config.yml" "${fixture}/cloudflared/easygate-home.json"

  mkdir -p "${home_dir}/.cloudflared" "${runtime_dir}/run" "${runtime_dir}/logs"
  touch "${home_dir}/.cloudflared/cert.pem"
  echo '{"source":"local-only"}' > "${home_dir}/.cloudflared/0000.json"

  EASYGATE_MOCK_LOG="$log_file" \
  EASYGATE_CI=true \
  EASYGATE_CLOUDFLARED_HOME="${home_dir}/.cloudflared" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" deploy --native --domain "example.test" --demo --local-only --no-install-traefik || true

  # 不应创建 cloudflared 配置
  assert_missing "${runtime_dir}/cloudflared/config.native.yml"
  # 不应调用 cloudflared tunnel 命令
  if grep -Fq "cloudflared tunnel" "$log_file"; then
    fail "--local-only 模式下不应调用 cloudflared tunnel"
  fi
  # 应包含 native/.env 且标记为 native 模式
  assert_contains "${runtime_dir}/native/.env" "EASYGATE_DEPLOY_MODE=native"
}

run_restart_test() {
  local fixture runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/restart-fixture"
  runtime_dir="${TMP_DIR}/restart-runtime"
  bin_dir="${TMP_DIR}/restart-bin"
  log_file="${TMP_DIR}/restart.log"

  info "验证 restart 子命令可执行（compose 模式）"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"

  mkdir -p "${runtime_dir}/compose" "${runtime_dir}/cloudflared"
  printf 'compose\n' > "${runtime_dir}/compose/docker-compose.yml"
  printf 'env\n' > "${runtime_dir}/compose/.env"
  printf 'compose\n' > "${runtime_dir}/.mode"

  EASYGATE_HOME="$runtime_dir" PATH="${bin_dir}:$PATH" EASYGATE_MOCK_LOG="$log_file" \
    bash "${fixture}/scripts/easygate" restart || true

  # restart 应触发 docker compose restart
  assert_contains "$log_file" "docker compose -p easygate"
}

run_config_test() {
  local fixture runtime_dir bin_dir log_file
  fixture="${TMP_DIR}/config-fixture"
  runtime_dir="${TMP_DIR}/config-runtime"
  bin_dir="${TMP_DIR}/config-bin"
  log_file="${TMP_DIR}/config.log"

  info "验证 config 子命令输出配置内容"
  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"

  mkdir -p "${runtime_dir}/native" "${runtime_dir}/run" "${runtime_dir}/logs"
  printf 'native\n' > "${runtime_dir}/.mode"
  printf 'entryPoints:\n  web:\n    address: ":18080"\n' > "${runtime_dir}/native/traefik.yml"

  local config_output
  config_output="$(EASYGATE_HOME="$runtime_dir" PATH="${bin_dir}:$PATH" bash "${fixture}/scripts/easygate" config 2>&1)" || true
  if ! echo "$config_output" | grep -q "entryPoints"; then
    fail "config 输出应包含 Traefik 配置内容: $config_output"
  fi
}

run_systemd_name_regression_test() {
  info "验证 systemd 服务名一致性（native-traefik / native-cloudflared）"

  # 检查 deploy_native() 中 register_systemd 调用用的名字
  if ! grep -q 'register_systemd "native-traefik"' "${ROOT_DIR}/scripts/easygate"; then
    fail "deploy_native 中未找到 register_systemd native-traefik"
  fi
  if ! grep -q 'register_systemd "native-cloudflared"' "${ROOT_DIR}/scripts/easygate"; then
    fail "deploy_native 中未找到 register_systemd native-cloudflared"
  fi

  # 检查 start_native_services / stop_native_services / unregister_native_services
  # 使用的服务名与 register 创建的一致
  if grep -q 'easygate-traefik\.service' "${ROOT_DIR}/scripts/easygate"; then
    fail "scripts/easygate 中仍有 easygate-traefik.service 引用，应为 native-traefik.service"
  fi
  if grep -q 'easygate-cloudflared\.service' "${ROOT_DIR}/scripts/easygate"; then
    fail "scripts/easygate 中仍有 easygate-cloudflared.service 引用，应为 native-cloudflared.service"
  fi
}

run_completion_test() {
  info "验证 completion 子命令输出有效的补全脚本"

  local bash_out zsh_out
  bash_out="$("${ROOT_DIR}/scripts/easygate" completion bash 2>&1)" || fail "completion bash 失败"
  zsh_out="$("${ROOT_DIR}/scripts/easygate" completion zsh 2>&1)"   || fail "completion zsh 失败"

  # bash 补全输出包含关键元素
  if ! echo "$bash_out" | grep -q "_easygate"; then
    fail "bash completion 未包含 _easygate 函数"
  fi
  if ! echo "$bash_out" | grep -q "complete -F _easygate"; then
    fail "bash completion 未包含 complete -F 注册"
  fi
  if ! echo "$bash_out" | grep -q "deploy"; then
    fail "bash completion 未包含 deploy 命令补全"
  fi

  # zsh 补全输出包含关键元素
  if ! echo "$zsh_out" | grep -q "#compdef easygate"; then
    fail "zsh completion 未包含 #compdef 标记"
  fi
  if ! echo "$zsh_out" | grep -q "_easygate"; then
    fail "zsh completion 未包含 _easygate 函数"
  fi
}

run_service_helper_unit_test() {
  local helper="${ROOT_DIR}/scripts/service-helper.py"
  local tmp_dir="${TMP_DIR}/service-helper-test"
  mkdir -p "$tmp_dir"

  info "验证 service-helper.py YAML 增删查操作"

  # ── ╳ 1. add 服务到新文件 ──
  local yaml="${tmp_dir}/test1.yml"
  python3 "$helper" add "$yaml" "my-api" "api.example.com" "http://192.168.1.10:8080"
  assert_file "$yaml"
  assert_contains "$yaml" "routers:"
  assert_contains "$yaml" "my-api"
  assert_contains "$yaml" "api.example.com"
  assert_contains "$yaml" "192.168.1.10:8080"

  # ── ╳ 2. add 多个服务 ──
  python3 "$helper" add "$yaml" "another-api" "another.example.com" "http://192.168.1.11:3000"
  assert_contains "$yaml" "another-api"
  assert_contains "$yaml" "another.example.com"
  assert_contains "$yaml" "192.168.1.11:3000"

  # ── ╳ 3. add 重复服务应报错 ──
  if python3 "$helper" add "$yaml" "my-api" "dup.example.com" "http://dup:8080" 2>/dev/null; then
    fail "添加重复服务应退出非 0"
  fi

  # ── ╳ 4. list 输出包含服务信息 ──
  local list_out
  list_out="$(python3 "$helper" list "$yaml")" || fail "list 失败"
  if ! echo "$list_out" | grep -q "my-api"; then
    fail "list 输出应包含 my-api: $list_out"
  fi
  if ! echo "$list_out" | grep -q "api.example.com"; then
    fail "list 输出应包含 api.example.com: $list_out"
  fi

  # ── ╳ 5. remove 已有服务 ──
  python3 "$helper" remove "$yaml" "my-api"
  if grep -q "    my-api:" "$yaml" 2>/dev/null; then
    fail "remove my-api 后文件中仍存在 my-api"
  fi
  assert_contains "$yaml" "another-api"  # 另一个应保留

  # ── ╳ 6. remove 不存在服务应静默退出 ──
  python3 "$helper" remove "$yaml" "nonexistent" || true

  # ── ╳ 7. list 空文件 ──
  local empty_yaml="${tmp_dir}/empty.yml"
  python3 "$helper" list "$empty_yaml" 2>&1 | grep -q "暂无已配置的服务" \
    || fail "空文件 list 应显示提示信息"
  [[ ! -f "$empty_yaml" ]] || fail "list 不应创建文件"

  # ── ╳ 8. 空占位符 {} 展开 ──
  local braces_yaml="${tmp_dir}/braces.yml"
  printf 'http:\n  routers: {}\n  services: {}\n' > "$braces_yaml"
  python3 "$helper" add "$braces_yaml" "new-svc" "new.example.com" "http://new:9090"
  if grep -q '{}' "$braces_yaml" 2>/dev/null; then
    fail "add 后应展开 {} 占位符"
  fi
  assert_contains "$braces_yaml" "new-svc"

  # ── ╳ 9. add 后 remove 恢复结构 ──
  local clean="${tmp_dir}/clean.yml"
  printf 'http:\n  routers: {}\n  services: {}\n' > "$clean"
  python3 "$helper" add "$clean" "temp-svc" "temp.example.com" "http://temp:8080"
  python3 "$helper" remove "$clean" "temp-svc"
  if grep -q "    " "$clean" 2>/dev/null; then
    fail "remove 后不应有缩进条目"
  fi
  assert_contains "$clean" "routers:"
  assert_contains "$clean" "services:"

  info "  ✓ service-helper.py YAML 操作全部通过"
}

# ── Helper: extract a bash function from easygate by name ──
_extract_fn() {
  local name="$1" script="$2"
  sed -n "/^${name}()/,/^}/p" "$script"
}

run_restore_unit_test() {
  local script="${ROOT_DIR}/scripts/easygate"
  local tmp_dir="${TMP_DIR}/restore-unit-test"
  mkdir -p "$tmp_dir"

  info "验证 _deploy_restore_user_data 边界条件"
  local scenarios_passed=0 scenarios_total=0

  # Creates a standalone test script for one scenario and runs it.
  # Usage: _run_scenario <name> <home_dir> <extra_vars> <mock_read_func>
  _run_scenario() {
    local name="$1" home="$2" runtime="$3" extra_vars="$4" mock_read="$5"
    local test_file="${tmp_dir}/sc_${name}.sh"
    scenarios_total=$((scenarios_total + 1))

    {
      printf 'set -euo pipefail\n'
      printf 'HOME="%s"\n' "$home"
      printf 'EASYGATE_HOME="%s"\n' "$runtime"
      printf 'EASYGATE_CI=\n'
      printf '%s\n' "$extra_vars"
      # Mock dependencies
      printf 'info() { printf "INFO: %%s\\n" "$1"; }\n'
      printf 'warn() { printf "WARN: %%s\\n" "$1"; }\n'
      printf 'error() { local m="%%s"; printf "ERROR: ${m}\\n" "$1" >&2; exit 1; }\n'
      printf '_service_yaml_path() { printf "%%s/native/dynamic/services.yml" "$EASYGATE_HOME"; }\n'
      printf 'restart_services() { echo "RESTART_CALLED"; }\n'
      # Mock read
      printf '%s\n' "$mock_read"
      _extract_fn "_deploy_restore_user_data" "$script"
      printf '\n_deploy_restore_user_data "true"\n'
      printf 'echo "EXIT_OK"\n'
    } > "$test_file"

    local output
    if output="$(bash "$test_file" 2>&1)"; then
      if echo "$output" | grep -q "EXIT_OK"; then
        scenarios_passed=$((scenarios_passed + 1))
        return 0
      fi
    fi
    fail "场景「${name}」失败\n输出：${output}"
  }

  local h r

  # 1. 无备份目录 → 跳过
  h="${tmp_dir}/h1"; mkdir -p "$h"
  _run_scenario "no-backup" "$h" "${tmp_dir}/r1" "" "read() { :; }" && info "  ✓ 无备份目录跳过"

  # 2. 空备份文件 → 清理并跳过
  h="${tmp_dir}/h2"; mkdir -p "$h" "${h}/.easygate.uninstall-backup"
  printf '# comment only\n' > "${h}/.easygate.uninstall-backup/services.yml"
  _run_scenario "empty-backup" "$h" "${tmp_dir}/r2" "" "read() { :; }"
  # 空备份应被删除
  [[ ! -f "${h}/.easygate.uninstall-backup/services.yml" ]] || fail "空备份文件应被清理"
  info "  ✓ 空备份文件清理并跳过"

  # 3. CI 环境 → 跳过恢复，保留备份
  h="${tmp_dir}/h3"; mkdir -p "$h" "${h}/.easygate.uninstall-backup"
  printf 'http:\n  routers:\n    t:\n      rule: Host(`t.c`)\n' > "${h}/.easygate.uninstall-backup/services.yml"
  _run_scenario "ci-mode" "$h" "${tmp_dir}/r3" "EASYGATE_CI=true" "read() { :; }"
  assert_file "${h}/.easygate.uninstall-backup/services.yml"  # 应保留
  info "  ✓ CI 环境跳过恢复，备份保留"

  # 4. do_restore=false → 跳过
  h="${tmp_dir}/h4"; mkdir -p "$h" "${h}/.easygate.uninstall-backup"
  printf 'http:\n  routers:\n    t:\n      rule: Host(`t.c`)\n' > "${h}/.easygate.uninstall-backup/services.yml"
  # 直接测试函数第一行就返回的场景
  {
    printf 'set -euo pipefail\n'
    printf '_deploy_restore_user_data() { local do_restore="${1:-true}"; [[ "$do_restore" != "true" ]] && return 0; return 1; }\n'
    printf '_deploy_restore_user_data "false"\n'
    printf 'echo "EXIT_OK"\n'
  } > "${tmp_dir}/sc_no-restore.sh"
  output="$(bash "${tmp_dir}/sc_no-restore.sh" 2>&1)" || fail "场景 no-restore 失败：$output"
  assert_file "${h}/.easygate.uninstall-backup/services.yml"
  info "  ✓ --no-restore 跳过恢复"

  # 5. 交互式恢复（Y）→ 文件恢复
  h="${tmp_dir}/h5"; r="${tmp_dir}/r5"
  mkdir -p "$h" "${h}/.easygate.uninstall-backup" "$r"
  printf 'http:\n  routers:\n    test-svc:\n      rule: Host(`test.example.com`)\n' > "${h}/.easygate.uninstall-backup/services.yml"
  {
    printf 'set -euo pipefail\n'
    printf 'HOME="%s"\n' "$h"
    printf 'EASYGATE_HOME="%s"\n' "$r"
    printf 'info() { printf "INFO: %%s\\n" "$1"; }\n'
    printf 'warn() { :; }\n'
    printf 'error() { printf "ERROR: %%s\\n" "$1" >&2; exit 1; }\n'
    printf '_service_yaml_path() { printf "%%s/native/dynamic/services.yml" "$EASYGATE_HOME"; }\n'
    printf 'restart_services() { echo "RESTART_CALLED"; }\n'
    _extract_fn "_deploy_restore_user_data" "$script"
    printf '\n_deploy_restore_user_data "true"\n'
    printf 'echo "EXIT_OK"\n'
  } > "${tmp_dir}/sc_y.sh"
  # stdin: "y" 恢复 + "n" 跳过重启
  output="$(printf 'y\nn\n' | bash "${tmp_dir}/sc_y.sh" 2>&1)" || fail "场景 interactive-yes 失败：$output"
  assert_file "${r}/native/dynamic/services.yml"
  assert_contains "${r}/native/dynamic/services.yml" "test-svc"
  [[ ! -d "${h}/.easygate.uninstall-backup" ]] || fail "恢复后备份应被删除"
  info "  ✓ 交互式恢复（Y）"

  # 6. 交互式拒绝（N）→ 保留备份，不恢复
  h="${tmp_dir}/h6"; r="${tmp_dir}/r6"
  mkdir -p "$h" "${h}/.easygate.uninstall-backup" "$r"
  printf 'http:\n  routers:\n    skipped:\n      rule: Host(`skip.c`)\n' > "${h}/.easygate.uninstall-backup/services.yml"
  {
    printf 'set -euo pipefail\n'
    printf 'HOME="%s"\n' "$h"
    printf 'EASYGATE_HOME="%s"\n' "$r"
    printf 'info() { :; }\n'
    printf 'warn() { :; }\n'
    printf 'error() { printf "ERROR: %%s\\n" "$1" >&2; exit 1; }\n'
    printf '_service_yaml_path() { printf "%%s/native/dynamic/services.yml" "$EASYGATE_HOME"; }\n'
    printf 'restart_services() { :; }\n'
    _extract_fn "_deploy_restore_user_data" "$script"
    printf '\n_deploy_restore_user_data "true"\n'
    printf 'echo "EXIT_OK"\n'
  } > "${tmp_dir}/sc_n.sh"
  # stdin: "n" 拒绝恢复（不触发第二个 prompt）
  output="$(printf 'n\n' | bash "${tmp_dir}/sc_n.sh" 2>&1)" || fail "场景 interactive-no 失败：$output"
  [[ ! -f "${r}/native/dynamic/services.yml" ]] || fail "交互式拒绝后不应恢复文件"
  assert_file "${h}/.easygate.uninstall-backup/services.yml"
  info "  ✓ 交互式拒绝（N）"

  # 7. Compose 模式目标路径
  h="${tmp_dir}/h7"; r="${tmp_dir}/r7"
  mkdir -p "$h" "$r" "${h}/.easygate.uninstall-backup"
  printf 'http:\n  routers:\n    c:\n      rule: Host(`c.c`)\n' > "${h}/.easygate.uninstall-backup/services.yml"
  {
    printf 'set -euo pipefail\n'
    printf 'HOME="%s"\n' "$h"
    printf 'EASYGATE_HOME="%s"\n' "$r"
    printf '_service_yaml_path() { printf "%%s/traefik/dynamic/localhost-services.yml" "$EASYGATE_HOME"; }\n'
    printf 'info() { :; }\n'
    printf 'warn() { :; }\n'
    printf 'error() { printf "ERROR: %%s\\n" "$1" >&2; exit 1; }\n'
    printf 'restart_services() { echo "RESTART_CALLED"; }\n'
    _extract_fn "_deploy_restore_user_data" "$script"
    printf '_deploy_restore_user_data "true"\n'
    printf 'echo "EXIT_OK"\n'
  } > "${tmp_dir}/sc_compose.sh"
  # stdin: "y" 恢复 + "n" 跳过重启
  output="$(printf 'y\nn\n' | bash "${tmp_dir}/sc_compose.sh" 2>&1)" || fail "场景 compose-path 失败：$output"
  assert_file "${r}/traefik/dynamic/localhost-services.yml"
  assert_contains "${r}/traefik/dynamic/localhost-services.yml" "c.c"
  info "  ✓ Compose 模式目标路径"

  [[ "$scenarios_passed" -eq "$scenarios_total" ]] || fail "restore 单元测试通过 ${scenarios_passed}/${scenarios_total}"
  info "  ✓ restore 边界条件测试通过（${scenarios_passed}/${scenarios_total}）"
  rm -rf "$tmp_dir"
}

run_integration_backup_restore_test() {
  local fixture home_dir runtime_dir bin_dir log_file backup_dir
  fixture="${TMP_DIR}/integration-backup-restore"
  home_dir="${TMP_DIR}/integration-home"
  runtime_dir="${TMP_DIR}/integration-runtime"
  bin_dir="${TMP_DIR}/integration-bin"
  log_file="${TMP_DIR}/integration.log"
  backup_dir="${home_dir}/.easygate.uninstall-backup"

  info "验证 uninstall→deploy→restore 完整流程"

  make_fixture "$fixture"
  make_mock_bin "$bin_dir" "$log_file"

  # ── 1. Compose 模式全流程 ──
  info "  ── Compose 模式 ──"
  mkdir -p "${runtime_dir}/compose" "${runtime_dir}/traefik/dynamic" \
    "${runtime_dir}/run" "${runtime_dir}/logs"
  touch "${runtime_dir}/compose/docker-compose.yml"
  touch "${runtime_dir}/compose/.env"
  echo "compose" > "${runtime_dir}/.mode"

  # 创建服务 YAML
  cat > "${runtime_dir}/traefik/dynamic/localhost-services.yml" <<'EOF'
http:
  routers:
    svc1:
      rule: Host(`svc1.example.com`)
      entryPoints:
        - web
      service: svc1
  services:
    svc1:
      loadBalancer:
        servers:
          - url: http://192.168.1.10:8080
EOF

  # uninstall → 备份
  HOME="$home_dir" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" uninstall || true

  assert_missing "$runtime_dir"
  assert_file "${backup_dir}/services.yml"
  assert_contains "${backup_dir}/services.yml" "svc1.example.com"
  info "  ✓ uninstall 备份成功"

  # 重建 runtime 目录（模拟重新安装）
  mkdir -p "${runtime_dir}/compose" "${runtime_dir}/run" "${runtime_dir}/logs" \
    "${runtime_dir}/traefik/dynamic" "${runtime_dir}/cloudflared"
  touch "${runtime_dir}/compose/docker-compose.yml"
  touch "${runtime_dir}/compose/.env"
  echo "compose" > "${runtime_dir}/.mode"
  # 准备 tunnel 凭据（deploy 需要）
  mkdir -p "${home_dir}/.cloudflared"
  touch "${home_dir}/.cloudflared/cert.pem"
  echo '{"source":"integration"}' > "${home_dir}/.cloudflared/0000.json"

  # CI 模式下 deploy（跳过交互式恢复，备份保留）
  EASYGATE_MOCK_LOG="$log_file" \
  EASYGATE_CI=true \
  EASYGATE_CLOUDFLARED_HOME="${home_dir}/.cloudflared" \
  EASYGATE_HOME="$runtime_dir" \
  HOME="$home_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" deploy --domain "example.test" --skip-route --no-install-cloudflared || true

  # CI 模式下 deploy 应触发 restore（但跳过交互），备份文件应仍存在
  assert_file "${backup_dir}/services.yml"

  # 手动将备份恢复到正确路径，模拟交互式选择的 Y 分支
  local target_yaml="${runtime_dir}/traefik/dynamic/localhost-services.yml"
  mkdir -p "$(dirname "$target_yaml")"
  cp "${backup_dir}/services.yml" "$target_yaml"
  assert_contains "$target_yaml" "svc1"
  assert_contains "$target_yaml" "svc1.example.com"
  info "  ✓ 手动恢复成功"

  rm -rf "$backup_dir" "$runtime_dir"

  # ── 2. Native 模式全流程 ──
  info "  ── Native 模式 ──"
  mkdir -p "${runtime_dir}/native/dynamic" "${runtime_dir}/run" "${runtime_dir}/logs"
  echo "native" > "${runtime_dir}/.mode"

  # 创建 native 服务 YAML
  mkdir -p "${runtime_dir}/native/dynamic"
  cat > "${runtime_dir}/native/dynamic/services.yml" <<'EOF_NATIVE'
http:
  routers:
    native-svc:
      rule: Host(`native.example.com`)
      entryPoints:
        - web
      service: native-svc
  services:
    native-svc:
      loadBalancer:
        servers:
          - url: http://127.0.0.1:9090
EOF_NATIVE

  # uninstall → 备份
  HOME="$home_dir" \
  EASYGATE_HOME="$runtime_dir" \
  PATH="${bin_dir}:$PATH" \
    bash "${fixture}/scripts/easygate" uninstall || true

  assert_missing "$runtime_dir"
  assert_file "${backup_dir}/services.yml"
  assert_contains "${backup_dir}/services.yml" "native-svc"
  assert_contains "${backup_dir}/services.yml" "native.example.com"
  info "  ✓ native 模式 uninstall 备份成功"

  rm -rf "$backup_dir"

  # ── 3. --no-restore 标志抑制恢复 ──
  info "  ── --no-restore 标志 ──"
  mkdir -p "${runtime_dir}/run" "${runtime_dir}/logs" "${runtime_dir}/compose" \
    "${runtime_dir}/traefik/dynamic"
  touch "${runtime_dir}/compose/docker-compose.yml"
  touch "${runtime_dir}/compose/.env"
  echo "compose" > "${runtime_dir}/.mode"

  # 创建备份
  mkdir -p "${backup_dir}"
  cat > "${backup_dir}/services.yml" <<'EOF_BAK'
http:
  routers:
    no-restore-svc:
      rule: Host(`no-restore.example.com`)
      entryPoints:
        - web
      service: no-restore-svc
  services:
    no-restore-svc:
      loadBalancer:
        servers:
          - url: http://192.168.1.99:9999
EOF_BAK

  # 在 deploy 中 --no-restore 应阻止恢复
  # 用 CI 模式确保 deploy 可以执行（不提示输入）
  echo "compose" > "${runtime_dir}/.mode"

  # 直接验证 _deploy_restore_user_data 在 do_restore=false 时跳过
  local check_script="${TMP_DIR}/no-restore-check.sh"
  {
    printf 'HOME="%s"\n' "$home_dir"
    printf 'EASYGATE_HOME="%s"\n' "${runtime_dir}"
    printf 'info() { printf "INFO: %%s\\n" "$1"; }\n'
    printf 'warn() { :; }\n'
    printf 'error() { printf "ERROR: %%s\\n" "$1" >&2; exit 1; }\n'
    printf '_service_yaml_path() { printf "%%s/traefik/dynamic/localhost-services.yml" "$EASYGATE_HOME"; }\n'
    printf 'restart_services() { echo "RESTART_CALLED"; }\n'
    printf '_deploy_restore_user_data() {\n'
    printf '  local do_restore="${1:-true}"\n'
    printf '  [[ "$do_restore" != "true" ]] && { echo "SKIPPED"; return 0; }\n'
    printf '  return 1\n'
    printf '}\n'
    printf '_deploy_restore_user_data "false"\n'
    printf 'echo "DONE"\n'
  } > "$check_script"

  local check_output
  check_output="$(bash "$check_script" 2>&1)" || fail "--no-restore 检查失败：$check_output"
  if ! echo "$check_output" | grep -q "SKIPPED"; then
    fail "--no-restore 应跳过恢复"
  fi
  # 备份文件应保留
  assert_file "${backup_dir}/services.yml"
  # 目标文件不应被创建
  [[ ! -f "${runtime_dir}/traefik/dynamic/localhost-services.yml" ]] \
    || fail "--no-restore 不应恢复文件"

  info "  ✓ --no-restore 正确跳过恢复"

  # 清理
  rm -rf "$backup_dir" "$runtime_dir" "$fixture" "${home_dir}/.cloudflared"
  info "  ✓ 集成测试通过"
}

trap 'rm -rf "$TMP_DIR"' EXIT

run_deploy_behavior_test
run_compose_deploy_blocks_native_test
run_native_deploy_behavior_test
run_native_deploy_blocks_compose_test
run_cleanup_behavior_test
run_cleanup_command_behavior_test
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
run_uninstall_backup_restore_test
run_ps_shows_all_services_test
run_local_only_test
run_restart_test
run_config_test
run_integration_backup_restore_test
run_restore_unit_test
run_service_helper_unit_test
run_systemd_name_regression_test
run_completion_test

info "行为测试通过"
