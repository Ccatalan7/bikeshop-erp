param(
    [string]$Message = "",
    [switch]$NoWait,
    [switch]$RequireConfirmation,
    [ValidateRange(1, 100)]
    [int]$KeepWindowsReleases = 10,
    [switch]$SkipReleaseCleanup
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

function Convert-ToUtcDateTimeOrNull {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        return ([datetime]$text).ToUniversalTime()
    } catch {
        return $null
    }
}

function Get-RunProperty {
    param(
        [object]$Run,
        [string]$Name
    )

    switch ($Name) {
        'databaseId' {
            $value = Get-ObjectProperty $Run 'databaseId'
            if ($null -eq $value) { $value = Get-ObjectProperty $Run 'id' }
            return $value
        }
        'headSha' {
            $value = Get-ObjectProperty $Run 'headSha'
            if ($null -eq $value) { $value = Get-ObjectProperty $Run 'head_sha' }
            return $value
        }
        'url' {
            $value = Get-ObjectProperty $Run 'url'
            if ($null -eq $value) { $value = Get-ObjectProperty $Run 'html_url' }
            return $value
        }
        'createdAt' {
            $value = Get-ObjectProperty $Run 'createdAt'
            if ($null -eq $value) { $value = Get-ObjectProperty $Run 'created_at' }
            return $value
        }
        'displayTitle' {
            $value = Get-ObjectProperty $Run 'displayTitle'
            if ($null -eq $value) { $value = Get-ObjectProperty $Run 'display_title' }
            return $value
        }
        default {
            return Get-ObjectProperty $Run $Name
        }
    }
}

function Invoke-WindowsReleaseCleanup {
    param([int]$Keep)

    Write-Step "Pruning old Windows releases, keeping latest $Keep"

    $releasesJson = gh release list `
        --repo Ccatalan7/bikeshop-erp `
        --limit 100 `
        --json tagName,createdAt,isDraft,isPrerelease,name

    $releases = @($releasesJson | ConvertFrom-Json)
    $windowsReleases = @(
        $releases |
            Where-Object { (Get-ObjectProperty $_ 'tagName') -like 'windows-v*' } |
            Sort-Object { [datetime](Get-ObjectProperty $_ 'createdAt') } -Descending
    )

    if ($windowsReleases.Count -le $Keep) {
        Write-Host "No old Windows releases to prune. Current count: $($windowsReleases.Count)."
        return
    }

    $oldReleases = @($windowsReleases | Select-Object -Skip $Keep)
    foreach ($release in $oldReleases) {
        $tagName = Get-ObjectProperty $release 'tagName'
        if ([string]::IsNullOrWhiteSpace($tagName)) {
            continue
        }

        Write-Host "Deleting old Windows release: $tagName"
        gh release delete $tagName --repo Ccatalan7/bikeshop-erp --yes --cleanup-tag
    }
}

function Get-WindowsWorkflowRuns {
    param([string]$Branch)

    try {
        $runsJson = gh api --method GET `
            repos/Ccatalan7/bikeshop-erp/actions/workflows/windows-release.yml/runs `
            -f branch=$Branch `
            -f event=workflow_dispatch `
            -f per_page=20

        $runsResponse = $runsJson | ConvertFrom-Json
        return @($runsResponse.workflow_runs)
    } catch {
        Write-Host "Direct workflow run API failed; falling back to gh run list: $($_.Exception.Message)"

        $runsJson = gh run list `
            --repo Ccatalan7/bikeshop-erp `
            --workflow "Build Windows Desktop Release" `
            --branch $Branch `
            --limit 20 `
            --json databaseId,headSha,status,conclusion,url,createdAt,displayTitle

        return @($runsJson | ConvertFrom-Json)
    }
}

function Assert-ProductionReleaseBranch {
    param([string]$Branch)

    Write-Step "Checking Production release permission for branch: $Branch"

    $environmentJson = gh api `
        repos/Ccatalan7/bikeshop-erp/environments/Production
    $environment = $environmentJson | ConvertFrom-Json
    $policy = Get-ObjectProperty $environment 'deployment_branch_policy'

    if ($null -eq $policy) {
        Write-Host 'Production has no deployment branch restriction.'
        return
    }

    $protectedBranchesOnly = Get-ObjectProperty $policy 'protected_branches'
    if ($protectedBranchesOnly -eq $true) {
        $escapedBranch = [uri]::EscapeDataString($Branch)
        $branchJson = gh api "repos/Ccatalan7/bikeshop-erp/branches/$escapedBranch"
        $branchDetails = $branchJson | ConvertFrom-Json
        if ((Get-ObjectProperty $branchDetails 'protected') -ne $true) {
            throw "Branch '$Branch' is not authorized by the Production environment. The Windows build was not started."
        }

        Write-Host 'Branch is protected and authorized for Production.'
        return
    }

    $customPolicies = Get-ObjectProperty $policy 'custom_branch_policies'
    if ($customPolicies -eq $true) {
        $policiesJson = gh api --method GET `
            repos/Ccatalan7/bikeshop-erp/environments/Production/deployment-branch-policies `
            -f per_page=100
        $policiesResponse = $policiesJson | ConvertFrom-Json
        $policies = @(Get-ObjectProperty $policiesResponse 'branch_policies')

        foreach ($branchPolicy in $policies) {
            $policyType = Get-ObjectProperty $branchPolicy 'type'
            $pattern = [string](Get-ObjectProperty $branchPolicy 'name')
            if (($null -eq $policyType -or $policyType -eq 'branch') -and $Branch -like $pattern) {
                Write-Host "Branch is authorized by Production policy '$pattern'."
                return
            }
        }

        throw "Branch '$Branch' is not authorized by the Production environment. The Windows build was not started."
    }
}

function Show-WorkflowFailureDiagnostics {
    param([string]$RunId)

    try {
        $jobsJson = gh api "repos/Ccatalan7/bikeshop-erp/actions/runs/$RunId/jobs"
        $jobsResponse = $jobsJson | ConvertFrom-Json
        $failedJobs = @(
            (Get-ObjectProperty $jobsResponse 'jobs') |
                Where-Object { (Get-ObjectProperty $_ 'conclusion') -eq 'failure' }
        )

        foreach ($job in $failedJobs) {
            $jobId = Get-ObjectProperty $job 'id'
            $jobName = Get-ObjectProperty $job 'name'
            Write-Host "Failed job: $jobName"
            if ($null -eq $jobId) {
                continue
            }

            $annotationsJson = gh api `
                "repos/Ccatalan7/bikeshop-erp/check-runs/$jobId/annotations"
            $annotations = @($annotationsJson | ConvertFrom-Json)
            foreach ($annotation in $annotations) {
                $message = Get-ObjectProperty $annotation 'message'
                if (-not [string]::IsNullOrWhiteSpace([string]$message)) {
                    Write-Host "  $message"
                }
            }
        }
    } catch {
        Write-Host "Could not load detailed failure diagnostics: $($_.Exception.Message)"
    }
}

function Find-TriggeredWorkflowRun {
    param(
        [string]$Branch,
        [string]$HeadSha,
        [datetime]$TriggeredAt
    )

    $parsedRuns = Get-WindowsWorkflowRuns -Branch $Branch

    foreach ($candidate in $parsedRuns) {
        $candidateTitle = [string](Get-RunProperty $candidate 'displayTitle')
        if ($candidateTitle -notlike 'Windows publish*') {
            continue
        }
        $candidateCreatedAt = Convert-ToUtcDateTimeOrNull (Get-RunProperty $candidate 'createdAt')
        if ($null -eq $candidateCreatedAt) {
            continue
        }

        if ((Get-RunProperty $candidate 'headSha') -eq $HeadSha -and $candidateCreatedAt -ge $TriggeredAt) {
            return $candidate
        }
    }

    foreach ($candidate in $parsedRuns) {
        $candidateTitle = [string](Get-RunProperty $candidate 'displayTitle')
        if ($candidateTitle -notlike 'Windows publish*') {
            continue
        }
        $candidateStatus = Get-ObjectProperty $candidate 'status'
        if ((Get-RunProperty $candidate 'headSha') -eq $HeadSha -and $candidateStatus -ne 'completed') {
            return $candidate
        }
    }

    return $null
}

function Find-ActiveWorkflowRun {
    param(
        [string]$Branch,
        [string]$HeadSha
    )

    $parsedRuns = Get-WindowsWorkflowRuns -Branch $Branch

    foreach ($candidate in $parsedRuns) {
        $candidateTitle = [string](Get-RunProperty $candidate 'displayTitle')
        if ($candidateTitle -notlike 'Windows publish*') {
            continue
        }
        $candidateStatus = Get-ObjectProperty $candidate 'status'
        if ((Get-RunProperty $candidate 'headSha') -eq $HeadSha -and $candidateStatus -ne 'completed') {
            return $candidate
        }
    }

    return $null
}

Require-Command git
Require-Command gh

$repoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $repoRoot

$branch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'Could not determine the current Git branch.'
}

Assert-ProductionReleaseBranch -Branch $branch

Write-Step 'Staging all Source Control changes'
git add -A

$stagedFiles = @(git diff --cached --name-only)
$hasStagedChanges = $stagedFiles.Count -gt 0

if ($hasStagedChanges -and [string]::IsNullOrWhiteSpace($Message)) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $Message = "chore: publish Windows update $timestamp"
}

Write-Step "Current branch: $branch"
if ($hasStagedChanges) {
    Write-Host "Commit message: $Message"
    Write-Host "Files to commit and publish:"
    foreach ($file in $stagedFiles) {
        Write-Host "  $file"
    }
} else {
    Write-Host 'No uncommitted Source Control changes found.'
    Write-Host 'Publishing the current branch HEAD instead.'
}

if ($RequireConfirmation) {
    $confirmationAction = if ($hasStagedChanges) { 'commit, push, and publish' } else { 'push and publish' }
    $confirmation = Read-Host "Type YES to $confirmationAction a Windows release from branch '$branch'"
    if ($confirmation -ne 'YES') {
        Write-Host 'Cancelled.'
        exit 1
    }
}

if ($hasStagedChanges) {
    Write-Step 'Committing staged changes'
    git commit -m $Message
} else {
    Write-Step 'Skipping commit'
}

$headSha = (git rev-parse HEAD).Trim()

Write-Step "Pushing $branch"
git push origin $branch

$run = Find-ActiveWorkflowRun -Branch $branch -HeadSha $headSha
$timerStartUtc = (Get-Date).ToUniversalTime()

if ($run) {
    Write-Step 'Existing Windows release build found for current commit'
    $existingRunCreatedAt = Convert-ToUtcDateTimeOrNull (Get-RunProperty $run 'createdAt')
    if ($null -ne $existingRunCreatedAt) {
        $timerStartUtc = $existingRunCreatedAt
    }
} else {
    Write-Step 'Triggering GitHub Actions Windows release workflow'
    $triggeredAt = (Get-Date).ToUniversalTime().AddSeconds(-5)
    gh workflow run windows-release.yml `
        --repo Ccatalan7/bikeshop-erp `
        --ref $branch `
        -f publish_release=true

    $runLookupDeadline = (Get-Date).AddMinutes(5)
    Write-Step 'Finding GitHub Actions Windows release run'
    do {
        $elapsed = Format-Elapsed ((Get-Date).ToUniversalTime() - $timerStartUtc)
        Write-Host "Elapsed: $elapsed | Phase: finding GitHub run"
        $run = Find-TriggeredWorkflowRun -Branch $branch -HeadSha $headSha -TriggeredAt $triggeredAt
        if (-not $run) {
            Start-Sleep -Seconds 10
        }
    } while (-not $run -and (Get-Date) -lt $runLookupDeadline)
}

if (-not $run) {
    Write-Host 'GitHub accepted the workflow_dispatch event, but the run is not visible through the API yet.'
    Write-Host 'This can happen when GitHub Actions is delayed. The build may still be queued or running.'
    Write-Host 'Check GitHub Actions for the latest "Build Windows Desktop Release" run, or use:'
    Write-Host '  gh run list --repo Ccatalan7/bikeshop-erp --workflow "Build Windows Desktop Release" --branch smartpegas1.0 --limit 5'
    exit 0
}

$runId = Get-RunProperty $run 'databaseId'
$runUrl = Get-RunProperty $run 'url'
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
    $elapsed = Format-Elapsed ((Get-Date).ToUniversalTime() - $timerStartUtc)
    Write-Host "Elapsed: $elapsed | Phase: building Windows release | Status: $status | Conclusion: $conclusion"
} while ($status -ne 'completed')

if ($conclusion -ne 'success') {
    $viewUrl = Get-ObjectProperty $view 'url'
    Show-WorkflowFailureDiagnostics -RunId $runId
    throw "Windows release workflow failed: $viewUrl"
}

Write-Step 'Windows release published'
gh release list --repo Ccatalan7/bikeshop-erp --limit 3

if (-not $SkipReleaseCleanup) {
    try {
        Invoke-WindowsReleaseCleanup -Keep $KeepWindowsReleases
    } catch {
        Write-Host "Release cleanup skipped because it failed: $($_.Exception.Message)"
    }
}
