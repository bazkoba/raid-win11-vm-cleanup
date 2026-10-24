#Requires -Version 5.1
<#
ASCII-only entry point for Windows PowerShell 5.1.
Downloads a pinned, hash-verified toolkit, then opens its Vietnamese GUI.
Opening this launcher does not install/remove apps or change Windows settings.
#>
[CmdletBinding()]
param([switch]$Demo,[switch]$DownloadOnly)

$ErrorActionPreference='Stop'
$bundleCommit='ac67f73f1972f3bef7f69ae0e737501d44649219'
$manifestSha256='C1F83E3551A129EF69AE31583E5B748CE5BDE7C9E3B81F448C01699A79A6E77E'
$script:RaidToolkitSource='https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup'
$script:RaidToolkitFiles=@(
    'RAID-Toolkit.ps1'
    'Invoke-RAID-Task.ps1'
    'Install-RAID-Apps.ps1'
    'Manage-RAID-Update.ps1'
    'Debloat-Win11-RAID.ps1'
    'Optimize-RAID-UI.ps1'
)

function ConvertTo-RaidCanonicalText([byte[]]$Bytes) {
    # Fail closed on invalid UTF-8 instead of replacing damaged Vietnamese text.
    $decoder=New-Object Text.UTF8Encoding($false,$true)
    $value=$decoder.GetString($Bytes)
    if ($value.Length -gt 0 -and [int]$value[0] -eq 0xfeff) { $value=$value.Substring(1) }
    return $value.Replace("`r`n","`n").TrimEnd([char[]]@("`r","`n"))+"`n"
}

function Get-RaidCanonicalHash([byte[]]$Bytes) {
    $text=ConvertTo-RaidCanonicalText $Bytes
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($text))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-RaidBootstrapBytes([string]$Uri) {
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client=New-Object Net.WebClient
    try { return ,($client.DownloadData($Uri)) }
    finally { $client.Dispose() }
}

function Save-RaidCanonicalFile([string]$Path,[string]$Text) {
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        # The cache is UTF-8 BOM so -File uses the same text under every locale.
        [IO.File]::WriteAllText($temporary,$Text,(New-Object Text.UTF8Encoding($true)))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Assert-RaidBootstrapPlatform([bool]$AllowKnownHost) {
    if (-not $AllowKnownHost -and $env:COMPUTERNAME -eq 'DESKTOP-IMKRT09') {
        throw 'This is the known real host PC. Run the launcher inside the Windows 11 VM. Use -Demo only for a non-operational preview.'
    }
    if (-not $AllowKnownHost -and ([Environment]::OSVersion.Version.Build -lt 22000 -or -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64')) {
        throw 'The production toolkit requires 64-bit Windows PowerShell in an x64 Windows 11 VM.'
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is unavailable; cannot choose a toolkit cache.' }
}

function Get-RaidVerifiedBundle([string]$Commit,[string]$ManifestHash,[string]$CacheBase) {
    if ($Commit -notmatch '^[0-9a-fA-F]{40}$' -or $ManifestHash -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'The toolkit release pins are missing or invalid. Download a published launcher.'
    }
    $root=Join-Path $CacheBase $Commit.ToLowerInvariant()
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $manifestPath=Join-Path $root 'Toolkit.manifest.json'
    $manifestBytes=$null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $cached=[IO.File]::ReadAllBytes($manifestPath)
            if ((Get-RaidCanonicalHash $cached) -ceq $ManifestHash.ToUpperInvariant()) { $manifestBytes=$cached }
        } catch { $manifestBytes=$null }
    }
    if ($null -eq $manifestBytes) {
        $manifestBytes=Get-RaidBootstrapBytes ($script:RaidToolkitSource+'/'+$Commit+'/Toolkit.manifest.json')
        if ((Get-RaidCanonicalHash $manifestBytes) -cne $ManifestHash.ToUpperInvariant()) { throw 'Toolkit manifest SHA-256 mismatch. Nothing was launched.' }
    }
    $manifestText=ConvertTo-RaidCanonicalText $manifestBytes
    $manifest=ConvertFrom-Json -InputObject $manifestText
    if ($manifest.Schema -ne 1 -or @($manifest.Files).Count -ne $script:RaidToolkitFiles.Count) {
        throw 'Unsupported toolkit manifest schema or file count. Nothing was launched.'
    }
    foreach ($file in @($manifest.Files)) {
        if ($file.Name -isnot [string] -or $script:RaidToolkitFiles -cnotcontains $file.Name -or $file.Sha256 -isnot [string] -or $file.Sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw 'The manifest contains an unexpected filename or invalid hash. Nothing was launched.'
        }
    }
    foreach ($required in $script:RaidToolkitFiles) {
        if (@($manifest.Files | Where-Object {$_.Name -ceq $required}).Count -ne 1) {
            throw 'The manifest contains duplicate or missing toolkit files. Nothing was launched.'
        }
    }
    # Validate the complete manifest before resolving any download destination.
    foreach ($file in @($manifest.Files)) {
        $destination=Join-Path $root $file.Name
        $bytes=$null
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            try {
                $cached=[IO.File]::ReadAllBytes($destination)
                if ((Get-RaidCanonicalHash $cached) -ceq $file.Sha256.ToUpperInvariant()) { $bytes=$cached }
            } catch { $bytes=$null }
        }
        if ($null -eq $bytes) {
            $bytes=Get-RaidBootstrapBytes ($script:RaidToolkitSource+'/'+$Commit+'/'+$file.Name)
            if ((Get-RaidCanonicalHash $bytes) -cne $file.Sha256.ToUpperInvariant()) {
                throw ('SHA-256 mismatch for '+$file.Name+'. Nothing was launched.')
            }
        }
        Save-RaidCanonicalFile $destination (ConvertTo-RaidCanonicalText $bytes)
    }
    Save-RaidCanonicalFile $manifestPath $manifestText
    # Recheck the saved files, including cache hits, immediately before launch.
    foreach ($file in @($manifest.Files)) {
        if ((Get-RaidCanonicalHash ([IO.File]::ReadAllBytes((Join-Path $root $file.Name)))) -cne $file.Sha256.ToUpperInvariant()) {
            throw ('Cached toolkit verification failed for '+$file.Name+'. Nothing was launched.')
        }
    }
    return [pscustomobject]@{Root=$root;Commit=$Commit.ToLowerInvariant();FilesVerified=@($manifest.Files).Count}
}

function Start-RaidToolkitWindow([string]$Root,[bool]$DemoMode) {
    $powerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $Root 'RAID-Toolkit.ps1')+'"'
    if ($DemoMode) { $arguments+=' -Demo' }
    $process=Start-Process -FilePath $powerShell -ArgumentList $arguments -WindowStyle Hidden -PassThru
    return $process.Id
}

function Invoke-RaidToolkitBootstrap([string]$Commit,[string]$ManifestHash,[switch]$DemoMode,[switch]$OnlyDownload) {
    Assert-RaidBootstrapPlatform ([bool]($DemoMode -or $OnlyDownload))
    $cacheBase=Join-Path $env:LOCALAPPDATA 'RaidVM-Toolkit\Releases'
    $bundle=Get-RaidVerifiedBundle $Commit $ManifestHash $cacheBase
    if ($OnlyDownload) {
        return ($bundle | ConvertTo-Json -Depth 4 -Compress)
    }
    $null=Start-RaidToolkitWindow $bundle.Root ([bool]$DemoMode)
    Write-Host 'RAID VM Toolkit opened. Choose an action in the window; no setup action runs automatically.'
}

try { Invoke-RaidToolkitBootstrap -Commit $bundleCommit -ManifestHash $manifestSha256 -DemoMode:$Demo -OnlyDownload:$DownloadOnly }
catch { throw ('RAID VM Toolkit could not start: '+$_.Exception.GetBaseException().Message) }
