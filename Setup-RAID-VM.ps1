#Requires -Version 5.1
<#
Run in an elevated Windows PowerShell window INSIDE the x64 Windows 11 VM.
Installs missing Chrome and WinRAR from their official vendors, then runs cleanup.
WinRAR is a trial; this script does not provide or activate a license.
-Preview lists cleanup targets and planned installations without installing/removing apps.
#>
[CmdletBinding()]
param([switch]$Preview)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -eq 'DESKTOP-IMKRT09') {
    throw 'This is the real host PC. Run this command inside the gaming VM instead.'
}
$taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$taskPrincipal = New-Object Security.Principal.WindowsPrincipal($taskIdentity)
if (-not $taskPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open Windows PowerShell with Run as administrator INSIDE the VM, then retry.'
}
if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'Use 64-bit Windows PowerShell on an x64 Windows VM. ARM64 is not supported by this setup.'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$setupFolder = Join-Path $env:ProgramData ('RaidVM-Setup\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $setupFolder -Force | Out-Null
$cleanupPath = Join-Path $setupFolder 'Debloat-Win11-RAID.ps1'
# Pin the reviewed cleanup version so its behavior does not change unexpectedly.
$cleanupUri = 'https://raw.githubusercontent.com/bazkoba/raid-win11-vm-cleanup/3ac260d93822a2567fec375e930e669e71dc23e5/Debloat-Win11-RAID.ps1'
$cleanupHash = '76D04475569829B5485FEE028DEEA2D6F1F87E14F2CC06EFAD7888CE78473FEC'
Write-Host 'Downloading the reviewed RAID cleanup script...' -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing -Uri $cleanupUri -OutFile $cleanupPath
if ((Get-FileHash -LiteralPath $cleanupPath -Algorithm SHA256).Hash -ne $cleanupHash) {
    throw 'Cleanup script hash mismatch. Stopped before installing or removing anything.'
}

$chromePaths = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
$winrarPath = Join-Path $env:ProgramFiles 'WinRAR\WinRAR.exe'
$chromePresent = @($chromePaths | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
$winrarPresent = Test-Path -LiteralPath $winrarPath
$powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

if ($Preview) {
    Write-Host ('Chrome already present: ' + $chromePresent + '; WinRAR already present: ' + $winrarPresent)
    Write-Host 'Normal run installs missing Chrome and WinRAR, then removes the listed inbox apps.'
    & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $cleanupPath -Preview
    if ($LASTEXITCODE -ne 0) { throw 'Cleanup preview failed. See the output above.' }
    Write-Host ('Preview finished. Downloaded script: ' + $cleanupPath)
    return
}

function Get-VerifiedInstaller([string]$Uri,[string]$Destination,[string]$PublisherPattern) {
    Write-Host ('Downloading: ' + $Uri)
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
    $signature = Get-AuthenticodeSignature -LiteralPath $Destination
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $PublisherPattern) {
        throw ('Installer signature check failed: ' + $Destination + '. No installer was launched by this download step.')
    }
    Write-Host ('Verified publisher: ' + $signature.SignerCertificate.Subject)
}

# Download and verify every required installer before changing installed apps.
$chromeInstaller = Join-Path $setupFolder 'Chrome-x64.msi'
$winrarInstaller = Join-Path $setupFolder 'WinRAR-x64.exe'
if (-not $chromePresent) {
    Get-VerifiedInstaller 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' $chromeInstaller 'O="?Google (LLC|Inc\.)"?(,|$)'
}
if (-not $winrarPresent) {
    $downloadPage = Invoke-WebRequest -UseBasicParsing -Uri 'https://www.rarlab.com/download.htm'
    # Match the English stable x64 release only; beta and localized filenames differ.
    $releaseMatch = [regex]::Match($downloadPage.Content, 'href\s*=\s*["''](?<path>/rar/winrar-x64-\d+\.exe)["'']', 'IgnoreCase')
    if (-not $releaseMatch.Success) {
        throw 'Cannot find the stable WinRAR x64 download on rarlab.com. Stopped before cleanup.'
    }
    $winrarUri = 'https://www.rarlab.com' + $releaseMatch.Groups['path'].Value
    Get-VerifiedInstaller $winrarUri $winrarInstaller 'O="?(win\.rar|WinRAR) GmbH"?(,|$)'
}

if (-not $chromePresent) {
    Write-Host 'Installing Google Chrome...' -ForegroundColor Cyan
    $chromeLog = Join-Path $setupFolder 'chrome-install.log'
    $msiArguments = '/i "' + $chromeInstaller + '" /qn /norestart /L*v "' + $chromeLog + '"'
    $chromeProcess = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList $msiArguments -WindowStyle Hidden -Wait -PassThru
    if ($chromeProcess.ExitCode -notin @(0,3010)) {
        throw ('Chrome installation failed; exit code ' + $chromeProcess.ExitCode + '. Log: ' + $chromeLog + '. Cleanup has not run.')
    }
    if (-not @($chromePaths | Where-Object { Test-Path -LiteralPath $_ }).Count) {
        throw 'Chrome executable was not found after installation. Cleanup has not run.'
    }
} else { Write-Host 'Chrome is already installed; keeping the existing installation.' }

if (-not $winrarPresent) {
    Write-Host 'Installing WinRAR (trial)...' -ForegroundColor Cyan
    $winrarProcess = Start-Process -FilePath $winrarInstaller -ArgumentList '/S' -WindowStyle Hidden -Wait -PassThru
    if ($winrarProcess.ExitCode -notin @(0,3010) -or -not (Test-Path -LiteralPath $winrarPath)) {
        throw ('WinRAR installation could not be verified; exit code ' + $winrarProcess.ExitCode + '. Cleanup has not run.')
    }
} else { Write-Host 'WinRAR is already installed; keeping the existing installation.' }

Write-Host 'Chrome and WinRAR are present. Starting Windows app cleanup...' -ForegroundColor Cyan
& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $cleanupPath
if ($LASTEXITCODE -ne 0) { throw 'Cleanup failed. See the output above; Chrome/WinRAR may already be installed.' }
Write-Host ''
Write-Host 'Setup finished. Review any cleanup warnings above, then restart the VM when convenient.' -ForegroundColor Green
Write-Host ('Setup files and installer log: ' + $setupFolder)
Write-Host 'No automatic reboot. RAID and Plarium Play are not installed by this setup.'
