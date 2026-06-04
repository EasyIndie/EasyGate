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
require_file "scripts/uninstall.sh"
require_file "scripts/uninstall.ps1"
require_file "scripts/local-acceptance.sh"
require_file "scripts/local-acceptance.ps1"

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
bash -n scripts/deploy.sh
bash -n scripts/uninstall.sh
bash -n scripts/local-acceptance.sh

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
grep -q "cloudflared-linux-" scripts/deploy.sh || fail "deploy.sh 缺少 Linux cloudflared 下载逻辑"
grep -q "cloudflared-darwin-" scripts/deploy.sh || fail "deploy.sh 缺少 macOS cloudflared 下载逻辑"
grep -q "cloudflared-windows-" scripts/deploy.ps1 || fail "deploy.ps1 缺少 Windows cloudflared 下载逻辑"

info "检查文档链接文件是否存在"
while IFS= read -r link; do
  [[ -f "${link}" ]] || fail "文档链接指向不存在的文件：${link}"
done < <(grep -Roh 'docs/[A-Za-z0-9._/-]*\.md' README.md docs | sort -u)

if command -v ruby >/dev/null 2>&1; then
  info "使用 Ruby 检查 YAML 语法"
  ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_file(f); puts "ok #{f}" }' \
    docker-compose.yml \
    docker-compose.local.yml \
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

if command -v pwsh >/dev/null 2>&1; then
  info "检查 PowerShell 脚本语法"
  pwsh -NoProfile -Command '$errors = $null; $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw scripts/test.ps1), [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }'
  pwsh -NoProfile -Command '$errors = $null; $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw scripts/cleanup.ps1), [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }'
  pwsh -NoProfile -Command '$errors = $null; $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw scripts/deploy.ps1), [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }'
  pwsh -NoProfile -Command '$errors = $null; $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw scripts/uninstall.ps1), [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }'
  pwsh -NoProfile -Command '$errors = $null; $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw scripts/local-acceptance.ps1), [ref]$errors); if ($errors) { $errors | Format-List; exit 1 }'
else
  warn "未找到 pwsh，跳过 PowerShell 语法检查"
fi

info "全部检查通过"
