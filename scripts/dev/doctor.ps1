[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Root
$tools = Get-Content (Join-Path $Root 'toolchain.json') | ConvertFrom-Json
$errors = 0
$warnings = 0

function Pass([string]$Message) { Write-Host "PASS  $Message" -ForegroundColor Green }
function Warn([string]$Message) { $script:warnings++; Write-Host "WARN  $Message" -ForegroundColor Yellow }
function Fail([string]$Message) { $script:errors++; Write-Host "FAIL  $Message" -ForegroundColor Red }

foreach ($command in @('git','gh','fvm','volta','node','npm','uv','just','docker','psql','gitleaks','supabase','firebase')) {
    $resolved = Get-Command $command -ErrorAction SilentlyContinue
    if ($resolved) { Pass "${command}: $($resolved.Source)" } else { Fail "$command missing - rerun scripts/bootstrap/bootstrap_windows.ps1" }
}

if (Get-Command node -ErrorAction SilentlyContinue) {
    $actualNode = (& node --version) -replace '^v',''
    if ($actualNode -eq $tools.node) { Pass "Node $actualNode matches toolchain.json" } else { Fail "Node $actualNode does not match $($tools.node) - run: volta install node@$($tools.node)" }
}

if (Get-Command fvm -ErrorAction SilentlyContinue) {
    $flutterOutput = & fvm flutter --version --machine 2>$null | ConvertFrom-Json
    if ($flutterOutput.frameworkVersion -eq $tools.flutter) { Pass "Flutter $($tools.flutter) matches .fvmrc" } else { Fail "FVM Flutter does not match $($tools.flutter)" }
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
    & docker info *> $null
    if ($LASTEXITCODE -eq 0) { Pass 'Docker runtime is reachable' } else { Warn 'Docker Desktop is installed but not running' }
}

foreach ($wrapper in @('android\gradle\wrapper\gradle-wrapper.jar','mobile_scanner_app\android\gradle\wrapper\gradle-wrapper.jar')) {
    if (Test-Path $wrapper) { Pass "$wrapper is present" } else { Fail "$wrapper is missing" }
}

if ($errors -gt 0) { Write-Error "Doctor failed: $errors blocker(s), $warnings warning(s)."; exit 1 }
Write-Host "Doctor passed with $warnings warning(s)."
