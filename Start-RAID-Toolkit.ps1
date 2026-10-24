#Requires -Version 5.1
<#
ASCII-only entry point for Windows PowerShell 5.1.
Downloads a pinned, hash-verified toolkit, then opens its Vietnamese GUI.
Opening this launcher does not install/remove apps or change Windows settings.
#>
[CmdletBinding()]
param([switch]$Demo,[switch]$DownloadOnly)

$ErrorActionPreference='Stop'
$bundleCommit='34816f33a15365ea10d5a5f67237268d0b162113'
$manifestSha256='8715C7180819551990D9D27E208CCC6D65C36712EE73E0835EDC164878AC3002'
$script:RaidToolkitSource='https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup'
$script:RaidToolkitFiles=@(
    'RAID-Toolkit.ps1'
    'Invoke-RAID-Task.ps1'
    'Install-RAID-Apps.ps1'
    'Manage-RAID-Update.ps1'
    'Debloat-Win11-RAID.ps1'
    'Optimize-RAID-UI.ps1'
    'Optimize-RAID-Services.ps1'
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

function Start-RaidGuiProcess([string]$PowerShell,[string]$Arguments,[string]$StandardOutputPath,[string]$StandardErrorPath) {
    # Hide only PowerShell's console through its own argument. STARTUPINFO's
    # Hidden style can also suppress the first WinForms window on Windows 11.
    return Start-Process -FilePath $PowerShell -ArgumentList $Arguments -PassThru -RedirectStandardOutput $StandardOutputPath -RedirectStandardError $StandardErrorPath
}

function Get-RaidGuiProcessState([object]$Process) {
    $Process.Refresh()
    $exited=$Process.HasExited
    $exitCode=$null;$windowHandle=0L
    if ($exited) { $exitCode=$Process.ExitCode }
    else { $windowHandle=$Process.MainWindowHandle.ToInt64() }
    return [pscustomobject]@{Pid=$Process.Id;HasExited=$exited;ExitCode=$exitCode;WindowHandle=$windowHandle}
}

function Get-RaidGuiStartupFailure([string]$Message,[string]$LogDirectory) {
    $errorPath=Join-Path $LogDirectory 'stderr.log'
    if (Test-Path -LiteralPath $errorPath -PathType Leaf) {
        try {
            $details=[IO.File]::ReadAllText($errorPath).Trim()
            if ($details.Length -gt 4000) { $details=$details.Substring($details.Length-4000) }
            if ($details) { $Message+="`r`n"+$details }
        } catch { }
    }
    return ($Message+"`r`nStartup logs: "+$LogDirectory)
}

function Wait-RaidToolkitReady([object]$Process,[string]$StatusPath,[string]$LaunchId,[string]$LogDirectory,[int]$TimeoutSeconds=20,[int]$PollMilliseconds=100) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try {
        do {
            $status=$null
            if (Test-Path -LiteralPath $StatusPath -PathType Leaf) {
                # A report may be in the middle of an atomic file replacement.
                try { $status=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($StatusPath,[Text.Encoding]::UTF8)) } catch { }
            }
            try { $processState=Get-RaidGuiProcessState $Process }
            catch { throw (Get-RaidGuiStartupFailure ('Could not read the toolkit process status. '+$_.Exception.GetBaseException().Message) $LogDirectory) }
            if ($null -ne $status) {
                if ($status.LaunchId -cne $LaunchId -or [string]$status.Pid -cne [string]$processState.Pid) {
                    throw (Get-RaidGuiStartupFailure 'The startup report did not match the launched process.' $LogDirectory)
                }
                if ($status.State -ceq 'Failed') {
                    $message='The toolkit reported a startup error.'
                    if ($status.Message) { $message+=' '+[string]$status.Message }
                    if ($status.Error) { $message+="`r`n"+[string]$status.Error }
                    throw (Get-RaidGuiStartupFailure $message $LogDirectory)
                }
                if ($status.State -ceq 'AlreadyRunning') { return $status }
                if ($status.State -cne 'Ready') {
                    throw (Get-RaidGuiStartupFailure 'The toolkit returned an unsupported startup status.' $LogDirectory)
                }
                $reportedHandle=0L
                if (-not [long]::TryParse([string]$status.WindowHandle,[ref]$reportedHandle) -or $reportedHandle -le 0) {
                    throw (Get-RaidGuiStartupFailure 'The toolkit did not report a valid visible window handle.' $LogDirectory)
                }
                # Refreshing process metadata checks for a real visible window;
                # a JSON report alone must never cause a successful launch message.
                if (-not $processState.HasExited -and $processState.WindowHandle -gt 0 -and $processState.WindowHandle -eq $reportedHandle) {
                    return $status
                }
            }
            if ($processState.HasExited) {
                throw (Get-RaidGuiStartupFailure ('The toolkit process exited before its window was ready (exit code '+[string]$processState.ExitCode+').') $LogDirectory)
            }
            if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                throw (Get-RaidGuiStartupFailure ('No visible toolkit window was confirmed within '+$TimeoutSeconds+' seconds.') $LogDirectory)
            }
            Start-Sleep -Milliseconds $PollMilliseconds
        } while ($true)
    } finally { $timer.Stop() }
}

function Start-RaidToolkitWindow([string]$Root,[bool]$DemoMode) {
    $launchId=[guid]::NewGuid().ToString('N')
    $launchBase=Join-Path $env:LOCALAPPDATA 'RaidVM-Toolkit\Launches'
    $logDirectory=Join-Path $launchBase ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$launchId)
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $statusPath=Join-Path $logDirectory 'startup.json'
    $powerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $Root 'RAID-Toolkit.ps1')+'" -StartupStatusPath "'+$statusPath+'" -LaunchId "'+$launchId+'"'
    if ($DemoMode) { $arguments+=' -Demo' }
    try {
        $process=Start-RaidGuiProcess $powerShell $arguments (Join-Path $logDirectory 'stdout.log') (Join-Path $logDirectory 'stderr.log')
    } catch {
        throw (Get-RaidGuiStartupFailure ('PowerShell could not launch the toolkit. '+$_.Exception.GetBaseException().Message) $logDirectory)
    }
    try { return Wait-RaidToolkitReady $process $statusPath $launchId $logDirectory }
    finally { if ($process -is [Diagnostics.Process]) { $process.Dispose() } }
}

function Invoke-RaidToolkitBootstrap([string]$Commit,[string]$ManifestHash,[switch]$DemoMode,[switch]$OnlyDownload) {
    Assert-RaidBootstrapPlatform ([bool]($DemoMode -or $OnlyDownload))
    $cacheBase=Join-Path $env:LOCALAPPDATA 'RaidVM-Toolkit\Releases'
    $bundle=Get-RaidVerifiedBundle $Commit $ManifestHash $cacheBase
    if ($OnlyDownload) {
        return ($bundle | ConvertTo-Json -Depth 4 -Compress)
    }
    $startup=Start-RaidToolkitWindow $bundle.Root ([bool]$DemoMode)
    if ($startup.State -ceq 'Ready') {
        Write-Host 'RAID VM Toolkit opened. Choose an action in the window; no setup action runs automatically.'
    } elseif ($startup.State -ceq 'AlreadyRunning') {
        Write-Host ('RAID VM Toolkit is already running in this account. '+[string]$startup.Message)
    } else { throw 'The toolkit did not confirm that its window was ready.' }
}

try { Invoke-RaidToolkitBootstrap -Commit $bundleCommit -ManifestHash $manifestSha256 -DemoMode:$Demo -OnlyDownload:$DownloadOnly }
catch { throw ('RAID VM Toolkit could not start: '+$_.Exception.GetBaseException().Message) }
