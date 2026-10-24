#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
Run INSIDE the Windows 11 gaming VM, using Windows PowerShell as administrator.
Removes selected inbox consumer apps, Xbox/Store apps, and OneDrive.
Preserves RAID, Plarium Play, Steam, drivers, Guest Additions, Windows components,
Defender, servicing, App Installer, codecs, .NET, Visual C++, DirectX and WebView2.
Does not force-remove Microsoft Edge or any protected Windows package.
Use -Preview to list the proposed removals without uninstalling anything.
App removal also removes that app's local data. A VM snapshot is recommended.
#>
[CmdletBinding()]
param([switch]$Preview,[string]$ResultPath)

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -eq 'DESKTOP-IMKRT09') {
    throw 'This is the real host PC. Copy this script into the gaming VM and run it there.'
}

$appNames = @(
    'Clipchamp.Clipchamp'
    'Microsoft.3DBuilder'
    'Microsoft.549981C3F5F10'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.Copilot'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.MixedReality.Portal'
    'Microsoft.Office.OneNote'
    'Microsoft.OneConnect'
    'Microsoft.OutlookForWindows'
    'Microsoft.Paint'
    'Microsoft.MSPaint'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Print3D'
    'Microsoft.ScreenSketch'
    'Microsoft.SkypeApp'
    'Microsoft.Todos'
    'Microsoft.Windows.DevHome'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsCalculator'
    'Microsoft.WindowsCamera'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsNotepad'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.Windows.Photos'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'microsoft.windowscommunicationsapps'
    'MicrosoftTeams'
    'MSTeams'
    'MicrosoftCorporationII.MicrosoftFamily'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.GamingApp'
    'Microsoft.GamingServices'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.WindowsStore'
    'Microsoft.StorePurchaseApp'
)
$targets = @{}
foreach ($appName in $appNames) { $targets[$appName] = $true }
$installed = @(Get-AppxPackage -AllUsers -PackageTypeFilter Main,Bundle)
$provisioned = @(Get-AppxProvisionedPackage -Online)
$toRemove = @($installed | Where-Object {
    $targets.ContainsKey($_.Name) -and -not $_.IsFramework -and -not $_.NonRemovable
})
$toDeprovision = @($provisioned | Where-Object { $targets.ContainsKey($_.DisplayName) })

if ($Preview) {
    Write-Host 'INSTALLED APP PACKAGES TO REMOVE:' -ForegroundColor Cyan
    $toRemove | Select-Object Name,PackageFullName | Format-Table -AutoSize
    Write-Host 'PROVISIONED PACKAGES TO REMOVE FOR FUTURE USER ACCOUNTS:' -ForegroundColor Cyan
    $toDeprovision | Select-Object DisplayName,PackageName | Format-Table -AutoSize
    Write-Host 'OneDrive will also be uninstalled if a signed setup program is available.'
    Write-Host 'Preview only: no apps were removed.' -ForegroundColor Green
    if ($ResultPath) {
        [pscustomobject]@{Success=$true;Partial=$false;Message=('Chỉ xem trước: '+$toRemove.Count+' gói app hiện có và '+$toDeprovision.Count+' gói dự phòng; chưa gỡ app.');Results=@($toRemove|Select-Object Name,PackageFullName);RebootRequired=$false} |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    }
    return
}

$logFolder = Join-Path $env:ProgramData ('RaidVM-Cleanup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
$installed | Select-Object Name,PackageFullName,InstallLocation | Export-Csv -LiteralPath (Join-Path $logFolder 'installed-before.csv') -NoTypeInformation -Encoding UTF8
$provisioned | Select-Object DisplayName,PackageName | Export-Csv -LiteralPath (Join-Path $logFolder 'provisioned-before.csv') -NoTypeInformation -Encoding UTF8
$results = New-Object 'System.Collections.Generic.List[object]'
function Add-Result([string]$stage,[string]$name,[string]$status,[string]$detail) {
    $results.Add([pscustomobject]@{Stage=$stage;Name=$name;Status=$status;Detail=$detail})
    $results | Export-Csv -LiteralPath (Join-Path $logFolder 'results.csv') -NoTypeInformation -Encoding UTF8
}

foreach ($group in @($toRemove | Group-Object Name)) {
    $packages = @($group.Group | Where-Object { $_.IsBundle })
    if (-not $packages.Count) { $packages = @($group.Group) }
    foreach ($package in @($packages | Sort-Object PackageFullName -Unique)) {
        Write-Host ('Removing ' + $package.Name)
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            Add-Result 'InstalledApp' $package.Name 'Removed' $package.PackageFullName
        } catch {
            Add-Result 'InstalledApp' $package.Name 'NotRemoved' $_.Exception.Message
            Write-Warning ($package.Name + ': ' + $_.Exception.Message)
        }
    }
}
foreach ($package in $toDeprovision) {
    try {
        $null = Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop
        Add-Result 'Provisioning' $package.DisplayName 'Removed' $package.PackageName
    } catch {
        Add-Result 'Provisioning' $package.DisplayName 'NotRemoved' $_.Exception.Message
        Write-Warning ($package.DisplayName + ': ' + $_.Exception.Message)
    }
}

$setupCandidates = New-Object 'System.Collections.Generic.List[string]'
foreach ($setupRoot in @((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'),(Join-Path $env:ProgramFiles 'Microsoft OneDrive'))) {
    if (Test-Path -LiteralPath $setupRoot) {
        Get-ChildItem -LiteralPath $setupRoot -Filter 'OneDriveSetup.exe' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $setupCandidates.Add($_.FullName) }
    }
}
foreach ($setupPath in @((Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),(Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'))) {
    if (Test-Path -LiteralPath $setupPath) { $setupCandidates.Add($setupPath) }
}
$signedSetup = $null
foreach ($candidate in $setupCandidates) {
    $signature = Get-AuthenticodeSignature -LiteralPath $candidate
    if ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match 'O=Microsoft Corporation') { $signedSetup = $candidate; break }
}
if ($signedSetup) {
    try {
        Write-Host 'Running the Microsoft OneDrive uninstaller.'
        $uninstaller = Start-Process -FilePath $signedSetup -ArgumentList '/uninstall' -WindowStyle Hidden -Wait -PassThru
        $status = 'UninstallerReturned'
        if ($uninstaller.ExitCode -notin @(0,3010)) { $status = 'CheckExitCode' }
        Add-Result 'OneDrive' 'Microsoft OneDrive' $status ('Exit code: ' + $uninstaller.ExitCode + '; setup: ' + $signedSetup)
    } catch { Add-Result 'OneDrive' 'Microsoft OneDrive' 'NotRemoved' $_.Exception.Message }
} else { Add-Result 'OneDrive' 'Microsoft OneDrive' 'Skipped' 'No signed Microsoft OneDrive uninstaller found; no folders were deleted.' }

$remaining = @(Get-AppxPackage -AllUsers -PackageTypeFilter Main,Bundle | Where-Object { $targets.ContainsKey($_.Name) })
$remaining | Select-Object Name,PackageFullName,NonRemovable | Export-Csv -LiteralPath (Join-Path $logFolder 'target-apps-remaining.csv') -NoTypeInformation -Encoding UTF8
Write-Host ''
Write-Host 'Cleanup finished. Protected apps or packages with uninstall errors may remain.' -ForegroundColor Green
Write-Host ('Logs: ' + $logFolder)
Write-Host 'Your RAID/Plarium installation, game runtimes, drivers and Guest Additions were preserved.'
Write-Host 'No automatic restart was performed. Run this once per new Windows VM; repeat only if needed after an update.'
if ($ResultPath) {
    $failed=@($results | Where-Object {$_.Status -in @('NotRemoved','CheckExitCode')})
    [pscustomobject]@{Success=($failed.Count -eq 0);Partial=($failed.Count -gt 0 -and $failed.Count -lt $results.Count);Message=('Đã xử lý danh sách app; có '+$failed.Count+' thao tác cần kiểm tra. Xem nhật ký để biết app còn lại.');Results=@($results.ToArray());LogFolder=$logFolder;RebootRequired=$false} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}
