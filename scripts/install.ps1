param(
  [string]$Domain,
  [string]$Tunnel,
  [string]$Dashboard,
  [string]$Port,
  [string]$ApiPort,
  [string]$TestApiPort,
  [switch]$SkipRoute,
  [switch]$Demo,
  [switch]$LocalOnly,
  [switch]$NoInstallCloudflared,
  [switch]$NoInstallTraefik,
  [switch]$Purge
)

# Use $args for undeclared positional arguments to avoid
# ValueFromRemainingArguments + common parameter binding issues.
$CommandArgs = @($args)

$ErrorActionPreference = "Stop"

$Repo = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_REPO)) { "EasyIndie/EasyGate" } else { $env:EASYGATE_REPO }
$Ref = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_REF)) { "main" } else { $env:EASYGATE_REF }
$SourceUrl = if ([string]::IsNullOrWhiteSpace($env:EASYGATE_CLI_URL)) {
  "https://raw.githubusercontent.com/$Repo/$Ref/scripts/easygate.ps1"
}
else {
  $env:EASYGATE_CLI_URL
}

function Get-EasyGateHome {
  if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_HOME)) {
    return $env:EASYGATE_HOME
  }
  return Join-Path $env:LOCALAPPDATA "EasyGate"
}

$EasyGateHome = Get-EasyGateHome
$InstallDir = Join-Path $EasyGateHome "bin"
$Target = Join-Path $InstallDir "easygate.ps1"

$ForwardedOptions = @()
if ($PSBoundParameters.ContainsKey("Domain")) { $ForwardedOptions += @("-Domain", $Domain) }
if ($PSBoundParameters.ContainsKey("Tunnel")) { $ForwardedOptions += @("-Tunnel", $Tunnel) }
if ($PSBoundParameters.ContainsKey("Dashboard")) { $ForwardedOptions += @("-Dashboard", $Dashboard) }
if ($PSBoundParameters.ContainsKey("Port")) { $ForwardedOptions += @("-Port", $Port) }
if ($PSBoundParameters.ContainsKey("ApiPort")) { $ForwardedOptions += @("-ApiPort", $ApiPort) }
if ($PSBoundParameters.ContainsKey("TestApiPort")) { $ForwardedOptions += @("-TestApiPort", $TestApiPort) }
if ($SkipRoute) { $ForwardedOptions += "-SkipRoute" }
if ($Demo) { $ForwardedOptions += "-Demo" }
if ($LocalOnly) { $ForwardedOptions += "-LocalOnly" }
if ($NoInstallCloudflared) { $ForwardedOptions += "-NoInstallCloudflared" }
if ($NoInstallTraefik) { $ForwardedOptions += "-NoInstallTraefik" }
if ($Purge) { $ForwardedOptions += "-Purge" }
$CommandArgs = @($CommandArgs) + $ForwardedOptions

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (-not [string]::IsNullOrWhiteSpace($env:EASYGATE_LOCAL_CLI)) {
  $SourcePath = $env:EASYGATE_LOCAL_CLI
  Write-Host "[install] 从本地复制 CLI：$SourcePath"
  if (-not (Test-Path $SourcePath -PathType Leaf)) {
    Write-Error "[install] 找不到本地 CLI：$SourcePath"
    Write-Host "[install] 当前工作目录：$(Get-Location)"
    Write-Host "[install] github.workspace：$env:GITHUB_WORKSPACE"
    Write-Host "[install] runner.temp：$env:RUNNER_TEMP"
    exit 1
  }
  try {
    Copy-Item $SourcePath $Target -Force -ErrorAction Stop
  }
  catch {
    Write-Error "[install] 复制 CLI 失败：$_"
    exit 1
  }
}
else {
  Write-Host "[install] 从远程下载 CLI：$SourceUrl"
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl -OutFile $Target -ErrorAction Stop
  }
  catch {
    Write-Error "[install] 下载 CLI 失败：$_"
    exit 1
  }
}

Write-Host "[install] easygate.ps1 已安装到：$Target"
Write-Host "[install] 运行时目录：$EasyGateHome"
Write-Host "[install] 可选：将 $InstallDir 加入 PATH"
Write-Host "[install] DEBUG: CommandArgs.Count = $($CommandArgs.Count), items = [$($CommandArgs -join '|')]"

if ($CommandArgs.Count -gt 0 -and $CommandArgs[0] -ne '') {
  Write-Host "[install] 转发参数到 easygate.ps1：$($CommandArgs -join ' ')"
  & $Target @CommandArgs
  if ($null -eq $LASTEXITCODE) {
    exit 0
  }
  exit $LASTEXITCODE
}

Write-Host "[install] 部署示例：powershell -ExecutionPolicy Bypass -File `"$Target`" deploy -Domain example.com"
