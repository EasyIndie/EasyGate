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
    "compose ps --services --status running"*)
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
  local bin="${TMP_DIR}/bin"
  local log="${TMP_DIR}/commands.log"

  info "验证部署脚本可复用已有 tunnel 并覆盖只读凭据"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${home}/.cloudflared" "${fixture}/cloudflared"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf '{"source":"new"}\n' > "${home}/.cloudflared/0000.json"
  printf '{"source":"old"}\n' > "${fixture}/cloudflared/easygate-home.json"
  chmod 400 "${fixture}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    HOME="$home" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy.sh --domain example.test --skip-route --demo --no-install-cloudflared
  )
  (
    cd "$fixture"
    HOME="$home" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy.sh --domain example.test --skip-route --demo --no-install-cloudflared
  )

  assert_contains "${fixture}/.env" "BASE_DOMAIN=example.test"
  assert_contains "${fixture}/.env" "TRAEFIK_DASHBOARD_HOST=traefik.example.test"
  assert_contains "${fixture}/cloudflared/config.yml" 'hostname: "*.example.test"'
  assert_contains "${fixture}/cloudflared/easygate-home.json" '"source":"new"'
  assert_contains "$log" "cloudflared tunnel create easygate-home"
  assert_contains "$log" "docker compose up -d"
  compose_calls="$(grep -Fc -- "docker compose" "$log")"
  [[ "$compose_calls" -ge 6 ]] || fail "重复启用 --demo 后 docker compose 调用次数不足：${compose_calls}"

  if grep -Fq "cloudflared tunnel route dns" "$log"; then
    fail "--skip-route 仍调用了 tunnel route dns"
  fi
}

run_compose_deploy_blocks_native_test() {
  local fixture="${TMP_DIR}/compose-blocks-native-fixture"
  local home="${TMP_DIR}/compose-blocks-native-home"
  local bin="${TMP_DIR}/compose-blocks-native-bin"
  local log="${TMP_DIR}/compose-blocks-native.log"

  info "验证原生模式运行时 Docker Compose 部署会被阻止"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${home}/.cloudflared" "${fixture}/.easygate/run"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf '%s\n' "$$" > "${fixture}/.easygate/run/native-traefik.pid"

  if (
    cd "$fixture"
    HOME="$home" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
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

  info "验证清理脚本默认保留配置，purge 仅在确认后删除本地生成文件"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${fixture}/.easygate" "${fixture}/cloudflared"
  printf 'env\n' > "${fixture}/.env"
  printf 'bin\n' > "${fixture}/.easygate/tool"
  printf 'config\n' > "${fixture}/cloudflared/config.yml"
  printf 'secret\n' > "${fixture}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" bash scripts/cleanup.sh
  )
  assert_file "${fixture}/.env"
  assert_file "${fixture}/cloudflared/config.yml"
  assert_file "${fixture}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_CONFIRM_PURGE="no" bash scripts/cleanup.sh --purge
  )
  assert_file "${fixture}/.env"
  assert_file "${fixture}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_CONFIRM_PURGE="yes" bash scripts/cleanup.sh --purge
  )
  assert_missing "${fixture}/.env"
  assert_missing "${fixture}/.easygate"
  assert_missing "${fixture}/cloudflared/config.yml"
  assert_missing "${fixture}/cloudflared/easygate-home.json"
}

run_native_deploy_behavior_test() {
  local fixture="${TMP_DIR}/native-deploy-fixture"
  local home="${TMP_DIR}/native-home"
  local bin="${TMP_DIR}/native-bin"
  local log="${TMP_DIR}/native-commands.log"

  info "验证原生部署脚本生成 file provider 配置并启动本地进程"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${home}/.cloudflared" "${fixture}/cloudflared"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"
  printf '{"source":"native"}\n' > "${home}/.cloudflared/0000.json"

  (
    cd "$fixture"
    HOME="$home" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy-native.sh --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  )
  (
    cd "$fixture"
    HOME="$home" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" \
      bash scripts/deploy-native.sh --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  )

  assert_contains "${fixture}/.env" "EASYGATE_DEPLOY_MODE=native"
  assert_contains "${fixture}/.easygate/native/traefik.yml" "providers:"
  assert_contains "${fixture}/.easygate/native/traefik.yml" ".easygate/native/dynamic"
  assert_contains "${fixture}/.easygate/native/dynamic/services.yml" "service: api@internal"
  assert_contains "${fixture}/cloudflared/config.native.yml" "service: http://127.0.0.1:18080"
  assert_contains "$log" "traefik --configFile="
  assert_contains "$log" ".easygate/native/traefik.yml"
  assert_contains "$log" "cloudflared tunnel --config"
  assert_contains "$log" "cloudflared/config.native.yml run"

  if grep -Fq "docker:" "${fixture}/.easygate/native/traefik.yml"; then
    fail "原生 Traefik 配置不应启用 docker provider"
  fi
  if grep -Fq "cloudflared tunnel route dns" "$log"; then
    fail "原生部署 --skip-route 仍调用了 tunnel route dns"
  fi
}

run_native_deploy_blocks_compose_test() {
  local fixture="${TMP_DIR}/native-blocks-compose-fixture"
  local home="${TMP_DIR}/native-blocks-compose-home"
  local bin="${TMP_DIR}/native-blocks-compose-bin"
  local log="${TMP_DIR}/native-blocks-compose.log"

  info "验证 Docker Compose 模式运行时原生部署会被阻止"
  make_fixture "$fixture"
  make_mock_bin "$bin" "$log"

  mkdir -p "${home}/.cloudflared"
  printf 'cert\n' > "${home}/.cloudflared/cert.pem"

  if (
    cd "$fixture"
    HOME="$home" EASYGATE_CLOUDFLARED_HOME="${home}/.cloudflared" PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" EASYGATE_MOCK_COMPOSE_RUNNING=true \
      bash scripts/deploy-native.sh --domain example.test --skip-route --no-install-cloudflared --no-install-traefik
  ); then
    fail "Docker Compose 模式运行时 deploy-native.sh 不应继续部署"
  fi

  assert_missing "${fixture}/.easygate/native/traefik.yml"
}

run_native_cleanup_behavior_test() {
  local fixture="${TMP_DIR}/native-cleanup-fixture"

  info "验证原生清理脚本默认保留配置，purge 删除原生运行配置"
  make_fixture "$fixture"

  mkdir -p "${fixture}/.easygate/native" "${fixture}/.easygate/run" "${fixture}/.easygate/logs" "${fixture}/cloudflared"
  printf 'traefik\n' > "${fixture}/.easygate/native/traefik.yml"
  printf 'pid\n' > "${fixture}/.easygate/run/native-traefik.pid"
  printf 'log\n' > "${fixture}/.easygate/logs/native-traefik.log"
  printf 'cloudflared\n' > "${fixture}/cloudflared/config.native.yml"

  (
    cd "$fixture"
    bash scripts/cleanup-native.sh
  )
  assert_file "${fixture}/.easygate/native/traefik.yml"
  assert_file "${fixture}/cloudflared/config.native.yml"
  assert_missing "${fixture}/.easygate/run/native-traefik.pid"

  (
    cd "$fixture"
    bash scripts/cleanup-native.sh --purge
  )
  assert_missing "${fixture}/.easygate/native"
  assert_missing "${fixture}/.easygate/run"
  assert_missing "${fixture}/.easygate/logs"
  assert_missing "${fixture}/cloudflared/config.native.yml"
}

trap 'rm -rf "$TMP_DIR"' EXIT

run_deploy_behavior_test
run_compose_deploy_blocks_native_test
run_native_deploy_behavior_test
run_native_deploy_blocks_compose_test
run_cleanup_behavior_test
run_native_cleanup_behavior_test

info "行为测试通过"
