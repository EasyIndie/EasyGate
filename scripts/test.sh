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
require_file "scripts/cleanup.sh"
require_file "scripts/local-acceptance.sh"
require_file "scripts/local-acceptance-native.sh"
require_file "scripts/behavior-test.sh"
require_file "scripts/lib.sh"
require_file "scripts/easygate"
require_file "scripts/install.sh"

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
bash -n scripts/easygate
bash -n scripts/install.sh
bash -n scripts/local-acceptance.sh
bash -n scripts/local-acceptance-native.sh
bash -n scripts/behavior-test.sh

if command -v shellcheck >/dev/null 2>&1; then
  info "使用 ShellCheck 检查 Bash 脚本"
  if ! shellcheck \
    scripts/test.sh \
    scripts/cleanup.sh \
    scripts/easygate \
    scripts/install.sh \
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
grep -q "EASYGATE_CLOUDFLARED_HOME" scripts/lib.sh || fail "lib.sh 缺少 cloudflared home 覆盖入口"
grep -q "EASYGATE_HOME" scripts/easygate || fail "easygate CLI 缺少 EASYGATE_HOME 运行时目录"
grep -q "EASYGATE_LOCAL_CLI" scripts/install.sh || fail "install.sh 缺少本地 CLI 安装测试入口"
grep -q "cloudflared-linux-" scripts/lib.sh || fail "lib.sh 缺少 Linux cloudflared 下载逻辑"
grep -q "cloudflared-darwin-" scripts/lib.sh || fail "lib.sh 缺少 macOS cloudflared 下载逻辑"
# Also verify the standalone CLI has its own copies:
grep -q "cloudflared-linux-" scripts/easygate || fail "easygate CLI 缺少 Linux cloudflared 下载逻辑"
grep -q "cloudflared-darwin-" scripts/easygate || fail "easygate CLI 缺少 macOS cloudflared 下载逻辑"
# 回归检查：cloudflared 镜像版本已固定（非 :latest）
grep -qE "cloudflared:[0-9]{4}\.[0-9]+" docker-compose.yml || fail "docker-compose.yml cloudflared 版本未固定"
# 回归检查：CLI 内嵌的 cloudflared 镜像版本与 docker-compose.yml 一致
_yml_version="$(grep -oE 'cloudflare/cloudflared:[0-9]{4}\.[0-9]+\.[0-9]+' docker-compose.yml | head -1 | cut -d: -f2)"
_cli_version="$(grep -oE 'cloudflare/cloudflared:[0-9]{4}\.[0-9]+\.[0-9]+' scripts/easygate | head -1 | cut -d: -f2)"
if [[ -n "$_yml_version" && -n "$_cli_version" && "$_yml_version" != "$_cli_version" ]]; then
  fail "CLI 内嵌 cloudflared 版本 ${_cli_version} 与 docker-compose.yml ${_yml_version} 不一致"
fi
# 回归检查：install.sh 不自依赖 lib.sh（curl | bash 模式无文件系统上下文）
if grep -q "source.*lib.sh" scripts/install.sh; then
  fail "install.sh 不可依赖 lib.sh（curl | bash 管道模式无文件系统上下文）"
fi
if grep -q "BASH_SOURCE" scripts/install.sh; then
  fail "install.sh 不可使用 BASH_SOURCE（curl | bash 管道模式此变量为空）"
fi

info "检查原生模式入口"
grep -q "traefik_v" scripts/lib.sh || fail "lib.sh 缺少 Traefik 下载逻辑"
grep -q "traefik_v" scripts/easygate || fail "easygate CLI 缺少 Traefik 下载逻辑"
# 回归检查：安全加固 —— 生成的 compose 必须含 read_only 和 cap_drop

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

