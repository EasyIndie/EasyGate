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
  grep -Fq "$text" "$path" || fail "$path 未包含：$text"
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

  chmod +x "${bin_dir}/docker" "${bin_dir}/cloudflared"
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

  assert_contains "${fixture}/.env" "BASE_DOMAIN=example.test"
  assert_contains "${fixture}/.env" "TRAEFIK_DASHBOARD_HOST=traefik.example.test"
  assert_contains "${fixture}/cloudflared/config.yml" 'hostname: "*.example.test"'
  assert_contains "${fixture}/cloudflared/easygate-home.json" '"source":"new"'
  assert_contains "$log" "cloudflared tunnel create easygate-home"
  assert_contains "$log" "docker compose up -d"
  assert_contains "$log" "docker compose --profile demo up -d demo-api demo-test-api"

  if grep -Fq "cloudflared tunnel route dns" "$log"; then
    fail "--skip-route 仍调用了 tunnel route dns"
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
    printf 'no\n' | PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" bash scripts/cleanup.sh --purge
  )
  assert_file "${fixture}/.env"
  assert_file "${fixture}/cloudflared/easygate-home.json"

  (
    cd "$fixture"
    printf 'yes\n' | PATH="${bin}:$PATH" EASYGATE_MOCK_LOG="$log" bash scripts/cleanup.sh --purge
  )
  assert_missing "${fixture}/.env"
  assert_missing "${fixture}/.easygate"
  assert_missing "${fixture}/cloudflared/config.yml"
  assert_missing "${fixture}/cloudflared/easygate-home.json"
}

trap 'rm -rf "$TMP_DIR"' EXIT

run_deploy_behavior_test
run_cleanup_behavior_test

info "行为测试通过"
