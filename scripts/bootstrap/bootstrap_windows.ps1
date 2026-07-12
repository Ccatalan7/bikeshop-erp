[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Root

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'WinGet is required. Install Microsoft App Installer, then rerun this script.'
}

$packages = @(
    'Git.Git',
    'GitHub.cli',
    'Volta.Volta',
    'astral-sh.uv',
    'Casey.Just',
    'Gitleaks.Gitleaks',
    'Docker.DockerDesktop',
    'PostgreSQL.PostgreSQL.17',
    'Microsoft.PowerShell',
    'Google.AndroidStudio'
)

foreach ($package in $packages) {
    winget install --id $package --exact --accept-package-agreements --accept-source-agreements --silent
}

$tools = Get-Content (Join-Path $Root 'toolchain.json') | ConvertFrom-Json
$flutterRoot = Join-Path $HOME ".fvm\versions\$($tools.flutter)"

if (-not (Test-Path (Join-Path $flutterRoot 'bin\flutter.bat'))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $flutterRoot) | Out-Null
    git clone --depth 1 --branch $tools.flutter https://github.com/flutter/flutter.git $flutterRoot
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$requiredPaths = @(
    (Join-Path $flutterRoot 'bin'),
    (Join-Path $HOME '.volta\bin'),
    (Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin')
)
foreach ($path in $requiredPaths) {
    if ($userPath -notlike "*$path*") { $userPath = "$path;$userPath" }
    if ($env:Path -notlike "*$path*") { $env:Path = "$path;$env:Path" }
}
[Environment]::SetEnvironmentVariable('Path', $userPath, 'User')

& (Join-Path $flutterRoot 'bin\dart.bat') pub global activate fvm $tools.fvm
volta install "node@$($tools.node)" "npm@$($tools.npm)"
fvm use $tools.flutter --force
npm ci
uv sync --project tools/invoice-parser-service

& (Join-Path $Root 'scripts\dev\doctor.ps1')
