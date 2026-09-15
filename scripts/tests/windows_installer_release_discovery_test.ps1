param(
    [string]$InstallerPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'install_vinabike_erp.ps1')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Load only the pure discovery function. Never run the installer's entry point,
# touch an installed app, or contact GitHub/production from this regression.
$parseTokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $InstallerPath, [ref]$parseTokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw 'The Windows installer does not parse.'
}
$discovery = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-LatestRelease'
}, $false)
if ($null -eq $discovery) {
    throw 'The installer discovery function is missing.'
}
Invoke-Expression $discovery.Extent.Text

$Repo = 'fixture/erp'
$script:Requests = [System.Collections.Generic.List[string]]::new()
$script:Feed = $null

function Invoke-GitHubJson {
    param([string]$Uri)
    $script:Requests.Add($Uri)
    # Invoke-RestMethod writes a JSON array as one pipeline object. Preserve
    # that real boundary rather than silently flattening fixture responses.
    return ,@(& $script:Feed $Uri)
}

function New-WindowsFixture {
    param(
        [string]$Tag = 'windows-v-fixture',
        [switch]$Draft,
        [switch]$Prerelease,
        [switch]$MissingChecksum
    )
    $zipName = 'vinabike_erp_windows_fixture.zip'
    $assets = @([pscustomobject]@{ name = $zipName })
    if (-not $MissingChecksum) {
        $assets += [pscustomobject]@{ name = "$zipName.sha256" }
    }
    return [pscustomobject]@{
        tag_name = $Tag
        name = 'Fixture Windows release'
        draft = [bool]$Draft
        prerelease = [bool]$Prerelease
        assets = $assets
    }
}

function Get-OtherPlatformPage {
    return @(1..100 | ForEach-Object {
        [pscustomobject]@{
            tag_name = "macos-v-fixture-$_"
            name = 'Fixture macOS release'
            draft = $false
            prerelease = $false
            assets = @([pscustomobject]@{ name = 'vinabike_erp_macos_fixture.zip' })
        }
    })
}

function Test-Discovery {
    param(
        [string]$Name,
        [scriptblock]$Feed,
        [int]$ExpectedRequests,
        [string]$ExpectedTag = '',
        [string]$ExpectedError = ''
    )
    $script:Requests.Clear()
    $script:Feed = $Feed
    $actualTag = ''
    $actualError = ''
    try {
        $actualTag = (Get-LatestRelease).Tag
    } catch {
        $actualError = $_.Exception.Message
    }
    if ($ExpectedError) {
        if (-not $actualError.Contains($ExpectedError)) {
            throw "$Name failed: expected '$ExpectedError', got '$actualError'."
        }
    } elseif ($actualError -or $actualTag -ne $ExpectedTag) {
        throw "$Name failed: tag '$actualTag', error '$actualError'."
    }
    if ($script:Requests.Count -ne $ExpectedRequests) {
        throw "$Name failed: $($script:Requests.Count) requests, expected $ExpectedRequests."
    }
    Write-Output "PASS: $Name"
}

Test-Discovery -Name 'Windows after a full macOS page' -ExpectedRequests 2 -ExpectedTag 'windows-v-fixture' -Feed {
    param($Uri)
    if ($Uri -match '&page=2$') {
        return New-WindowsFixture
    }
    return Get-OtherPlatformPage
}

Test-Discovery -Name 'First matching release stops pagination' -ExpectedRequests 1 -ExpectedTag 'windows-v-fixture' -Feed {
    param($Uri)
    if ($Uri -notmatch '\?per_page=100&page=1$') {
        throw 'Unexpected first-page request.'
    }
    return New-WindowsFixture
}

Test-Discovery -Name 'Draft, prerelease and missing checksum are not installed' -ExpectedRequests 1 -ExpectedTag 'windows-v-verified-fixture' -Feed {
    param($Uri)
    return @(
        (New-WindowsFixture -Tag 'windows-v-draft' -Draft),
        (New-WindowsFixture -Tag 'windows-v-prerelease' -Prerelease),
        (New-WindowsFixture -Tag 'windows-v-no-hash' -MissingChecksum),
        (New-WindowsFixture -Tag 'windows-v-verified-fixture')
    )
}

Test-Discovery -Name 'Empty feed ends immediately' -ExpectedRequests 1 -ExpectedError 'No published GitHub release' -Feed {
    param($Uri)
    return @()
}

Test-Discovery -Name 'Discovery has a ten-page request budget' -ExpectedRequests 10 -ExpectedError 'No published GitHub release' -Feed {
    param($Uri)
    return Get-OtherPlatformPage
}

Test-Discovery -Name 'Later-page network failures are not hidden' -ExpectedRequests 2 -ExpectedError 'upstream 503' -Feed {
    param($Uri)
    if ($Uri -match '&page=2$') {
        throw 'upstream 503'
    }
    return Get-OtherPlatformPage
}
