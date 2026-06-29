[CmdletBinding()]
param(
    [string]$Repo = 'Ccatalan7/bikeshop-erp',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'VinabikeERP'),
    [switch]$Force,
    [switch]$Launch,
    [switch]$Prepare,
    [switch]$ApplyPrepared,
    [switch]$Quiet,
    [switch]$NoShortcuts,
    [int]$WaitForProcessId = 0
)

function Resolve-FullPath {
    param([string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

$script:InstallRoot = Resolve-FullPath $InstallRoot
$script:AppDir = Join-Path $script:InstallRoot 'app'
$script:DownloadDir = Join-Path $script:InstallRoot 'downloads'
$script:StateFile = Join-Path $script:InstallRoot 'current-release.json'
$script:PreparedDir = Join-Path $script:InstallRoot 'prepared'
$script:PreparedStateFile = Join-Path $script:InstallRoot 'prepared-release.json'
$script:InstallerPath = Join-Path $script:InstallRoot 'Install-VinabikeERP.ps1'
$script:LauncherPath = Join-Path $script:InstallRoot 'Launch-VinabikeERP.ps1'
$script:LogPath = Join-Path $script:InstallRoot 'updater.log'
$script:UpdateMutex = $null
$script:HasUpdateMutex = $false

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Log {
    param([string]$Message)

    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz'
        Add-Content -LiteralPath $script:LogPath -Value "[$timestamp] $Message"
    } catch {
        # Logging must never block an install.
    }
}

function Write-Info {
    param([string]$Message)

    Write-Log $Message

    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Enter-UpdateMutex {
    param([int]$TimeoutSeconds = 300)

    $script:UpdateMutex = [System.Threading.Mutex]::new($false, 'Local\VinabikeERPUpdateMutex')

    try {
        if (-not $script:UpdateMutex.WaitOne(0)) {
            Write-Info 'Another Vinabike ERP update process is running; waiting for it to finish...'
            if (-not $script:UpdateMutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
                throw "Timed out waiting for another Vinabike ERP update process after $TimeoutSeconds seconds."
            }
        }

        $script:HasUpdateMutex = $true
    } catch [System.Threading.AbandonedMutexException] {
        $script:HasUpdateMutex = $true
        Write-Info 'Recovered an abandoned Vinabike ERP update lock.'
    }
}

function Exit-UpdateMutex {
    if ($script:HasUpdateMutex -and $null -ne $script:UpdateMutex) {
        $script:UpdateMutex.ReleaseMutex() | Out-Null
        $script:HasUpdateMutex = $false
    }

    if ($null -ne $script:UpdateMutex) {
        $script:UpdateMutex.Dispose()
        $script:UpdateMutex = $null
    }
}

function Assert-UnderInstallRoot {
    param([string]$Path)

    $fullPath = Resolve-FullPath $Path
    $root = $script:InstallRoot.TrimEnd('\')
    $rootWithSlash = "$root\"

    if ($fullPath -ne $root -and -not $fullPath.StartsWith($rootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to touch path outside install root: $fullPath"
    }
}

function Remove-SafeItem {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Assert-UnderInstallRoot $Path
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Clear-DownloadCache {
    if (-not (Test-Path -LiteralPath $script:DownloadDir)) {
        return
    }

    Get-ChildItem -LiteralPath $script:DownloadDir -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'extract-*' -or
            $_.Name -like 'vinabike_erp_windows_*.zip' -or
            $_.Name -like 'vinabike_erp_windows_*.zip.sha256'
        } |
        ForEach-Object {
            try {
                Remove-SafeItem $_.FullName
            } catch {
                Write-Log "Could not remove download cache item $($_.FullName): $($_.Exception.Message)"
            }
        }
}

function Invoke-GitHubJson {
    param([string]$Uri)

    return Invoke-RestMethod -Uri $Uri -Headers @{ 'User-Agent' = 'VinabikeERP-Updater' }
}

function Save-Download {
    param(
        [string]$Uri,
        [string]$OutFile
    )

    Assert-UnderInstallRoot $OutFile
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -Headers @{ 'User-Agent' = 'VinabikeERP-Updater' }
}

function Get-ManagedAppProcesses {
    $expectedExe = Resolve-FullPath (Join-Path $script:AppDir 'vinabike_erp.exe')

    Get-Process -Name 'vinabike_erp' -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and ((Resolve-FullPath $_.Path) -eq $expectedExe)
        } catch {
            $false
        }
    }
}

function Wait-ManagedAppProcessesToExit {
    param([int]$TimeoutSeconds = 120)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $running = @(Get-ManagedAppProcesses)
        if ($running.Count -eq 0) {
            return
        }

        Write-Info "Waiting for managed Vinabike ERP processes to exit: $($running.Id -join ', ')"
        Start-Sleep -Seconds 1
    }

    $remaining = @(Get-ManagedAppProcesses)
    if ($remaining.Count -gt 0) {
        throw "Vinabike ERP is still running from the managed install: $($remaining.Id -join ', ')"
    }
}

function Stop-UpdaterBootstrapShells {
    try {
        $shells = Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*Start-VinabikeERPUpdate.cmd*' }

        foreach ($shell in @($shells)) {
            Write-Info "Stopping stale updater shell $($shell.ProcessId)..."
            Stop-Process -Id $shell.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Info "Could not inspect stale updater shells: $($_.Exception.Message)"
    }
}

function Invoke-WithRetry {
    param(
        [string]$Description,
        [scriptblock]$Operation,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 1
    $lastError = $null

    while ((Get-Date) -lt $deadline) {
        try {
            & $Operation
            return
        } catch {
            $lastError = $_
            Write-Info "${Description} failed on attempt ${attempt}: $($_.Exception.Message)"
            Start-Sleep -Milliseconds 750
            $attempt += 1
        }
    }

    if ($lastError) {
        throw $lastError
    }
}

function Get-ExpectedHash {
    param([string]$HashFile)

    $hashText = Get-Content -LiteralPath $HashFile -Raw
    $match = [regex]::Match($hashText, '[A-Fa-f0-9]{64}')
    if (-not $match.Success) {
        throw "Could not read SHA256 from $HashFile"
    }

    return $match.Value.ToUpperInvariant()
}

function Get-InstalledTag {
    if (-not (Test-Path -LiteralPath $script:StateFile)) {
        return $null
    }

    try {
        $state = Get-Content -LiteralPath $script:StateFile -Raw | ConvertFrom-Json
        return $state.tag_name
    } catch {
        return $null
    }
}

function Copy-InstallerToInstallRoot {
    if (-not $PSCommandPath) {
        return
    }

    New-Item -ItemType Directory -Force -Path $script:InstallRoot | Out-Null
    $source = Resolve-FullPath $PSCommandPath
    $target = Resolve-FullPath $script:InstallerPath

    if ($source -ne $target) {
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Write-LauncherScript {
    New-Item -ItemType Directory -Force -Path $script:InstallRoot | Out-Null

    $launcher = @'
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $root 'Install-VinabikeERP.ps1'
$app = Join-Path $root 'app\vinabike_erp.exe'

if (-not (Test-Path -LiteralPath $app) -and (Test-Path -LiteralPath $installer)) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Force
}

if (-not (Test-Path -LiteralPath $app)) {
    throw "Vinabike ERP is not installed at $app"
}

Start-Process -FilePath $app -WorkingDirectory (Split-Path -Parent $app)
'@

    Set-Content -LiteralPath $script:LauncherPath -Value $launcher -Encoding UTF8
}

function New-AppShortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconPath
    )

    $parent = Split-Path -Parent $ShortcutPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.WindowStyle = 7
    if (Test-Path -LiteralPath $IconPath) {
        $shortcut.IconLocation = $IconPath
    }
    $shortcut.Save()
}

function Ensure-Shortcuts {
    if ($NoShortcuts) {
        return
    }

    $exePath = Join-Path $script:AppDir 'vinabike_erp.exe'
    $powerShellPath = (Get-Command powershell.exe).Source
    $launcherArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:LauncherPath`""
    $updaterArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$script:InstallerPath`" -Launch"

    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

    New-AppShortcut `
        -ShortcutPath (Join-Path $desktop 'Vinabike ERP.lnk') `
        -TargetPath $powerShellPath `
        -Arguments $launcherArgs `
        -WorkingDirectory $script:InstallRoot `
        -IconPath $exePath

    New-AppShortcut `
        -ShortcutPath (Join-Path $programs 'Vinabike ERP.lnk') `
        -TargetPath $powerShellPath `
        -Arguments $launcherArgs `
        -WorkingDirectory $script:InstallRoot `
        -IconPath $exePath

    New-AppShortcut `
        -ShortcutPath (Join-Path $programs 'Actualizar Vinabike ERP.lnk') `
        -TargetPath $powerShellPath `
        -Arguments $updaterArgs `
        -WorkingDirectory $script:InstallRoot `
        -IconPath $exePath
}

function Get-LatestRelease {
    $releases = Invoke-GitHubJson "https://api.github.com/repos/$Repo/releases?per_page=30"

    foreach ($release in @($releases)) {
        if ($release.draft -or $release.prerelease -or -not $release.assets) {
            continue
        }

        $zipAsset = $release.assets |
            Where-Object { $_.name -match '^vinabike_erp_windows_.*\.zip$' } |
            Select-Object -First 1

        if (-not $zipAsset) {
            continue
        }

        $hashAssetName = "$($zipAsset.name).sha256"
        $hashAsset = $release.assets |
            Where-Object { $_.name -eq $hashAssetName } |
            Select-Object -First 1

        if (-not $hashAsset) {
            continue
        }

        return [pscustomobject]@{
            Tag = $release.tag_name
            Name = $release.name
            ZipAsset = $zipAsset
            HashAsset = $hashAsset
        }
    }

    throw "No published GitHub release for $Repo contains a Windows zip and checksum."
}

function Copy-StagedAppInPlace {
    param([string]$StagingDir)

    Write-Info 'Applying release in place because the app folder is still locked.'
    New-Item -ItemType Directory -Force -Path $script:AppDir | Out-Null

    Get-ChildItem -LiteralPath $StagingDir -Force | ForEach-Object {
        $source = $_.FullName
        Invoke-WithRetry `
            -Description "Copying $($_.Name)" `
            -TimeoutSeconds 120 `
            -Operation {
                Copy-Item -LiteralPath $source -Destination $script:AppDir -Recurse -Force
            }
    }
}

function Test-StagedApp {
    param([string]$StagingDir)

    if (-not (Test-Path -LiteralPath (Join-Path $StagingDir 'vinabike_erp.exe'))) {
        throw 'Staged app is missing vinabike_erp.exe.'
    }

    if (-not (Test-Path -LiteralPath (Join-Path $StagingDir 'data'))) {
        throw 'Staged app is missing the Flutter data folder.'
    }
}

function New-StagedRelease {
    param(
        [pscustomobject]$Release,
        [string]$StagingDir
    )

    New-Item -ItemType Directory -Force -Path $script:DownloadDir | Out-Null

    $zipPath = Join-Path $script:DownloadDir $Release.ZipAsset.name
    $hashPath = Join-Path $script:DownloadDir $Release.HashAsset.name

    Write-Info "Downloading $($Release.ZipAsset.name)..."
    Save-Download -Uri $Release.ZipAsset.browser_download_url -OutFile $zipPath
    Save-Download -Uri $Release.HashAsset.browser_download_url -OutFile $hashPath

    Write-Info 'Verifying SHA256 checksum...'
    $expectedHash = Get-ExpectedHash $hashPath
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()

    if ($actualHash -ne $expectedHash) {
        throw "SHA256 mismatch. Expected $expectedHash but got $actualHash."
    }

    $extractDir = Join-Path $script:DownloadDir ("extract-" + [guid]::NewGuid().ToString('N'))

    Remove-SafeItem $extractDir
    Remove-SafeItem $StagingDir
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

    Write-Info 'Extracting release...'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $exe = Get-ChildItem -LiteralPath $extractDir -Filter 'vinabike_erp.exe' -Recurse |
        Select-Object -First 1

    if (-not $exe) {
        throw 'The downloaded zip does not contain vinabike_erp.exe.'
    }

    $releaseRoot = $exe.Directory.FullName
    Get-ChildItem -LiteralPath $releaseRoot | Copy-Item -Destination $StagingDir -Recurse -Force

    Test-StagedApp $StagingDir

    try {
        Remove-SafeItem $extractDir
    } catch {
        Write-Info "Could not remove temporary extract folder $extractDir`: $($_.Exception.Message)"
    }
    Remove-Item -LiteralPath $zipPath, $hashPath -Force -ErrorAction SilentlyContinue
}

function Get-PreparedReleaseState {
    if (-not (Test-Path -LiteralPath $script:PreparedStateFile)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $script:PreparedStateFile -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Prepare-Release {
    param([pscustomobject]$Release)

    $preparedAppDir = Join-Path $script:PreparedDir 'app'
    $state = Get-PreparedReleaseState

    if ($state -and $state.tag_name -eq $Release.Tag) {
        try {
            Test-StagedApp $preparedAppDir
            Write-Info "Vinabike ERP release $($Release.Tag) is already prepared."
            return
        } catch {
            Write-Info "Prepared update is invalid and will be rebuilt: $($_.Exception.Message)"
        }
    }

    Remove-SafeItem $script:PreparedDir
    New-Item -ItemType Directory -Force -Path $script:PreparedDir | Out-Null

    Write-Info "Preparing Vinabike ERP release $($Release.Tag)..."
    New-StagedRelease -Release $Release -StagingDir $preparedAppDir

    $preparedState = [ordered]@{
        tag_name = $Release.Tag
        release_name = $Release.Name
        asset_name = $Release.ZipAsset.name
        app_dir = $preparedAppDir
        prepared_at = (Get-Date).ToString('o')
        install_root = $script:InstallRoot
    }

    $preparedState | ConvertTo-Json | Set-Content -LiteralPath $script:PreparedStateFile -Encoding UTF8
    Write-Info "Prepared Vinabike ERP release $($Release.Tag)."
}

function Install-StagedRelease {
    param(
        [pscustomobject]$Release,
        [string]$StagingDir
    )

    $running = @(Get-ManagedAppProcesses)
    if ($running) {
        if ($Quiet) {
            Write-Info 'Vinabike ERP is running; skipping update check.'
            return
        }

        throw 'Close Vinabike ERP before updating it, then run this installer again.'
    }

    Test-StagedApp $StagingDir
    $previousDir = Join-Path $script:InstallRoot 'app.previous'

    Write-Info 'Installing release...'
    $installedInPlace = $false
    try {
        Invoke-WithRetry `
            -Description 'Removing previous app backup' `
            -Operation { Remove-SafeItem $previousDir }

        if (Test-Path -LiteralPath $script:AppDir) {
            Assert-UnderInstallRoot $script:AppDir
            Assert-UnderInstallRoot $previousDir

            try {
                Invoke-WithRetry `
                    -Description 'Moving current app to backup' `
                    -TimeoutSeconds 20 `
                    -Operation {
                        Move-Item -LiteralPath $script:AppDir -Destination $previousDir -Force
                    }
            } catch {
                Write-Info "Could not move the current app folder: $($_.Exception.Message)"
                Copy-StagedAppInPlace $StagingDir
                $installedInPlace = $true
            }
        }

        if (-not $installedInPlace) {
            Assert-UnderInstallRoot $StagingDir
            Assert-UnderInstallRoot $script:AppDir
            Invoke-WithRetry `
                -Description 'Promoting staged app' `
                -Operation {
                    Move-Item -LiteralPath $StagingDir -Destination $script:AppDir -Force
                }
        }
    } catch {
        if (-not (Test-Path -LiteralPath $script:AppDir) -and (Test-Path -LiteralPath $previousDir)) {
            Invoke-WithRetry `
                -Description 'Restoring previous app after failed install' `
                -Operation {
                    Move-Item -LiteralPath $previousDir -Destination $script:AppDir -Force
                }
        }

        throw
    }

    $state = [ordered]@{
        tag_name = $Release.Tag
        release_name = $Release.Name
        asset_name = $Release.ZipAsset.name
        installed_at = (Get-Date).ToString('o')
        install_root = $script:InstallRoot
    }

    $state | ConvertTo-Json | Set-Content -LiteralPath $script:StateFile -Encoding UTF8
}

function Install-PreparedRelease {
    param([pscustomobject]$Release)

    $state = Get-PreparedReleaseState
    if (-not $state -or $state.tag_name -ne $Release.Tag -or -not $state.app_dir) {
        return $false
    }

    $preparedAppDir = Resolve-FullPath $state.app_dir
    Assert-UnderInstallRoot $preparedAppDir

    Write-Info "Applying prepared Vinabike ERP release $($Release.Tag)..."
    Install-StagedRelease -Release $Release -StagingDir $preparedAppDir
    Remove-SafeItem $script:PreparedDir
    Remove-Item -LiteralPath $script:PreparedStateFile -Force -ErrorAction SilentlyContinue
    return $true
}

function Install-Release {
    param([pscustomobject]$Release)

    $stagingDir = Join-Path $script:InstallRoot 'app.new'

    New-StagedRelease -Release $Release -StagingDir $stagingDir
    Install-StagedRelease -Release $Release -StagingDir $stagingDir
    Remove-SafeItem $stagingDir
}

New-Item -ItemType Directory -Force -Path $script:InstallRoot | Out-Null
Copy-InstallerToInstallRoot
Write-LauncherScript
Write-Log "Starting updater. Force=$Force Launch=$Launch Prepare=$Prepare ApplyPrepared=$ApplyPrepared Quiet=$Quiet NoShortcuts=$NoShortcuts WaitForProcessId=$WaitForProcessId"

Enter-UpdateMutex
try {
    if ($WaitForProcessId -gt 0) {
        Write-Info "Waiting for Vinabike ERP process $WaitForProcessId to exit..."
        try {
            Wait-Process -Id $WaitForProcessId -Timeout 60 -ErrorAction SilentlyContinue
        } catch {
            # If the process already exited, continue with the update.
        }

        Wait-ManagedAppProcessesToExit
    }

    Stop-UpdaterBootstrapShells

    $latest = Get-LatestRelease
    $installedTag = Get-InstalledTag
    $exePath = Join-Path $script:AppDir 'vinabike_erp.exe'

    if ($Prepare) {
        if ($installedTag -eq $latest.Tag -and (Test-Path -LiteralPath $exePath)) {
            Write-Info "Vinabike ERP is already current: $installedTag"
        } else {
            Prepare-Release $latest
        }

        Ensure-Shortcuts
        Write-Info "Done. Prepared update at $script:PreparedDir"
        return
    }

    if (-not $Force -and $installedTag -eq $latest.Tag -and (Test-Path -LiteralPath $exePath)) {
        Write-Info "Vinabike ERP is already current: $installedTag"
    } else {
        if ($ApplyPrepared) {
            $appliedPrepared = Install-PreparedRelease $latest
            if (-not $appliedPrepared) {
                Write-Info "No prepared update found for $($latest.Tag); falling back to full install."
                Install-Release $latest
            }
        } else {
            Write-Info "Installing Vinabike ERP release $($latest.Tag)..."
            Install-Release $latest
        }
    }

    Ensure-Shortcuts

    if ($Launch) {
        Start-Process -FilePath (Join-Path $script:AppDir 'vinabike_erp.exe') -WorkingDirectory $script:AppDir
    }

    Write-Info "Done. Installed at $script:AppDir"
} finally {
    Clear-DownloadCache
    Exit-UpdateMutex
}
