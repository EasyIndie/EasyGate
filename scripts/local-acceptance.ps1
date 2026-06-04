$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Strict = $env:EASYGATE_ACCEPTANCE_STRICT -eq "true"
$ComposeArgs = @("compose", "-f", "docker-compose.local.yml", "--env-file", ".env")
$TraefikHttpPort = "18080"

function Write-Info {
  param([string]$Message)
  Write-Host "[acceptance] $Message" -ForegroundColor Blue
}

function Write-Warn {
  param([string]$Message)
  Write-Host "[acceptance] $Message" -ForegroundColor Yellow
}

function Fail {
  param([string]$Message)
  Write-Host "[acceptance] $Message" -ForegroundColor Red
  exit 1
}

function Skip-Or-Fail {
  param([string]$Message)
  if ($Strict) {
    Fail $Message
  }
  Write-Warn "$Message，跳过本地路由验收"
  exit 0
}

function Compose {
  param([string[]]$Args)
  docker @ComposeArgs @Args
}

function Request-Text {
  param([string]$HostName)
  Invoke-WebRequest -Uri "http://127.0.0.1:$TraefikHttpPort" -Headers @{ Host = $HostName } -UseBasicParsing
}

function Cleanup {
  try {
    Compose @("down", "--remove-orphans") | Out-Null
  }
  catch {
  }
}

Set-Location $RootDir

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Skip-Or-Fail "未找到 docker"
}

try {
  docker compose version | Out-Null
}
catch {
  Skip-Or-Fail "未找到 docker compose"
}

try {
  docker info | Out-Null
}
catch {
  Skip-Or-Fail "Docker daemon 不可用"
}

if (-not (Test-Path ".env")) {
  Copy-Item ".env.example" ".env"
  Write-Info "已从 .env.example 生成本机验收用 .env"
}

Get-Content ".env" | ForEach-Object {
  $Line = $_.Trim()
  if ($Line -eq "" -or $Line.StartsWith("#")) {
    return
  }
  $Parts = $Line.Split("=", 2)
  if ($Parts.Length -eq 2 -and $Parts[0] -eq "TRAEFIK_HTTP_PORT" -and $Parts[1] -ne "") {
    $script:TraefikHttpPort = $Parts[1]
  }
}

try {
  Write-Info "启动本机验收栈"
  Compose @("up", "-d") | Out-Null

  Write-Info "等待 Traefik 就绪"
  $Ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $Response = Request-Text "api.example.com"
      if ($Response.Content -match "Hostname:") {
        $Ready = $true
        break
      }
    }
    catch {
      Start-Sleep -Seconds 1
    }
  }

  if (-not $Ready) {
    Fail "Traefik 未在预期时间内就绪"
  }

  Write-Info "验证生产 demo 路由"
  $Api = Request-Text "api.example.com"
  if ($Api.Content -notmatch "Hostname:") {
    Fail "api.example.com 未返回 whoami 响应"
  }

  Write-Info "验证测试 demo 路由"
  $TestApi = Request-Text "test-api.example.com"
  if ($TestApi.Content -notmatch "Hostname:") {
    Fail "test-api.example.com 未返回 whoami 响应"
  }

  Write-Info "验证未配置域名返回 404"
  try {
    Invoke-WebRequest -Uri "http://127.0.0.1:$TraefikHttpPort" -Headers @{ Host = "missing.example.com" } -UseBasicParsing | Out-Null
    Fail "missing.example.com 预期 404，实际请求成功"
  }
  catch {
    $StatusCode = $_.Exception.Response.StatusCode.value__
    if ($StatusCode -ne 404) {
      Fail "missing.example.com 预期 404，实际 ${StatusCode}"
    }
  }

  Write-Info "本机路由验收通过"
}
finally {
  Cleanup
}
