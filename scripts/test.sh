#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

info() {
  printf '\033[1;34m[test]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33m[test]\033[0m %s\n' "$1"
}

fail() {
  printf '\033[1;31m[test]\033[0m %s\n' "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "缺少文件：${path}"
}

info "检查关键文件"
require_file ".env.example"
require_file ".github/dependabot.yml"
require_file ".github/workflows/ci.yml"
require_file ".github/workflows/release.yml"
require_file "docker-compose.yml"
require_file "docker-compose.local.yml"
require_file "traefik/traefik.yml"
require_file "traefik/dynamic/localhost-services.yml"
require_file "cloudflared/config.yml.example"
require_file "scripts/test.sh"
require_file "scripts/test.ps1"
require_file "scripts/cleanup.sh"
require_file "scripts/cleanup.ps1"
require_file "scripts/deploy.sh"
require_file "scripts/deploy.ps1"
require_file "scripts/deploy-native.sh"
require_file "scripts/deploy-native.ps1"
require_file "scripts/uninstall.sh"
require_file "scripts/uninstall.ps1"
require_file "scripts/local-acceptance.sh"
require_file "scripts/local-acceptance.ps1"
require_file "scripts/local-acceptance-native.sh"
require_file "scripts/local-acceptance-native.ps1"
require_file "scripts/behavior-test.sh"
require_file "scripts/behavior-test.ps1"
require_file "scripts/cleanup-native.sh"
require_file "scripts/cleanup-native.ps1"
require_file "scripts/native-demo-server.py"
require_file "scripts/compose.sh"
require_file "scripts/easygate"
require_file "scripts/easygate.ps1"
require_file "scripts/install.sh"
require_file "scripts/install.ps1"

info "检查旧项目名残留"
if grep -R "[E]asyTLS\|[e]asytls\|[E]ASYTLS" \
  --exclude-dir=.git \
  --exclude=prompts.txt \
  . >/dev/null 2>&1; then
  fail "发现旧项目名残留"
fi

info "检查 Bash 脚本语法"
bash -n scripts/test.sh
bash -n scripts/cleanup.sh
bash -n scripts/cleanup-native.sh
bash -n scripts/compose.sh
bash -n scripts/easygate
bash -n scripts/install.sh
bash -n scripts/deploy.sh
bash -n scripts/deploy-native.sh
bash -n scripts/uninstall.sh
bash -n scripts/local-acceptance.sh
bash -n scripts/local-acceptance-native.sh
bash -n scripts/behavior-test.sh

if command -v shellcheck >/dev/null 2>&1; then
  info "使用 ShellCheck 检查 Bash 脚本"
  if ! shellcheck \
    scripts/test.sh \
    scripts/cleanup.sh \
    scripts/cleanup-native.sh \
    scripts/compose.sh \
    scripts/easygate \
    scripts/install.sh \
    scripts/deploy.sh \
    scripts/deploy-native.sh \
    scripts/uninstall.sh \
    scripts/local-acceptance.sh \
    scripts/local-acceptance-native.sh \
    scripts/behavior-test.sh; then
    warn "ShellCheck 发现问题，请后续修复；当前不阻断基础 CI"
  fi
else
  warn "未找到 shellcheck，跳过 Bash lint"
fi

info "检查 .env.example 默认值"
grep -q "^BASE_DOMAIN=example.com$" .env.example || fail ".env.example 缺少 BASE_DOMAIN 默认值"
grep -q "^TRAEFIK_HTTP_PORT=18080$" .env.example || fail ".env.example 缺少 TRAEFIK_HTTP_PORT 默认值"
grep -q "^TRAEFIK_DASHBOARD_HOST=traefik.example.com$" .env.example || fail ".env.example 缺少 dashboard host 默认值"

info "检查 Traefik 网络命名"
grep -q "easygate-proxy" docker-compose.yml || fail "docker-compose.yml 缺少 easygate-proxy"
grep -q "network: easygate-proxy" traefik/traefik.yml || fail "traefik.yml 未指向 easygate-proxy"
grep -q "traefik.docker.network=easygate-proxy" examples/docker-service.compose.yml || fail "示例服务未使用 easygate-proxy"

info "检查 cloudflared 自动安装入口"
grep -q -- "--no-install-cloudflared" scripts/deploy.sh || fail "deploy.sh 缺少 cloudflared 自动安装开关"
grep -q "EASYGATE_CLOUDFLARED_HOME" scripts/lib.sh || fail "lib.sh 缺少 cloudflared home 覆盖入口"
grep -q "EASYGATE_HOME" scripts/deploy.sh || fail "deploy.sh 缺少 EASYGATE_HOME 运行时目录"
grep -q "EASYGATE_HOME" scripts/easygate || fail "easygate CLI 缺少 EASYGATE_HOME 运行时目录"
grep -q "EASYGATE_LOCAL_CLI" scripts/install.sh || fail "install.sh 缺少本地 CLI 安装测试入口"
grep -q "EASYGATE_HOME" scripts/easygate.ps1 || fail "easygate.ps1 缺少 EASYGATE_HOME 运行时目录"
grep -q "EASYGATE_LOCAL_CLI" scripts/install.ps1 || fail "install.ps1 缺少本地 CLI 安装测试入口"
grep -q "EASYGATE_CLOUDFLARED_HOME" scripts/deploy.ps1 || fail "deploy.ps1 缺少 cloudflared home 覆盖入口"
grep -q "cloudflared-linux-" scripts/lib.sh || fail "lib.sh 缺少 Linux cloudflared 下载逻辑"
grep -q "cloudflared-darwin-" scripts/lib.sh || fail "lib.sh 缺少 macOS cloudflared 下载逻辑"
grep -q "cloudflared-windows-" scripts/deploy.ps1 || fail "deploy.ps1 缺少 Windows cloudflared 下载逻辑"
grep -q "cloudflared-windows-" scripts/easygate.ps1 || fail "easygate.ps1 缺少 Windows cloudflared 下载逻辑"
# Also verify the standalone CLI has its own copies:
grep -q "cloudflared-linux-" scripts/easygate || fail "easygate CLI 缺少 Linux cloudflared 下载逻辑"
grep -q "cloudflared-darwin-" scripts/easygate || fail "easygate CLI 缺少 macOS cloudflared 下载逻辑"

info "检查原生模式入口"
grep -q -- "--local-only" scripts/deploy-native.sh || fail "deploy-native.sh 缺少 local-only 验收入口"
grep -q "traefik_v" scripts/lib.sh || fail "lib.sh 缺少 Traefik 下载逻辑"
grep -q "traefik_v" scripts/easygate || fail "easygate CLI 缺少 Traefik 下载逻辑"
grep -q "config.native.yml" scripts/deploy-native.sh || fail "deploy-native.sh 缺少原生 cloudflared 配置"
grep -q "providers:" scripts/deploy-native.sh || fail "deploy-native.sh 缺少原生 Traefik 配置生成"
grep -q "EASYGATE_CLI" scripts/local-acceptance-native.ps1 || fail "local-acceptance-native.ps1 缺少独立 CLI 覆盖入口"
grep -q "config.native.yml" scripts/deploy-native.ps1 || fail "deploy-native.ps1 缺少原生 cloudflared 配置"
grep -q "assert_no_native_deployment" scripts/deploy.sh || fail "deploy.sh 缺少原生模式互斥检查"
grep -q "assert_no_compose_deployment" scripts/deploy-native.sh || fail "deploy-native.sh 缺少 Compose 模式互斥检查"

info "检查 GitHub Actions Node 24 兼容配置"
grep -q "FORCE_JAVASCRIPT_ACTIONS_TO_NODE24" .github/workflows/ci.yml || fail "CI 缺少 Node 24 opt-in"
grep -q "actions/checkout@v6" .github/workflows/ci.yml || fail "CI 未使用支持 Node 24 的 checkout 版本"
grep -q "SHA256SUMS" .github/workflows/release.yml || fail "Release workflow 缺少校验和产物"

info "检查文档链接文件是否存在"
while IFS=$'\t' read -r source link; do
  [[ -n "${source}" && -n "${link}" ]] || continue
  case "$link" in
    http://*|https://*|mailto:*|\#*|"") continue ;;
  esac

  path="${link%%#*}"
  [[ "$path" == *.md ]] || continue

  if [[ "$path" == docs/* ]]; then
    target="$path"
  else
    target="$(dirname "$source")/$path"
  fi
  [[ -f "$target" ]] || fail "文档链接指向不存在的文件：${source} -> ${link}"
done < <(perl -ne 'while (/\[[^\]]+\]\(([^)]+)\)/g) { print "$ARGV\t$1\n" }' README.md docs/*.md | sort -u)

info "运行 Bash 行为测试"
bash scripts/behavior-test.sh

if command -v ruby >/dev/null 2>&1; then
  info "使用 Ruby 检查 YAML 语法"
  ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_file(f); puts "ok #{f}" }' \
    docker-compose.yml \
    docker-compose.local.yml \
    .github/dependabot.yml \
    .github/workflows/ci.yml \
    .github/workflows/release.yml \
    traefik/traefik.yml \
    traefik/dynamic/localhost-services.yml \
    cloudflared/config.yml.example \
    examples/docker-service.compose.yml
else
  warn "未找到 ruby，跳过 YAML 解析检查"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  info "检查 Docker Compose 配置"
  docker compose --env-file .env.example config >/dev/null
else
  warn "未找到 docker compose，跳过 Compose 配置检查"
fi

info "全部检查通过"
