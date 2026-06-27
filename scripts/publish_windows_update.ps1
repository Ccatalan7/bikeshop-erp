param(
    [string]$Message = "",
    [switch]$NoWait,
    [switch]$RequireConfirmation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "[windows-update] $Message"
}

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Get-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Format-Elapsed {
    param([TimeSpan]$Elapsed)

    if ($Elapsed.TotalHours -ge 1) {
        return '{0:00}:{1:00}:{2:00}' -f [int]$Elapsed.TotalHours, $Elapsed.Minutes, $Elapsed.Seconds
    }

    return '{0:00}:{1:00}' -f $Elapsed.Minutes, $Elapsed.Seconds
}

Require-Command git
Require-Command gh

$repoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $repoRoot

$branch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'Could not determine the current Git branch.'
}

Write-Step 'Staging all Source Control changes'
git add -A

$stagedFiles = @(git diff --cached --name-only)

if ($stagedFiles.Count -eq 0) {
    Write-Host 'No Source Control changes found.'
    Write-Host 'Make changes first, then run this task again.'
    Write-Host ''
    Write-Host 'Current status:'
    git status --short
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Message)) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $Message = "chore: publish Windows update $timestamp"
}

Write-Step "Current branch: $branch"
Write-Host "Commit message: $Message"
Write-Host "Files to commit and publish:"
foreach ($file in $stagedFiles) {
    Write-Host "  $file"
}

if ($RequireConfirmation) {
    $confirmation = Read-Host "Type YES to commit, push, and publish a Windows release from branch '$branch'"
    if ($confirmation -ne 'YES') {
        Write-Host 'Cancelled.'
        exit 1
    }
}

Write-Step 'Committing staged changes'
git commit -m $Message

$headSha = (git rev-parse HEAD).Trim()

Write-Step "Pushing $branch"
git push origin $branch

Write-Step 'Triggering GitHub Actions Windows release workflow'
gh workflow run windows-release.yml --repo Ccatalan7/bikeshop-erp --ref $branch
$buildTimer = [System.Diagnostics.Stopwatch]::StartNew()

Start-Sleep -Seconds 6

$runsJson = gh run list `
    --repo Ccatalan7/bikeshop-erp `
    --workflow "Build Windows Desktop Release" `
    --branch $branch `
    --limit 10 `
    --json databaseId,headSha,status,conclusion,url,createdAt

$parsedRuns = $runsJson | ConvertFrom-Json
$run = $null
foreach ($candidate in $parsedRuns) {
    if ((Get-ObjectProperty $candidate 'headSha') -eq $headSha) {
        $run = $candidate
        break
    }
}

if (-not $run) {
    Write-Host 'Workflow was triggered, but the run was not found yet.'
    Write-Host 'Check GitHub Actions for the latest "Build Windows Desktop Release" run.'
    exit 0
}

$runId = Get-ObjectProperty $run 'databaseId'
$runUrl = Get-ObjectProperty $run 'url'
if ([string]::IsNullOrWhiteSpace([string]$runId)) {
    throw 'Workflow run was found, but its databaseId was missing.'
}

Write-Host "Workflow run: $runUrl"

if ($NoWait) {
    Write-Host 'Not waiting for completion because -NoWait was passed.'
    exit 0
}

Write-Step 'Waiting for Windows release build to finish'
do {
    Start-Sleep -Seconds 30
    $viewJson = gh run view $runId `
        --repo Ccatalan7/bikeshop-erp `
        --json status,conclusion,url
    $view = $viewJson | ConvertFrom-Json
    $status = Get-ObjectProperty $view 'status'
    $conclusion = Get-ObjectProperty $view 'conclusion'
    $elapsed = Format-Elapsed $buildTimer.Elapsed
    Write-Host "Elapsed: $elapsed | Status: $status | Conclusion: $conclusion"
} while ($status -ne 'completed')

if ($conclusion -ne 'success') {
    $viewUrl = Get-ObjectProperty $view 'url'
    throw "Windows release workflow failed: $viewUrl"
}

Write-Step 'Windows release published'
gh release list --repo Ccatalan7/bikeshop-erp --limit 3
