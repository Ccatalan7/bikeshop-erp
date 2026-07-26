param(
    [string]$Message = "",
    [switch]$NoWait,
    [switch]$RequireConfirmation,
    [ValidateRange(1, 100)]
    [int]$KeepWindowsReleases = 10,
    [switch]$SkipReleaseCleanup,
    [string]$PreparedState = "",
    [switch]$CheckReleaseBranch
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

function Resolve-ErpUpdateStatePath {
    param(
        [string]$RequestedPath,
        [string]$RepositoryRoot
    )

    $gitDirectory = (git rev-parse --absolute-git-dir).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitDirectory)) {
        throw 'Could not resolve the current Git directory.'
    }

    if ([string]::IsNullOrWhiteSpace($RequestedPath) -or $RequestedPath -eq 'auto') {
        $resolvedPath = Join-Path $gitDirectory 'vinabike-erp-publish-state.json'
    } elseif ([System.IO.Path]::IsPathRooted($RequestedPath)) {
        $resolvedPath = $RequestedPath
    } else {
        $resolvedPath = Join-Path $RepositoryRoot $RequestedPath
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($resolvedPath)
    $resolvedGitDirectory = [System.IO.Path]::GetFullPath($gitDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $gitPrefix = "$resolvedGitDirectory$([System.IO.Path]::DirectorySeparatorChar)"
    if (-not $resolvedPath.StartsWith(
        $gitPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'The ERP update state file must stay inside the current Git directory.'
    }

    return $resolvedPath
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (
            [System.BitConverter]::ToString($sha256.ComputeHash($Bytes))
        ).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Read-PreparedErpUpdateState {
    param(
        [string]$RequestedPath,
        [string]$RepositoryRoot
    )

    $statePath = Resolve-ErpUpdateStatePath `
        -RequestedPath $RequestedPath `
        -RepositoryRoot $RepositoryRoot
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Prepared ERP update state is unavailable: $statePath"
    }

    $stateItem = Get-Item -LiteralPath $statePath -Force
    if (($stateItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Prepared ERP update state must not be a symbolic link or reparse point.'
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    } catch {
        throw 'Prepared ERP update state is not valid JSON.'
    }

    $targets = @(Get-ObjectProperty $state 'targets')
    $releaseNotes = Get-ObjectProperty $state 'release_notes'
    $schemaVersion = Get-ObjectProperty $state 'schema_version'
    $stateRepositoryRoot = [string](Get-ObjectProperty $state 'repository_root')
    $remote = [string](Get-ObjectProperty $state 'remote')
    $branch = [string](Get-ObjectProperty $state 'branch')
    $headSha = [string](Get-ObjectProperty $state 'head_sha')
    $createdEpochValue = Get-ObjectProperty $state 'created_epoch'

    if (
        $schemaVersion -ne 2 -or
        $targets -notcontains 'windows' -or
        [string]::IsNullOrWhiteSpace($stateRepositoryRoot) -or
        $remote -ne 'origin' -or
        [string]::IsNullOrWhiteSpace($branch) -or
        $headSha -notmatch '^[0-9a-f]{40}$' -or
        $null -eq $createdEpochValue -or
        $null -eq $releaseNotes
    ) {
        throw 'Prepared ERP update state is malformed or does not authorize Windows.'
    }

    try {
        $createdEpoch = [int64]$createdEpochValue
    } catch {
        throw 'Prepared ERP update state has an invalid creation time.'
    }
    $nowEpoch = [int64](
        [DateTime]::UtcNow - [DateTime]'1970-01-01T00:00:00Z'
    ).TotalSeconds
    $stateAge = $nowEpoch - $createdEpoch
    if ($stateAge -lt 0 -or $stateAge -gt 21600) {
        throw 'Prepared ERP update state is stale; run the top-level publish task again.'
    }

    $fromCommit = [string](Get-ObjectProperty $releaseNotes 'from_commit')
    $candidateBase64 = [string](Get-ObjectProperty $releaseNotes 'candidate_b64')
    $candidateSha256 = [string](
        Get-ObjectProperty $releaseNotes 'candidate_sha256'
    )
    if (
        $fromCommit -notmatch '^[0-9a-f]{40}$' -or
        $candidateBase64.Length -gt 16384 -or
        (
            [string]::IsNullOrEmpty($candidateBase64) -and
            -not [string]::IsNullOrEmpty($candidateSha256)
        ) -or
        (
            -not [string]::IsNullOrEmpty($candidateBase64) -and
            $candidateSha256 -notmatch '^[0-9a-f]{64}$'
        )
    ) {
        throw 'Prepared ERP update state has invalid release-note metadata.'
    }

    if (-not [string]::IsNullOrEmpty($candidateBase64)) {
        try {
            $candidateBytes = [System.Convert]::FromBase64String($candidateBase64)
        } catch {
            throw 'Prepared ERP update state has an invalid release-note candidate.'
        }
        if ($candidateBytes.Length -lt 2 -or $candidateBytes.Length -gt 12288) {
            throw 'Prepared ERP update release-note candidate is outside its size boundary.'
        }
        if ((Get-Sha256Hex -Bytes $candidateBytes) -ne $candidateSha256) {
            throw 'Prepared ERP update release-note candidate failed its SHA256 binding.'
        }
        try {
            $candidateEnvelope = (
                [System.Text.Encoding]::UTF8.GetString($candidateBytes) |
                    ConvertFrom-Json
            )
        } catch {
            throw 'Prepared ERP update release-note candidate is not valid JSON.'
        }
        if (
            (Get-ObjectProperty $candidateEnvelope 'from_commit') -ne $fromCommit -or
            (Get-ObjectProperty $candidateEnvelope 'to_commit') -ne $headSha
        ) {
            throw 'Prepared ERP update release-note candidate targets a different range.'
        }
    }

    return [pscustomobject]@{
        StatePath = $statePath
        RepositoryRoot = [System.IO.Path]::GetFullPath($stateRepositoryRoot)
        Remote = $remote
        Branch = $branch
        HeadSha = $headSha
        ReleaseNotesFromCommit = $fromCommit
        ReleaseNotesCandidateBase64 = $candidateBase64
        ReleaseNotesCandidateSha256 = $candidateSha256
    }
}

function Assert-PreparedErpUpdateSource {
    param([object]$PreparedUpdate)

    $actualRoot = [System.IO.Path]::GetFullPath(
        (git rev-parse --show-toplevel).Trim()
    )
    $actualBranch = (git branch --show-current).Trim()
    $actualHead = (git rev-parse HEAD).Trim()

    if (-not $actualRoot.Equals(
        $PreparedUpdate.RepositoryRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Prepared ERP update state belongs to a different repository checkout.'
    }
    if ($actualBranch -ne $PreparedUpdate.Branch) {
        throw 'The current branch does not match the prepared ERP update.'
    }
    if ($actualHead -ne $PreparedUpdate.HeadSha) {
        throw 'The current commit does not match the prepared ERP update.'
    }
    if (-not [string]::IsNullOrWhiteSpace((git status --porcelain))) {
        throw 'The worktree changed after the shared ERP update commit was prepared.'
    }

    git merge-base --is-ancestor `
        $PreparedUpdate.ReleaseNotesFromCommit `
        $PreparedUpdate.HeadSha
    if ($LASTEXITCODE -ne 0) {
        throw 'The prepared release-note base is not an ancestor of the release commit.'
    }

    $remoteLine = @(
        git ls-remote `
            --heads `
            $PreparedUpdate.Remote `
            "refs/heads/$($PreparedUpdate.Branch)"
    ) | Select-Object -First 1
    $remoteHead = if ([string]::IsNullOrWhiteSpace([string]$remoteLine)) {
        ''
    } else {
        ([string]$remoteLine -split '\s+')[0]
    }
    if (
        $remoteHead -notmatch '^[0-9a-f]{40}$' -or
        $remoteHead -ne $PreparedUpdate.HeadSha
    ) {
        throw 'The live remote branch no longer matches the prepared ERP update.'
    }
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

function Find-PublishedWindowsReleaseForCommit {
    param([string]$HeadSha)

    $releases = @()
    for ($page = 1; $page -le 20; $page++) {
        $releaseJson = gh api `
            --method GET `
            repos/Ccatalan7/bikeshop-erp/releases `
            -f per_page=100 `
            -f page=$page
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not inspect existing Windows releases.'
        }
        $releasePage = @($releaseJson | ConvertFrom-Json)
        $releases += $releasePage
        if ($releasePage.Count -lt 100) {
            break
        }
        if ($page -eq 20) {
            throw 'Windows release history exceeded its bounded verification scan.'
        }
    }

    $candidates = @(
        $releases |
            Where-Object {
                (Get-ObjectProperty $_ 'tag_name') -like 'windows-v*' -and
                (Get-ObjectProperty $_ 'draft') -ne $true -and
                (Get-ObjectProperty $_ 'prerelease') -ne $true
            } |
            Sort-Object {
                [datetime](Get-ObjectProperty $_ 'created_at')
            } -Descending
    )

    foreach ($candidate in $candidates) {
        $tagName = [string](Get-ObjectProperty $candidate 'tag_name')
        $assets = @(Get-ObjectProperty $candidate 'assets')
        $manifestAsset = @(
            $assets |
                Where-Object {
                    (Get-ObjectProperty $_ 'name') -eq
                        'windows-release-manifest.json'
                }
        ) | Select-Object -First 1
        $assetId = Get-ObjectProperty $manifestAsset 'id'
        if ($null -eq $assetId) {
            continue
        }

        try {
            $manifestJson = gh api `
                --method GET `
                -H 'Accept: application/octet-stream' `
                "repos/Ccatalan7/bikeshop-erp/releases/assets/$assetId" 2>$null
            if ($LASTEXITCODE -ne 0) {
                continue
            }
            $manifest = ($manifestJson -join "`n") | ConvertFrom-Json
            $zipName = [string](Get-ObjectProperty $manifest 'zip_name')
            $zipSha256 = [string](
                Get-ObjectProperty $manifest 'zip_sha256'
            )
            $installerName = [string](
                Get-ObjectProperty $manifest 'installer_name'
            )
            $installerSha256 = [string](
                Get-ObjectProperty $manifest 'installer_sha256'
            )
            if (
                (Get-ObjectProperty $manifest 'tag_name') -ne $tagName -or
                (Get-ObjectProperty $manifest 'commit') -ne $HeadSha -or
                (Get-ObjectProperty $manifest 'publish_requested') -ne $true -or
                [string]::IsNullOrWhiteSpace($zipName) -or
                $zipSha256 -notmatch '^[0-9a-f]{64}$' -or
                [string]::IsNullOrWhiteSpace($installerName) -or
                $installerSha256 -notmatch '^[0-9a-f]{64}$'
            ) {
                continue
            }

            $zipAsset = @(
                $assets |
                    Where-Object {
                        (Get-ObjectProperty $_ 'name') -eq $zipName
                    }
            ) | Select-Object -First 1
            $checksumAsset = @(
                $assets |
                    Where-Object {
                        (Get-ObjectProperty $_ 'name') -eq "$zipName.sha256"
                    }
            ) | Select-Object -First 1
            $installerAsset = @(
                $assets |
                    Where-Object {
                        (Get-ObjectProperty $_ 'name') -eq $installerName
                    }
            ) | Select-Object -First 1
            if (
                $null -eq $zipAsset -or
                $null -eq $checksumAsset -or
                $null -eq $installerAsset -or
                [int64](Get-ObjectProperty $zipAsset 'size') -le 0 -or
                [int64](Get-ObjectProperty $checksumAsset 'size') -le 0 -or
                [int64](Get-ObjectProperty $installerAsset 'size') -le 0
            ) {
                continue
            }

            $checksumAssetId = Get-ObjectProperty $checksumAsset 'id'
            $checksumText = gh api `
                --method GET `
                -H 'Accept: application/octet-stream' `
                "repos/Ccatalan7/bikeshop-erp/releases/assets/$checksumAssetId" 2>$null
            if ($LASTEXITCODE -ne 0) {
                continue
            }
            $expectedChecksum = (
                '^' +
                [regex]::Escape($zipSha256) +
                '\s+' +
                [regex]::Escape($zipName) +
                '\s*$'
            )
            if (($checksumText -join "`n") -notmatch $expectedChecksum) {
                continue
            }
            return $tagName
        } catch {
            continue
        }
    }

    return $null
}

function Get-WindowsWorkflowRuns {
    param([string]$Branch)

    try {
        $runsJson = gh api --method GET `
            repos/Ccatalan7/bikeshop-erp/actions/workflows/windows-release.yml/runs `
            -f branch=$Branch `
            -f event=workflow_dispatch `
            -f per_page=20
        if ($LASTEXITCODE -ne 0) {
            throw 'The workflow-run API request failed.'
        }

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
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not list Windows release workflow runs.'
        }

        return @($runsJson | ConvertFrom-Json)
    }
}

function Assert-ProductionReleaseBranch {
    param([string]$Branch)

    Write-Step "Checking Production release permission for branch: $Branch"

    $environmentJson = gh api `
        repos/Ccatalan7/bikeshop-erp/environments/Production
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not verify the GitHub Production environment policy.'
    }
    $environment = $environmentJson | ConvertFrom-Json
    if ($null -eq $environment) {
        throw 'GitHub returned an empty Production environment policy.'
    }
    $policy = Get-ObjectProperty $environment 'deployment_branch_policy'

    if ($null -eq $policy) {
        Write-Host 'Production has no deployment branch restriction.'
        return
    }

    $protectedBranchesOnly = Get-ObjectProperty $policy 'protected_branches'
    if ($protectedBranchesOnly -eq $true) {
        $escapedBranch = [uri]::EscapeDataString($Branch)
        $branchJson = gh api "repos/Ccatalan7/bikeshop-erp/branches/$escapedBranch"
        if ($LASTEXITCODE -ne 0) {
            throw "Could not verify whether branch '$Branch' is protected."
        }
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
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not verify the Production custom branch policies.'
        }
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
        [datetime]$TriggeredAt,
        [string]$ExpectedTitle
    )

    $parsedRuns = Get-WindowsWorkflowRuns -Branch $Branch

    foreach ($candidate in $parsedRuns) {
        $candidateTitle = [string](Get-RunProperty $candidate 'displayTitle')
        if ($candidateTitle -ne $ExpectedTitle) {
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
        if ($candidateTitle -ne $ExpectedTitle) {
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
        [string]$HeadSha,
        [string]$ExpectedTitle
    )

    $parsedRuns = Get-WindowsWorkflowRuns -Branch $Branch

    foreach ($candidate in $parsedRuns) {
        $candidateTitle = [string](Get-RunProperty $candidate 'displayTitle')
        if ($candidateTitle -ne $ExpectedTitle) {
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

$preparedUpdate = $null
$releaseNotesFromCommit = ''
$releaseNotesCandidateBase64 = ''
$releaseNotesCandidateSha256 = ''

if ($CheckReleaseBranch) {
    Write-Host 'Windows Production branch boundary is ready.'
    return
}

if (-not [string]::IsNullOrWhiteSpace($PreparedState)) {
    if (
        -not [string]::IsNullOrWhiteSpace($Message) -or
        $RequireConfirmation
    ) {
        throw '-PreparedState cannot be combined with commit or confirmation options.'
    }

    Write-Step 'Validating the shared Windows and Android release state'
    $preparedUpdate = Read-PreparedErpUpdateState `
        -RequestedPath $PreparedState `
        -RepositoryRoot $repoRoot
    Assert-PreparedErpUpdateSource -PreparedUpdate $preparedUpdate
    $branch = $preparedUpdate.Branch
    $headSha = $preparedUpdate.HeadSha
    $releaseNotesFromCommit = $preparedUpdate.ReleaseNotesFromCommit
    $releaseNotesCandidateBase64 = (
        $preparedUpdate.ReleaseNotesCandidateBase64
    )
    $releaseNotesCandidateSha256 = (
        $preparedUpdate.ReleaseNotesCandidateSha256
    )
    Write-Host "Prepared source: $headSha"
    Write-Host 'Git staging, commit, and push are owned by the shared preparation step.'
} else {
    Write-Step 'Staging all Source Control changes'
    git add -A
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not stage the reviewed Source Control changes.'
    }

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
        $confirmationAction = if ($hasStagedChanges) {
            'commit, push, and publish'
        } else {
            'push and publish'
        }
        $confirmation = Read-Host `
            "Type YES to $confirmationAction a Windows release from branch '$branch'"
        if ($confirmation -ne 'YES') {
            Write-Host 'Cancelled.'
            exit 1
        }
    }

    if ($hasStagedChanges) {
        Write-Step 'Committing staged changes'
        git commit -m $Message
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not create the Windows update commit.'
        }
    } else {
        Write-Step 'Skipping commit'
    }

    $headSha = (git rev-parse HEAD).Trim()

    Write-Step "Pushing $branch"
    git push origin $branch
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not push the Windows update commit.'
    }
}

$publishedRelease = Find-PublishedWindowsReleaseForCommit -HeadSha $headSha
if (-not [string]::IsNullOrWhiteSpace([string]$publishedRelease)) {
    Write-Step 'Windows release is already published'
    Write-Host "Exact release: $publishedRelease"
    Write-Host "Source commit: $headSha"
    exit 0
}

if ($null -ne $preparedUpdate) {
    Assert-PreparedErpUpdateSource -PreparedUpdate $preparedUpdate
}

$notesTitleIdentity = if (
    [string]::IsNullOrWhiteSpace($releaseNotesCandidateSha256)
) {
    'fallback'
} else {
    $releaseNotesCandidateSha256
}
$notesBaseIdentity = if (
    [string]::IsNullOrWhiteSpace($releaseNotesFromCommit)
) {
    'auto'
} else {
    $releaseNotesFromCommit
}
$expectedRunTitle = (
    "Windows publish · $headSha · notes $notesTitleIdentity" +
    " · from $notesBaseIdentity"
)
$run = Find-ActiveWorkflowRun `
    -Branch $branch `
    -HeadSha $headSha `
    -ExpectedTitle $expectedRunTitle
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
    $workflowInputs = [ordered]@{
        publish_release = 'true'
        expected_commit = $headSha
        release_notes_from_commit = $releaseNotesFromCommit
        release_notes_candidate_b64 = $releaseNotesCandidateBase64
        release_notes_candidate_sha256 = $releaseNotesCandidateSha256
    }
    $workflowInputsJson = $workflowInputs |
        ConvertTo-Json -Compress
    $workflowInputsJson |
        gh workflow run windows-release.yml `
            --repo Ccatalan7/bikeshop-erp `
            --ref $branch `
            --json
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub rejected the Windows release workflow dispatch.'
    }

    $runLookupDeadline = (Get-Date).AddMinutes(5)
    Write-Step 'Finding GitHub Actions Windows release run'
    do {
        $elapsed = Format-Elapsed ((Get-Date).ToUniversalTime() - $timerStartUtc)
        Write-Host "Elapsed: $elapsed | Phase: finding GitHub run"
        $run = Find-TriggeredWorkflowRun `
            -Branch $branch `
            -HeadSha $headSha `
            -TriggeredAt $triggeredAt `
            -ExpectedTitle $expectedRunTitle
        if (-not $run) {
            Start-Sleep -Seconds 10
        }
    } while (-not $run -and (Get-Date) -lt $runLookupDeadline)
}

if (-not $run) {
    throw 'GitHub accepted the Windows dispatch, but its exact run could not be correlated within five minutes.'
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
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect Windows release workflow run $runId."
    }
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

Write-Step 'Verifying the exact published Windows release'
$publishedRelease = $null
$publicationDeadline = (Get-Date).AddMinutes(2)
do {
    $publishedRelease = Find-PublishedWindowsReleaseForCommit `
        -HeadSha $headSha
    if ([string]::IsNullOrWhiteSpace([string]$publishedRelease)) {
        Start-Sleep -Seconds 5
    }
} while (
    [string]::IsNullOrWhiteSpace([string]$publishedRelease) -and
    (Get-Date) -lt $publicationDeadline
)
if ([string]::IsNullOrWhiteSpace([string]$publishedRelease)) {
    throw 'The Windows workflow succeeded, but its exact release manifest is not visible.'
}

Write-Step 'Windows release published'
Write-Host "Exact release: $publishedRelease"
gh release list --repo Ccatalan7/bikeshop-erp --limit 3

if (-not $SkipReleaseCleanup) {
    try {
        Invoke-WindowsReleaseCleanup -Keep $KeepWindowsReleases
    } catch {
        Write-Host "Release cleanup skipped because it failed: $($_.Exception.Message)"
    }
}
