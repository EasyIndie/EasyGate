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
if [[ "${1:-}" == "--version" ]]; then
  exit 0
fi
if [[ "${1:-}" == "tunnel" && "${2:-}" == "create" ]]; then
  exit 1
fi
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
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy-native.sh --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  )
  (
    cd "$fixture"
    HOME="$home" EASYGATE_HOME="$runtime" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
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

  info "验证 install.sh 可安装 standalone CLI"
  EASYGATE_HOME="$runtime" EASYGATE_LOCAL_CLI="${ROOT_DIR}/scripts/easygate" \
    bash "${ROOT_DIR}/scripts/install.sh" >/dev/null

  assert_file "${runtime}/bin/easygate"
  EASYGATE_HOME="$runtime" "${runtime}/bin/easygate" version | grep -q "easygate" || fail "安装后的 easygate 无法运行"

  # 验证写入的 PATH 行格式 —— 路径用引号包裹，$PATH 可展开
  # 在测试环境中不检查真实 rc 文件（HOME 可能被 mock），
  # 而是直接验证 install.sh 中 add_to_path 函数生成的行格式
  local add_to_path_body
  add_to_path_body="$(sed -n '/^add_to_path()/,/^}/p' "${ROOT_DIR}/scripts/install.sh")"
  if echo "$add_to_path_body" | grep -q 'export PATH='; then
    local export_line
    export_line="$(echo "$add_to_path_body" | grep 'export PATH=' | head -1)"
    # 必须包含单引号或双引号保护路径，且 $PATH 可展开
    if ! echo "$export_line" | grep -qE "export PATH=['\"].*['\"].*\\\$PATH"; then
      fail "install.sh add_to_path 生成的 PATH 行格式异常：${export_line}"
    fi
  else
    fail "install.sh 缺少 PATH 导出逻辑"
  fi
}

run_install_pipe_behavior_test() {
  local runtime="${TMP_DIR}/install-pipe-runtime"

  info "验证 install.sh 通过管道模式（curl | bash）可正常安装"
  # 通过 stdin 管道传递脚本，模拟 curl | bash 场景
  # 此时 BASH_SOURCE 为空，脚本不能依赖 lib.sh 或文件系统上下文
  EASYGATE_HOME="$runtime" EASYGATE_LOCAL_CLI="${ROOT_DIR}/scripts/easygate" \
    bash < "${ROOT_DIR}/scripts/install.sh" >/dev/null

  assert_file "${runtime}/bin/easygate"
  EASYGATE_HOME="$runtime" "${runtime}/bin/easygate" version | grep -q "easygate" || fail "管道安装后的 easygate 无法运行"

  # 验证管道模式下不会因缺失 lib.sh 或 BASH_SOURCE 而失败
  # （测试本身通过了上面的断言就证明没问题）
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

info "行为测试通过"
