param(
    [string]$Message = "",
    [string]$StateFile = ".git/vinabike-windows-android-publish-state.json"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)

    Write-Host ""
    Write-Host "[erp-update] $Message"
}

function Require-Command {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        throw "Required command '$Name' was not found in PATH."
    }
    return $command
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

function Test-GitAncestor {
    param(
        [string]$Ancestor,
        [string]$Descendant
    )

    git merge-base --is-ancestor $Ancestor $Descendant 2>$null
    return $LASTEXITCODE -eq 0
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

function Protect-PrivateStateFile {
    param([string]$Path)

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $security = New-Object System.Security.AccessControl.FileSecurity
    $security.SetOwner($identity.User)
    $security.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $identity.User,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $security.AddAccessRule($rule)
    [System.IO.File]::SetAccessControl($Path, $security)
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

function Get-ReusableCodexCandidate {
    param(
        [string]$StatePath,
        [string]$FromCommit,
        [string]$ToCommit
    )

    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        return $null
    }
    try {
        $item = Get-Item -LiteralPath $StatePath -Force
        if (
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne
                0
        ) {
            return $null
        }
        $state = Get-Content -LiteralPath $StatePath -Raw |
            ConvertFrom-Json
        $notes = Get-ObjectProperty $state 'release_notes'
        $targets = @(Get-ObjectProperty $state 'targets')
        $candidateBase64 = [string](
            Get-ObjectProperty $notes 'candidate_b64'
        )
        $candidateSha256 = [string](
            Get-ObjectProperty $notes 'candidate_sha256'
        )
        if (
            (
                (Get-ObjectProperty $state 'schema_version') -ne 2 -and
                (Get-ObjectProperty $state 'schema_version') -ne 3
            ) -or
            $targets -notcontains 'windows' -or
            $targets -notcontains 'android' -or
            (Get-ObjectProperty $state 'head_sha') -ne $ToCommit -or
            (Get-ObjectProperty $notes 'from_commit') -ne $FromCommit -or
            [string]::IsNullOrEmpty($candidateBase64) -or
            $candidateBase64.Length -gt 16384 -or
            $candidateSha256 -notmatch '^[0-9a-f]{64}$'
        ) {
            return $null
        }

        $bytes = [System.Convert]::FromBase64String($candidateBase64)
        if (
            $bytes.Length -lt 2 -or
            $bytes.Length -gt 12288 -or
            (Get-Sha256Hex -Bytes $bytes) -ne $candidateSha256
        ) {
            return $null
        }
        $envelope = (
            [System.Text.Encoding]::UTF8.GetString($bytes) |
                ConvertFrom-Json
        )
        if (
            (Get-ObjectProperty $envelope 'schema_version') -ne 1 -or
            (Get-ObjectProperty $envelope 'from_commit') -ne $FromCommit -or
            (Get-ObjectProperty $envelope 'to_commit') -ne $ToCommit -or
            $null -eq (Get-ObjectProperty $envelope 'candidate')
        ) {
            return $null
        }
        return [pscustomobject]@{
            Base64 = $candidateBase64
            Sha256 = $candidateSha256
        }
    } catch {
        return $null
    }
}

function Invoke-FlutterDependencyNormalization {
    param([string]$RepositoryRoot)

    $fvmFlutter = Join-Path `
        $RepositoryRoot `
        '.fvm\flutter_sdk\bin\flutter.bat'
    if (Test-Path -LiteralPath $fvmFlutter -PathType Leaf) {
        & $fvmFlutter pub get
    } else {
        $fvm = Get-Command fvm -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $fvm) {
            & $fvm.Source flutter pub get
        } else {
            $flutter = Require-Command flutter
            & $flutter.Source pub get
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Flutter dependency normalization failed.'
    }
}

function Get-LatestWindowsReleaseBase {
    param([string]$HeadSha)

    $releases = @()
    for ($page = 1; $page -le 20; $page++) {
        $releaseJson = gh api `
            --method GET `
            repos/Ccatalan7/bikeshop-erp/releases `
            -f per_page=100 `
            -f page=$page
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not inspect the existing Windows release history.'
        }
        $releasePage = @($releaseJson | ConvertFrom-Json)
        $releases += $releasePage
        if ($releasePage.Count -lt 100) {
            break
        }
        if ($page -eq 20) {
            throw 'Windows release history exceeded its bounded baseline scan.'
        }
    }

    $releases = @(
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

    $privateDirectory = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        "vinabike-release-base-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $privateDirectory | Out-Null
    try {
        foreach ($release in $releases) {
            $tagName = [string](Get-ObjectProperty $release 'tag_name')
            $releaseTarget = [string](
                Get-ObjectProperty $release 'target_commitish'
            )
            $manifestPath = Join-Path `
                $privateDirectory `
                'windows-release-manifest.json'
            Remove-Item -LiteralPath $manifestPath -Force `
                -ErrorAction SilentlyContinue
            gh release download $tagName `
                --repo Ccatalan7/bikeshop-erp `
                --pattern windows-release-manifest.json `
                --dir $privateDirectory `
                --clobber 2>$null |
                Out-Host
            if ($LASTEXITCODE -ne 0 -or -not (
                Test-Path -LiteralPath $manifestPath -PathType Leaf
            )) {
                continue
            }

            try {
                $manifest = (
                    Get-Content -LiteralPath $manifestPath -Raw |
                        ConvertFrom-Json
                )
            } catch {
                continue
            }
            $candidateCommit = [string](
                Get-ObjectProperty $manifest 'commit'
            )
            if (
                (Get-ObjectProperty $manifest 'tag_name') -ne $tagName -or
                $candidateCommit -notmatch '^[0-9a-f]{40}$' -or
                $candidateCommit -eq $HeadSha -or
                $candidateCommit -ne $releaseTarget
            ) {
                continue
            }
            git cat-file -e "$candidateCommit`^{commit}" 2>$null
            if (
                $LASTEXITCODE -eq 0 -and
                (Test-GitAncestor `
                    -Ancestor $candidateCommit `
                    -Descendant $HeadSha)
            ) {
                return $candidateCommit
            }
        }
    } finally {
        Remove-Item -LiteralPath $privateDirectory -Recurse -Force `
            -ErrorAction SilentlyContinue
    }

    $rootCommit = @(
        git rev-parse "$HeadSha`^"
    ) | Select-Object -First 1
    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace([string]$rootCommit) -or
        ([string]$rootCommit) -notmatch '^[0-9a-f]{40}$'
    ) {
        throw 'Could not establish the previous release or parent commit.'
    }
    return [string]$rootCommit
}

function Get-LocalCodexCandidate {
    param(
        [string]$RepositoryRoot,
        [string]$FromCommit,
        [string]$ToCommit,
        [string]$OutputPath
    )

    $codex = Get-Command codex.exe,codex.cmd,codex `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $codex) {
        Write-Host 'Local Codex release notes unavailable; protected CI will use its safe fallback.'
        return $null
    }
    $gitleaks = Get-Command gitleaks.exe,gitleaks `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $gitleaks) {
        Write-Host 'Local Codex release notes skipped because gitleaks is unavailable; protected CI will use its safe fallback.'
        return $null
    }

    $node = Require-Command node
    $git = Get-Command git.exe,git -ErrorAction Stop |
        Select-Object -First 1
    $generator = Join-Path `
        $RepositoryRoot `
        'scripts\releases\generate_codex_release_notes.mjs'
    $privateScanLog = Join-Path `
        ([System.IO.Path]::GetDirectoryName($OutputPath)) `
        'gitleaks-private.log'
    & $gitleaks.Source git `
        "--log-opts=$FromCommit..$ToCommit" `
        --config (Join-Path $RepositoryRoot '.gitleaks.toml') `
        --gitleaks-ignore-path (Join-Path $RepositoryRoot '.gitleaksignore') `
        --redact=100 `
        --no-banner `
        --no-color `
        --timeout 120 `
        $RepositoryRoot *> $privateScanLog
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Local Codex release notes skipped because the committed range did not pass the private secret scan.'
        return $null
    }

    & $node.Source $generator `
            --from-commit $FromCommit `
            --to-commit $ToCommit `
            --output $OutputPath `
            --codex-bin $codex.Source `
            --git-bin $git.Source |
        Out-Host
    $generatorExitCode = $LASTEXITCODE
    if ($generatorExitCode -ne 0 -or -not (
        Test-Path -LiteralPath $OutputPath -PathType Leaf
    )) {
        Write-Host 'Local Codex candidate was unavailable; publication will continue with the protected fallback.'
        return $null
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($OutputPath)
        if ($bytes.Length -lt 2 -or $bytes.Length -gt 12288) {
            throw 'candidate size'
        }
        $envelope = (
            [System.Text.Encoding]::UTF8.GetString($bytes) |
                ConvertFrom-Json
        )
        if (
            (Get-ObjectProperty $envelope 'schema_version') -ne 1 -or
            (Get-ObjectProperty $envelope 'from_commit') -ne $FromCommit -or
            (Get-ObjectProperty $envelope 'to_commit') -ne $ToCommit -or
            $null -eq (Get-ObjectProperty $envelope 'candidate')
        ) {
            throw 'candidate identity'
        }
        return [pscustomobject]@{
            Base64 = [System.Convert]::ToBase64String($bytes)
            Sha256 = Get-Sha256Hex -Bytes $bytes
        }
    } catch {
        Write-Host 'Local Codex candidate failed local validation; publication will continue with the protected fallback.'
        return $null
    }
}

$git = Require-Command git
$null = Require-Command gh
$node = Require-Command node

$repoRoot = (git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'Could not resolve the repository root.'
}
$repoRoot = [System.IO.Path]::GetFullPath($repoRoot)
Set-Location $repoRoot

$branch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'Could not determine the current Git branch.'
}

Write-Step 'Checking the Windows Production branch boundary'
& (Join-Path $repoRoot 'scripts\publish_windows_update.ps1') `
    -CheckReleaseBranch
if ($LASTEXITCODE -ne 0) {
    throw 'The current branch is not authorized for Production publication.'
}

Write-Step "Checking live source history for $branch"
git fetch `
    --quiet `
    --no-tags `
    origin `
    "refs/heads/${branch}:refs/remotes/origin/${branch}"
if ($LASTEXITCODE -ne 0) {
    throw "Could not fetch the live origin/$branch history."
}
$remoteBefore = (git rev-parse "refs/remotes/origin/$branch").Trim()
if (Test-GitAncestor -Ancestor $remoteBefore -Descendant HEAD) {
    Write-Host 'Local source already contains the live remote branch.'
} elseif (Test-GitAncestor -Ancestor HEAD -Descendant $remoteBefore) {
    Write-Step "Fast-forwarding $branch to the live origin"
    git merge --ff-only $remoteBefore
    if ($LASTEXITCODE -ne 0) {
        throw 'The live branch could not be applied without disturbing local work.'
    }
} else {
    throw "Local $branch and origin/$branch have diverged; publication stopped safely."
}

Write-Step 'Normalizing pinned Flutter dependencies'
Invoke-FlutterDependencyNormalization -RepositoryRoot $repoRoot

Write-Step 'Staging all reviewed Source Control changes once'
git add -A
if ($LASTEXITCODE -ne 0) {
    throw 'Could not stage the reviewed Source Control changes.'
}
$stagedFiles = @(git diff --cached --name-only)
if ($stagedFiles.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $Message = "chore: publish ERP update $timestamp"
    }
    Write-Host "Commit message: $Message"
    Write-Host 'Files to commit and publish:'
    foreach ($file in $stagedFiles) {
        Write-Host "  $file"
    }

    Write-Step 'Creating the shared Windows and Android update commit'
    git commit -m $Message
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the shared ERP update commit.'
    }
} else {
    Write-Host 'No uncommitted Source Control changes found.'
    Write-Host 'Both publishers will use the current branch HEAD.'
}

if (-not [string]::IsNullOrWhiteSpace((git status --porcelain))) {
    throw 'The worktree changed while the shared ERP update was being prepared.'
}

$headSha = (git rev-parse HEAD).Trim()
$desktopReleaseNotesFromCommit = Get-LatestWindowsReleaseBase -HeadSha $headSha
$pairedBaseResolver = Join-Path `
    $repoRoot `
    'scripts\releases\resolve_paired_release_notes_base.mjs'
$pairedBaseLines = @(
    & $node.Source $pairedBaseResolver `
        --branch $branch `
        --head-commit $headSha `
        --desktop-commit $desktopReleaseNotesFromCommit
)
if ($LASTEXITCODE -ne 0 -or $pairedBaseLines.Count -ne 1) {
    throw 'Could not resolve one common Windows and Android release-note baseline.'
}
$releaseNotesFromCommit = ([string]$pairedBaseLines[0]).Trim()
if ($releaseNotesFromCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'The common Windows and Android release-note baseline is invalid.'
}
$statePath = Resolve-ErpUpdateStatePath `
    -RequestedPath $StateFile `
    -RepositoryRoot $repoRoot
$temporaryRoot = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    "vinabike-codex-notes-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    Write-Step 'Preparing one optional Codex summary for both platforms'
    $candidatePath = Join-Path $temporaryRoot 'release-notes-candidate.json'
    $candidate = Get-ReusableCodexCandidate `
        -StatePath $statePath `
        -FromCommit $releaseNotesFromCommit `
        -ToCommit $headSha
    if ($null -ne $candidate) {
        Write-Host 'Reusing the exact Codex candidate already bound to this commit.'
    } else {
        $candidate = Get-LocalCodexCandidate `
            -RepositoryRoot $repoRoot `
            -FromCommit $releaseNotesFromCommit `
            -ToCommit $headSha `
            -OutputPath $candidatePath
    }
    $candidateBase64 = if ($null -eq $candidate) {
        ''
    } else {
        $candidate.Base64
    }
    $candidateSha256 = if ($null -eq $candidate) {
        ''
    } else {
        $candidate.Sha256
    }

    if (
        (git rev-parse HEAD).Trim() -ne $headSha -or
        (git branch --show-current).Trim() -ne $branch -or
        -not [string]::IsNullOrWhiteSpace((git status --porcelain))
    ) {
        throw 'The local source changed while the Codex summary was being prepared.'
    }

    Write-Step "Pushing the shared source commit $headSha"
    git push origin "${headSha}:refs/heads/$branch"
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not push the shared ERP update commit.'
    }

    $remoteLine = @(
        git ls-remote --heads origin "refs/heads/$branch"
    ) | Select-Object -First 1
    $remoteAfter = if ([string]::IsNullOrWhiteSpace([string]$remoteLine)) {
        ''
    } else {
        ([string]$remoteLine -split '\s+')[0]
    }
    if ($remoteAfter -ne $headSha) {
        throw 'The live remote branch does not identify the shared ERP update commit.'
    }

    $createdEpoch = [int64](
        [DateTime]::UtcNow - [DateTime]'1970-01-01T00:00:00Z'
    ).TotalSeconds
    $state = [ordered]@{
        schema_version = 2
        targets = @('windows', 'android')
        repository_root = $repoRoot
        remote = 'origin'
        branch = $branch
        head_sha = $headSha
        created_epoch = $createdEpoch
        release_notes = [ordered]@{
            from_commit = $releaseNotesFromCommit
            candidate_b64 = $candidateBase64
            candidate_sha256 = $candidateSha256
        }
    }

    $stateTemporaryPath = "$statePath.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        $stateJson = $state | ConvertTo-Json -Depth 5 -Compress
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText(
            $stateTemporaryPath,
            $stateJson,
            $utf8WithoutBom
        )
        Protect-PrivateStateFile -Path $stateTemporaryPath
        Move-Item `
            -LiteralPath $stateTemporaryPath `
            -Destination $statePath `
            -Force
        Protect-PrivateStateFile -Path $statePath
    } finally {
        Remove-Item -LiteralPath $stateTemporaryPath -Force `
            -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host 'Prepared one shared Windows and Android ERP update:'
    Write-Host "  Source: $headSha"
    Write-Host "  Release-note base: $releaseNotesFromCommit"
    Write-Host 'VS Code can now start both protected publishers in parallel.'
} finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force `
        -ErrorAction SilentlyContinue
}
