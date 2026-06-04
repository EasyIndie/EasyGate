$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("easygate-behavior-" + [System.Guid]::NewGuid().ToString("N"))

function Write-Info {
  param([string]$Message)
  Write-Host "[behavior] $Message" -ForegroundColor Blue
}

function Fail {
  param([string]$Message)
  Write-Host "[behavior] $Message" -ForegroundColor Red
  exit 1
}

function Assert-File {
  param([string]$Path)
  if (-not (Test-Path $Path -PathType Leaf)) {
    Fail "缺少文件：$Path"
  }
}

function Assert-Missing {
  param([string]$Path)
  if (Test-Path $Path) {
    Fail "不应存在：$Path"
  }
}

function Assert-Contains {
  param(
    [string]$Path,
    [string]$Text
  )
  $Content = Get-Content -Raw $Path
  if (-not $Content.Contains($Text)) {
    Fail "$Path 未包含：$Text"
  }
}

function New-Fixture {
  param([string]$Destination)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Copy-Item -Recurse (Join-Path $RootDir "scripts") $Destination
  Copy-Item -Recurse (Join-Path $RootDir "traefik") $Destination
  Copy-Item -Recurse (Join-Path $RootDir "cloudflared") $Destination
  Copy-Item (Join-Path $RootDir "docker-compose.yml") $Destination
  Copy-Item (Join-Path $RootDir "docker-compose.local.yml") $Destination
  Copy-Item (Join-Path $RootDir ".env.example") $Destination
}

function New-MockBin {
  param(
    [string]$BinDir,
    [string]$LogFile
  )
  New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
  "" | Set-Content -Path $LogFile

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("docker " + ($Args -join " "))
exit 0
'@ | Set-Content -Path (Join-Path $BinDir "docker.ps1") -Encoding UTF8

  @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
Add-Content -Path $env:EASYGATE_MOCK_LOG -Value ("cloudflared " + ($Args -join " "))
if ($Args.Count -ge 2 -and $Args[0] -eq "tunnel" -and $Args[1] -eq "create") {
  exit 1
}
exit 0
'@ | Set-Content -Path (Join-Path $BinDir "cloudflared.ps1") -Encoding UTF8

  if ($IsWindows) {
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$BinDir\docker.ps1"" %*" |
      Set-Content -Path (Join-Path $BinDir "docker.cmd") -Encoding ASCII
    "@pwsh -NoProfile -ExecutionPolicy Bypass -File ""$BinDir\cloudflared.ps1"" %*" |
      Set-Content -Path (Join-Path $BinDir "cloudflared.cmd") -Encoding ASCII
  }
  else {
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$BinDir/docker.ps1" "`$@"
"@ | Set-Content -Path (Join-Path $BinDir "docker") -Encoding UTF8
    @"
#!/usr/bin/env sh
pwsh -NoProfile -File "$BinDir/cloudflared.ps1" "`$@"
"@ | Set-Content -Path (Join-Path $BinDir "cloudflared") -Encoding UTF8
    chmod +x (Join-Path $BinDir "docker") (Join-Path $BinDir "cloudflared")
  }
}

function Invoke-WithMockPath {
  param(
    [string]$BinDir,
    [scriptblock]$Body
  )
  $OldPath = $env:PATH
  $Separator = [System.IO.Path]::PathSeparator
  $env:PATH = "$BinDir$Separator$OldPath"
  try {
    & $Body
  }
  finally {
    $env:PATH = $OldPath
  }
}

function Test-DeployBehavior {
  $Fixture = Join-Path $TempRoot "deploy-fixture"
  $HomeDir = Join-Path $TempRoot "home"
  $BinDir = Join-Path $TempRoot "bin"
  $LogFile = Join-Path $TempRoot "commands.log"

  Write-Info "验证 PowerShell 部署脚本可复用已有 tunnel"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir ".cloudflared") | Out-Null
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/cert.pem") -Value "cert"
  Set-Content -Path (Join-Path $HomeDir ".cloudflared/0000.json") -Value '{"source":"new"}'
  Set-Content -Path (Join-Path $Fixture "cloudflared/easygate-home.json") -Value '{"source":"old"}'

  $OldCloudflaredHome = $env:EASYGATE_CLOUDFLARED_HOME
  $env:EASYGATE_CLOUDFLARED_HOME = Join-Path $HomeDir ".cloudflared"
  try {
    Invoke-WithMockPath $BinDir {
      Push-Location $Fixture
      try {
        & ".\scripts\deploy.ps1" -Domain "example.test" -SkipRoute -Demo -NoInstallCloudflared
      }
      finally {
        Pop-Location
      }
    }
  }
  finally {
    $env:EASYGATE_CLOUDFLARED_HOME = $OldCloudflaredHome
  }

  Assert-Contains (Join-Path $Fixture ".env") "BASE_DOMAIN=example.test"
  Assert-Contains (Join-Path $Fixture "cloudflared/config.yml") 'hostname: "*.example.test"'
  Assert-Contains (Join-Path $Fixture "cloudflared/easygate-home.json") '"source":"new"'
  Assert-Contains $LogFile "cloudflared tunnel create easygate-home"
  Assert-Contains $LogFile "docker compose up -d"
  Assert-Contains $LogFile "docker compose --profile demo up -d demo-api demo-test-api"

  $LogText = Get-Content -Raw $LogFile
  if ($LogText.Contains("cloudflared tunnel route dns")) {
    Fail "-SkipRoute 仍调用了 tunnel route dns"
  }
}

function Test-CleanupBehavior {
  $Fixture = Join-Path $TempRoot "cleanup-fixture"
  $BinDir = Join-Path $TempRoot "cleanup-bin"
  $LogFile = Join-Path $TempRoot "cleanup-commands.log"

  Write-Info "验证 PowerShell 清理脚本删除范围"
  New-Fixture $Fixture
  New-MockBin $BinDir $LogFile

  New-Item -ItemType Directory -Force -Path (Join-Path $Fixture ".easygate") | Out-Null
  Set-Content -Path (Join-Path $Fixture ".env") -Value "env"
  Set-Content -Path (Join-Path $Fixture ".easygate/tool") -Value "tool"
  Set-Content -Path (Join-Path $Fixture "cloudflared/config.yml") -Value "config"
  Set-Content -Path (Join-Path $Fixture "cloudflared/easygate-home.json") -Value "secret"

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      & ".\scripts\cleanup.ps1"
    }
    finally {
      Pop-Location
    }
  }
  Assert-File (Join-Path $Fixture ".env")
  Assert-File (Join-Path $Fixture "cloudflared/config.yml")
  Assert-File (Join-Path $Fixture "cloudflared/easygate-home.json")

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      "no" | & ".\scripts\cleanup.ps1" -Purge
    }
    finally {
      Pop-Location
    }
  }
  Assert-File (Join-Path $Fixture ".env")
  Assert-File (Join-Path $Fixture "cloudflared/easygate-home.json")

  Invoke-WithMockPath $BinDir {
    Push-Location $Fixture
    try {
      "yes" | & ".\scripts\cleanup.ps1" -Purge
    }
    finally {
      Pop-Location
    }
  }
  Assert-Missing (Join-Path $Fixture ".env")
  Assert-Missing (Join-Path $Fixture ".easygate")
  Assert-Missing (Join-Path $Fixture "cloudflared/config.yml")
  Assert-Missing (Join-Path $Fixture "cloudflared/easygate-home.json")
}

try {
  New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
  Test-DeployBehavior
  Test-CleanupBehavior
  Write-Info "PowerShell 行为测试通过"
}
finally {
  if (Test-Path $TempRoot) {
    Remove-Item $TempRoot -Recurse -Force
  }
}
