#Requires -Version 5.1
<#
Windows 11 VM: reversible automatic-update policy. Status is read-only.
Block sets ONLY NoAutoUpdate=1. Restore returns that value to its saved state.
Does not stop services, disable Defender, edit tasks/ACLs, or block every update route.
Manual updates and stronger domain/MDM policies can still apply.
https://learn.microsoft.com/en-us/windows/deployment/update/waas-wu-settings
https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-update#allowautoupdate
#>
[CmdletBinding()]
param(
    [ValidateSet('Status','Block','Restore')][string]$Action='Status',
    [string]$ResultPath
)

$ErrorActionPreference='Stop'
$script:RaidUpdateKey='SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$script:RaidUpdateValue='NoAutoUpdate'
$script:RaidUpdateBackupFolder=Join-Path $env:ProgramData 'RaidVM-Toolkit\Update'
$script:RaidUpdateBackupPath=Join-Path $script:RaidUpdateBackupFolder 'before.json'

function Get-RaidUpdateRegistrySnapshot([string]$Path,[string]$Name) {
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path,$false)
    try {
        $exists=$null -ne $key -and @($key.GetValueNames()) -contains $Name
        $kind=$null; $value=$null
        if ($exists) {
            $kind=$key.GetValueKind($Name).ToString()
            $value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        return [pscustomobject]@{Path=$Path;Name=$Name;Exists=$exists;Kind=$kind;Value=$value}
    } finally { if ($key) { $key.Dispose() } }
}

function Test-RaidUpdateSnapshotEqual($Left,$Right) {
    if ([bool]$Left.Exists -ne [bool]$Right.Exists) { return $false }
    if (-not $Left.Exists) { return $true }
    return $Left.Kind -eq $Right.Kind -and (ConvertTo-Json -InputObject $Left.Value -Depth 5 -Compress) -ceq (ConvertTo-Json -InputObject $Right.Value -Depth 5 -Compress)
}

function Assert-RaidUpdateEntry($Entry) {
    # Even a modified backup cannot redirect this elevated writer to another key.
    if ($null -eq $Entry -or $Entry.Path -cne $script:RaidUpdateKey -or $Entry.Name -cne $script:RaidUpdateValue -or $Entry.Exists -isnot [bool]) {
        throw 'Mục sao lưu Windows Update không hợp lệ; chưa ghi registry.'
    }
    if ($Entry.Exists -and $Entry.Kind -notin @('DWord','QWord','String','ExpandString','MultiString','Binary')) {
        throw 'Kiểu giá trị trong sao lưu Windows Update không được hỗ trợ.'
    }
}

function Set-RaidUpdateRegistrySnapshot($Entry) {
    Assert-RaidUpdateEntry $Entry
    $current=Get-RaidUpdateRegistrySnapshot $Entry.Path $Entry.Name
    if (Test-RaidUpdateSnapshotEqual $current $Entry) { return }
    if (-not $Entry.Exists) {
        $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Entry.Path,$true)
        try { if ($key) { $key.DeleteValue($Entry.Name,$false) } }
        finally { if ($key) { $key.Dispose() } }
    } else {
        $kind=[Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$Entry.Kind)
        $value=$Entry.Value
        switch ([string]$Entry.Kind) {
            'DWord' { $value=[int]$value }
            'QWord' { $value=[long]$value }
            'String' { $value=[string]$value }
            'ExpandString' { $value=[string]$value }
            'MultiString' { $value=[string[]]$value }
            'Binary' { $value=[byte[]]$value }
        }
        $key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($Entry.Path,$true)
        try { $key.SetValue($Entry.Name,$value,$kind) }
        finally { if ($key) { $key.Dispose() } }
    }
    $actual=Get-RaidUpdateRegistrySnapshot $Entry.Path $Entry.Name
    if (-not (Test-RaidUpdateSnapshotEqual $actual $Entry)) {
        throw 'Giá trị NoAutoUpdate đọc lại không khớp; chưa thể xác nhận thay đổi.'
    }
}

function Get-RaidUpdateMachineId {
    $entry=Get-RaidUpdateRegistrySnapshot 'SOFTWARE\Microsoft\Cryptography' 'MachineGuid'
    if (-not $entry.Exists -or [string]::IsNullOrWhiteSpace([string]$entry.Value)) { throw 'Không đọc được mã định danh Windows để bảo vệ bản sao lưu.' }
    return [string]$entry.Value
}

function Get-RaidUpdatePlatform {
    $entry=Get-RaidUpdateRegistrySnapshot 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID'
    $edition=[string]$entry.Value
    $build=[Environment]::OSVersion.Version.Build
    $supported=$build -ge 22000 -and $edition -match '^(Professional|Enterprise|Education|IoTEnterprise)'
    $ignore=Get-RaidUpdateRegistrySnapshot 'SOFTWARE\Microsoft\PolicyManager\current\device\Update' 'IgnoreWindowsUpdateGroupPolicies'
    return [pscustomobject]@{Edition=$edition;Build=$build;Supported=$supported;GroupPolicyIgnored=($ignore.Exists -and [int]$ignore.Value -eq 1)}
}

function Assert-RaidUpdateMutationAllowed {
    if ($env:COMPUTERNAME -eq 'DESKTOP-IMKRT09') { throw 'Đây là máy thật đã được chặn. Chỉ chạy chức năng này trong máy ảo Windows 11.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Hãy dùng Windows PowerShell 64-bit trong máy ảo.' }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Chức năng Windows Update cần quyền quản trị trong máy ảo.'
    }
}

function Read-RaidUpdateBackup {
    if (-not (Test-Path -LiteralPath $script:RaidUpdateBackupPath)) { return $null }
    $saved=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:RaidUpdateBackupPath))
    if ($saved.Schema -ne 1 -or $saved.MachineId -cne (Get-RaidUpdateMachineId) -or $saved.Active -isnot [bool]) {
        throw 'Bản sao lưu Update không thuộc Windows này hoặc sai định dạng. Không tự ghi đè bản sao lưu.'
    }
    Assert-RaidUpdateEntry $saved.Original
    return $saved
}

function Save-RaidUpdateBackup($State) {
    New-Item -ItemType Directory -Path $script:RaidUpdateBackupFolder -Force | Out-Null
    $tempPath=$script:RaidUpdateBackupPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $json=ConvertTo-Json -InputObject $State -Depth 8
        [IO.File]::WriteAllText($tempPath,$json,(New-Object Text.UTF8Encoding($true)))
        if (Test-Path -LiteralPath $script:RaidUpdateBackupPath) {
            # An explicit sidecar avoids PowerShell 5.1 coercing a null backup
            # filename to an invalid empty path. File.Replace is atomic on NTFS.
            [IO.File]::Replace($tempPath,$script:RaidUpdateBackupPath,$script:RaidUpdateBackupPath+'.previous',$true)
        } else { [IO.File]::Move($tempPath,$script:RaidUpdateBackupPath) }
    } finally { if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force } }
}

function Get-RaidUpdateStatus {
    $platform=Get-RaidUpdatePlatform
    $entry=Get-RaidUpdateRegistrySnapshot $script:RaidUpdateKey $script:RaidUpdateValue
    $saved=Read-RaidUpdateBackup
    return [pscustomobject]@{
        Platform=$platform;Policy=$entry;BackupActive=($null -ne $saved -and $saved.Active)
        PolicyRequestsBlock=($entry.Exists -and $entry.Kind -eq 'DWord' -and [int]$entry.Value -eq 1)
    }
}

function Invoke-RaidUpdateAction([string]$RequestedAction) {
    if ($RequestedAction -notin @('Status','Block','Restore')) { throw 'Chức năng Windows Update không hợp lệ.' }
    $details=New-Object 'System.Collections.Generic.List[string]'
    $details.Add('Chỉ quản lý cập nhật Windows tự động. Vẫn có thể cài thủ công; chính sách quản trị khác có thể ghi đè. Không bảo đảm chặn toàn bộ cập nhật vĩnh viễn.')
    if ($RequestedAction -ne 'Status') { Assert-RaidUpdateMutationAllowed }
    $status=Get-RaidUpdateStatus
    $platform=$status.Platform
    $message='Đã đọc trạng thái chính sách Windows Update.'
    if ($RequestedAction -eq 'Block') {
        if (-not $platform.Supported) {
            throw ('Windows '+$platform.Edition+' không nằm trong các bản Windows 11 hỗ trợ chính sách này. Chưa thay đổi; có thể tạm dừng cập nhật trong Settings > Windows Update.')
        }
        if ($platform.GroupPolicyIgnored) { throw 'Thiết bị đang bỏ qua Group Policy của Windows Update theo cấu hình MDM. Chưa thay đổi; cần quản lý tại hệ thống MDM.' }
        $saved=Read-RaidUpdateBackup
        if (-not $saved -or -not $saved.Active) {
            $saved=[pscustomobject]@{
                Schema=1;MachineId=(Get-RaidUpdateMachineId);ComputerName=$env:COMPUTERNAME
                SavedAt=(Get-Date).ToString('o');Active=$true;Original=$status.Policy
            }
            # Mandatory pre-change backup; a save failure stops before the write.
            Save-RaidUpdateBackup $saved
        }
        $target=[pscustomobject]@{Path=$script:RaidUpdateKey;Name=$script:RaidUpdateValue;Exists=$true;Kind='DWord';Value=1}
        Set-RaidUpdateRegistrySnapshot $target
        # Verify independently of the writer (also catches a blocked/silently ignored write).
        $actual=Get-RaidUpdateRegistrySnapshot $target.Path $target.Name
        if (-not (Test-RaidUpdateSnapshotEqual $actual $target)) { throw 'Chưa xác nhận được chính sách chặn cập nhật tự động; bản sao lưu vẫn được giữ.' }
        $message='Đã đặt và kiểm tra chính sách chặn cập nhật Windows tự động.'
        $details.Add('Windows có thể cần thời gian hoặc lần khởi động lại tiếp theo để nhận chính sách. Tác vụ cập nhật đã bắt đầu không bị hủy. Script không tự khởi động lại.')
    } elseif ($RequestedAction -eq 'Restore') {
        $saved=Read-RaidUpdateBackup
        if (-not $saved -or -not $saved.Active) {
            $message='Không có bản sao lưu Update đang hoạt động để khôi phục. Không thay đổi chính sách hiện tại.'
        } else {
            Set-RaidUpdateRegistrySnapshot $saved.Original
            $actual=Get-RaidUpdateRegistrySnapshot $saved.Original.Path $saved.Original.Name
            if (-not (Test-RaidUpdateSnapshotEqual $actual $saved.Original)) { throw 'Khôi phục chưa được xác nhận; bản sao lưu vẫn hoạt động để thử lại.' }
            $saved.Active=$false
            # If this status save fails, disk backup remains active and a retry is safe.
            Save-RaidUpdateBackup $saved
            $message='Đã khôi phục và kiểm tra thiết lập Update trước khi dùng công cụ.'
            $details.Add('Nếu Update đã bị chặn trước đó, khôi phục sẽ giữ nguyên trạng thái đã có. Không tự sửa chính sách ngoài phạm vi công cụ.')
        }
    }
    $status=Get-RaidUpdateStatus
    if (-not $platform.Supported) { $details.Add('Bản Windows này không được chức năng Block hỗ trợ; không báo rằng chính sách có hiệu lực.') }
    if ($platform.GroupPolicyIgnored) { $details.Add('MDM đang yêu cầu bỏ qua Group Policy Windows Update.') }
    return [pscustomobject]@{
        Success=$true;Action=$RequestedAction;Message=$message;Details=@($details.ToArray());RebootRequired=$false
        BackupPath=$script:RaidUpdateBackupPath;BackupActive=$status.BackupActive
        Supported=$platform.Supported;Edition=$platform.Edition;GroupPolicyIgnored=$platform.GroupPolicyIgnored
        PolicyRequestsBlock=$status.PolicyRequestsBlock;Policy=$status.Policy
    }
}

function Write-RaidUpdateResult($Result,[string]$Path) {
    if ($Path) {
        $fullPath=[IO.Path]::GetFullPath($Path)
        $parent=[IO.Path]::GetDirectoryName($fullPath)
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($fullPath,($Result | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($true)))
    }
    Write-Host $Result.Message
    foreach ($line in @($Result.Details)) { Write-Host $line }
}

try {
    $result=Invoke-RaidUpdateAction $Action
    Write-RaidUpdateResult $result $ResultPath
    exit 0
} catch {
    $cause=$_.Exception.GetBaseException()
    $result=[pscustomobject]@{
        Success=$false;Action=$Action;Message=$cause.Message
        Details=@(($cause.GetType().Name+'; HRESULT '+$cause.HResult),'Nếu đã tạo sao lưu, file vẫn được giữ để khôi phục hoặc thử lại. Không có dịch vụ nào bị script vô hiệu hóa.')
        RebootRequired=$false;BackupPath=$script:RaidUpdateBackupPath
    }
    try { Write-RaidUpdateResult $result $ResultPath }
    catch { Write-Error ('Không ghi được kết quả: '+$_.Exception.Message) -ErrorAction Continue }
    exit 1
}
