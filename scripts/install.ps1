param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs,
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

Write-Host "[install] ✅ 安装完成"
Write-Host "   CLI 路径：$Target"
Write-Host "   运行时目录：$EasyGateHome"
Write-Host ""
Write-Host "   添加到 PATH 以便直接使用 easygate.ps1 命令："
Write-Host "   `$env:Path = `"$InstallDir;`$env:Path`""
Write-Host "   或系统设置 → 环境变量 → PATH 添加：$InstallDir"
Write-Host ""

if ($CommandArgs.Count -gt 0 -and $CommandArgs[0] -ne '') {
  & $Target @CommandArgs
  if ($null -eq $LASTEXITCODE) {
    exit 0
  }
  exit $LASTEXITCODE
}

Write-Host "   直接部署："
Write-Host "   powershell -ExecutionPolicy Bypass -File `"$Target`" deploy -Domain example.com"
Write-Host "   或先加入 PATH 后："
Write-Host "   easygate.ps1 deploy -Domain example.com"
