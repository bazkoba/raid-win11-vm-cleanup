#Requires -Version 5.1
<#
Reversible service profile for a Windows 11 RAID/Plarium virtual machine.
Only this file's explicit allowlist can be changed. It never edits service ACLs,
triggers, executables or dependencies. Preview/Status do not change services.
Printing, Search, ConnectedDevices and Diagnostics are separate opt-in groups.
Original configuration is saved once; a pending journal survives partial failure.
https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-service
https://learn.microsoft.com/en-us/windows/win32/services/automatically-starting-services
#>
[CmdletBinding()]
param(
    [ValidateSet('Preview','Apply','Restore','Status')][string]$Action='Preview',
    [ValidateSet('OptionalWindows','Xbox','Printing','Search','ConnectedDevices','Diagnostics')][string[]]$Groups,
    [string]$ResultPath
)

$ErrorActionPreference='Stop'
$script:RaidServicesBackupFolder=Join-Path $env:ProgramData 'RaidVM-Toolkit\Services'
$script:RaidServicesBackupPath=Join-Path $script:RaidServicesBackupFolder 'before.json'

function Get-RaidServicesCatalog {
    return [ordered]@{
        OptionalWindows=@('Fax','MapsBroker','RetailDemo','RemoteRegistry','WMPNetworkSvc')
        Xbox=@('XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc')
        Printing=@('Spooler','PrintNotify')
        Search=@('WSearch')
        ConnectedDevices=@('CDPSvc','CDPUserSvc_*')
        Diagnostics=@('DiagTrack','dmwappushservice')
    }
}

function Get-RaidServiceGroup([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'Tên dịch vụ không hợp lệ.' }
    $catalog=Get-RaidServicesCatalog
    foreach ($group in $catalog.Keys) {
        foreach ($allowed in $catalog[$group]) {
            if ($allowed -eq 'CDPUserSvc_*') {
                # Only actual per-user instances are eligible, never the template.
                if ($Name -cmatch '^CDPUserSvc_[0-9a-fA-F]+$') { return [string]$group }
            } elseif ($Name -ieq $allowed) { return [string]$group }
        }
    }
    throw ('Dịch vụ '+$Name+' không thuộc danh sách cho phép; chưa thay đổi.')
}

function Get-RaidServicesGroups([string[]]$RequestedGroups) {
    $catalog=Get-RaidServicesCatalog
    if (-not $RequestedGroups -or $RequestedGroups.Count -eq 0) { return @('OptionalWindows','Xbox') }
    $result=New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $RequestedGroups) {
        if ($name -notin @($catalog.Keys)) { throw ('Nhóm dịch vụ không hợp lệ: '+$name) }
        if (-not $result.Contains($name)) { $result.Add($name) }
    }
    return @($result.ToArray())
}

function Get-RaidServiceInventory { return @((Get-Service -ErrorAction Stop).Name) }

function Get-RaidServiceRegistryValue([string]$Name,[string]$ValueName) {
    $null=Get-RaidServiceGroup $Name
    if ($ValueName -notin @('Start','DelayedAutoStart')) { throw 'Giá trị dịch vụ không hợp lệ.' }
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(('SYSTEM\CurrentControlSet\Services\'+$Name),$false)
    try {
        if (-not $key) { throw ('Không tìm thấy khóa cấu hình của '+$Name+'.') }
        $exists=@($key.GetValueNames()) -contains $ValueName
        $kind=$null;$value=$null
        if ($exists) {
            $kind=$key.GetValueKind($ValueName).ToString()
            $value=$key.GetValue($ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        return [pscustomobject]@{Exists=$exists;Kind=$kind;Value=$value}
    } finally { if ($key) { $key.Dispose() } }
}

function Assert-RaidServiceValue($Value,[string]$ValueName) {
    if ($null -eq $Value -or $Value.Exists -isnot [bool]) { throw 'Dữ liệu sao lưu dịch vụ không hợp lệ.' }
    if (-not $Value.Exists) {
        if ($ValueName -eq 'Start') { throw 'Bản sao lưu thiếu kiểu khởi động dịch vụ.' }
        return
    }
    if ($ValueName -eq 'Start') {
        if ($Value.Kind -cne 'DWord' -or $Value.Value -notin @(2,3,4)) { throw 'Kiểu khởi động dịch vụ không được hỗ trợ; chưa thay đổi.' }
        return
    }
    if ($ValueName -cne 'DelayedAutoStart') { throw 'Giá trị dịch vụ không hợp lệ.' }
    switch -CaseSensitive ([string]$Value.Kind) {
        'DWord' { $null=[int]$Value.Value }
        'QWord' { $null=[long]$Value.Value }
        'String' { if ($Value.Value -isnot [string]) { throw 'Sao lưu chuỗi không hợp lệ.' } }
        'ExpandString' { if ($Value.Value -isnot [string]) { throw 'Sao lưu chuỗi không hợp lệ.' } }
        'MultiString' { foreach ($item in @($Value.Value)) { if ($item -isnot [string]) { throw 'Sao lưu chuỗi không hợp lệ.' } } }
        {$_ -in @('Binary','None')} { foreach ($item in @($Value.Value)) { if ($item -notmatch '^\d+$' -or [long]$item -gt 255) { throw 'Sao lưu nhị phân không hợp lệ.' } } }
        default { throw 'Kiểu DelayedAutoStart trong sao lưu không được hỗ trợ.' }
    }
}

function Test-RaidServiceValueEqual($Left,$Right) {
    if ([bool]$Left.Exists -ne [bool]$Right.Exists) { return $false }
    if (-not $Left.Exists) { return $true }
    return $Left.Kind -ceq $Right.Kind -and (ConvertTo-Json -InputObject $Left.Value -Compress -Depth 6) -ceq (ConvertTo-Json -InputObject $Right.Value -Compress -Depth 6)
}

function Get-RaidServiceFacts([string]$Name) {
    $null=Get-RaidServiceGroup $Name
    try { $service=Get-Service -Name $Name -ErrorAction Stop }
    catch { throw ('Không đọc được dịch vụ '+$Name+'. Nếu dịch vụ đã bị gỡ, bản sao lưu vẫn được giữ để thử khôi phục sau. '+$_.Exception.GetBaseException().Message) }
    $service.Refresh()
    $start=Get-RaidServiceRegistryValue $Name 'Start'
    Assert-RaidServiceValue $start 'Start'
    $startup=$service.StartType.ToString()
    if ($startup -cne (@{2='Automatic';3='Manual';4='Disabled'}[[int]$start.Value])) { throw ('Cấu hình SCM và registry của '+$Name+' chưa đồng nhất; chưa thay đổi.') }
    return [pscustomobject]@{
        Name=[string]$service.Name;DisplayName=[string]$service.DisplayName
        StartupType=$startup;Start=$start
        DelayedAutoStart=(Get-RaidServiceRegistryValue $Name 'DelayedAutoStart')
        State=$service.Status.ToString()
        DependsOn=@($service.ServicesDependedOn | ForEach-Object { $_.Name })
        Dependents=@($service.DependentServices | ForEach-Object { $_.Name })
    }
}

function Get-RaidServiceState([string]$Name) {
    # Dependency names are read-only and may be outside the allowlist.
    return (Get-Service -Name $Name -ErrorAction Stop).Status.ToString()
}

function Get-RaidServicesMachineId {
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Cryptography',$false)
    try { $id=[string]$key.GetValue('MachineGuid') }
    finally { if ($key) { $key.Dispose() } }
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'Không đọc được mã định danh Windows để bảo vệ bản sao lưu.' }
    return $id
}

function Assert-RaidServicesMutationAllowed {
    if ([Environment]::MachineName -ieq 'DESKTOP-IMKRT09' -or $env:COMPUTERNAME -ieq 'DESKTOP-IMKRT09') {
        throw 'Đây là máy thật đã được chặn. Chỉ tối ưu dịch vụ trong máy ảo Windows 11.'
    }
    if (-not [Environment]::Is64BitProcess -or [Environment]::OSVersion.Version.Build -lt 22000) { throw 'Hãy chạy Windows PowerShell 64-bit trong máy ảo Windows 11.' }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Tối ưu/khôi phục dịch vụ cần quyền quản trị trong máy ảo.' }
    } finally { $identity.Dispose() }
}

function Set-RaidServiceStartup([string]$Name,[string]$StartupType) {
    Assert-RaidServicesMutationAllowed
    $null=Get-RaidServiceGroup $Name
    if ($StartupType -notin @('Automatic','Manual','Disabled')) { throw 'Kiểu khởi động dịch vụ không hợp lệ.' }
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
}

function Set-RaidServiceRunState([string]$Name,[string]$State) {
    Assert-RaidServicesMutationAllowed
    $null=Get-RaidServiceGroup $Name
    $service=Get-Service -Name $Name -ErrorAction Stop
    $service.Refresh()
    if ($service.Status.ToString() -eq $State) { return }
    if ($State -eq 'Stopped') { Stop-Service -Name $Name -ErrorAction Stop }
    elseif ($State -eq 'Running') { Start-Service -Name $Name -ErrorAction Stop }
    else { throw 'Trạng thái dịch vụ không hợp lệ.' }
    $service.WaitForStatus([Enum]::Parse([System.ServiceProcess.ServiceControllerStatus],$State),[TimeSpan]::FromSeconds(12))
}

function Set-RaidServiceDelaySnapshot([string]$Name,$Value) {
    Assert-RaidServicesMutationAllowed
    $null=Get-RaidServiceGroup $Name
    Assert-RaidServiceValue $Value 'DelayedAutoStart'
    if (Test-RaidServiceValueEqual (Get-RaidServiceRegistryValue $Name 'DelayedAutoStart') $Value) { return }
    # Open existing key only; a removed service is never recreated from a backup.
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(('SYSTEM\CurrentControlSet\Services\'+$Name),$true)
    try {
        if (-not $key) { throw ('Dịch vụ '+$Name+' không còn tồn tại; giữ bản sao lưu để thử lại.') }
        if (-not $Value.Exists) { $key.DeleteValue('DelayedAutoStart',$false) }
        else {
            $kind=[Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$Value.Kind)
            $data=$Value.Value
            switch ([string]$Value.Kind) {
                'DWord' { $data=[int]$data }
                'QWord' { $data=[long]$data }
                'String' { $data=[string]$data }
                'ExpandString' { $data=[string]$data }
                'MultiString' { $data=[string[]]$data }
                {$_ -in @('Binary','None')} { $data=[byte[]]$data }
            }
            $key.SetValue('DelayedAutoStart',$data,$kind)
        }
    } finally { if ($key) { $key.Dispose() } }
    if (-not (Test-RaidServiceValueEqual (Get-RaidServiceRegistryValue $Name 'DelayedAutoStart') $Value)) { throw ('Đọc lại DelayedAutoStart của '+$Name+' không khớp.') }
}

function Assert-RaidServicesBackup($State) {
    if ($null -eq $State -or $State.Schema -ne 1 -or $State.Active -isnot [bool] -or $State.MachineId -cne (Get-RaidServicesMachineId) -or $State.ComputerName -ine [Environment]::MachineName) {
        throw 'Bản sao lưu dịch vụ sai định dạng hoặc thuộc Windows khác; không tự ghi đè.'
    }
    $seen=@{}
    foreach ($entry in @($State.Entries)) {
        $group=Get-RaidServiceGroup ([string]$entry.Name)
        if ($seen.ContainsKey([string]$entry.Name) -or $entry.Group -cne $group -or $entry.Pending -isnot [bool] -or $null -eq $entry.Before -or $entry.Before.Name -ine $entry.Name) { throw 'Mục sao lưu dịch vụ không hợp lệ; chưa ghi cấu hình.' }
        $seen[[string]$entry.Name]=$true
        if ($entry.Before.State -notin @('Running','Stopped')) { throw 'Trạng thái gốc trong sao lưu dịch vụ không hợp lệ.' }
        Assert-RaidServiceValue $entry.Before.Start 'Start'
        Assert-RaidServiceValue $entry.Before.DelayedAutoStart 'DelayedAutoStart'
        if ($entry.Before.StartupType -cne (@{2='Automatic';3='Manual';4='Disabled'}[[int]$entry.Before.Start.Value])) { throw 'Kiểu khởi động trong sao lưu không khớp.' }
    }
    if ([bool]$State.Active -ne (@($State.Entries | Where-Object { $_.Pending }).Count -gt 0)) { throw 'Nhật ký khôi phục dịch vụ không nhất quán; chưa ghi cấu hình.' }
}

function Read-RaidServicesBackup {
    if (-not [IO.File]::Exists($script:RaidServicesBackupPath)) { return $null }
    $state=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:RaidServicesBackupPath))
    Assert-RaidServicesBackup $state
    return $state
}

function Save-RaidServicesBackup($State) {
    Assert-RaidServicesBackup $State
    New-Item -ItemType Directory -Path $script:RaidServicesBackupFolder -Force | Out-Null
    $temp=$script:RaidServicesBackupPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject $State -Depth 12),(New-Object Text.UTF8Encoding($true)))
        if ([IO.File]::Exists($script:RaidServicesBackupPath)) { [IO.File]::Replace($temp,$script:RaidServicesBackupPath,$script:RaidServicesBackupPath+'.previous',$true) }
        else { [IO.File]::Move($temp,$script:RaidServicesBackupPath) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Enter-RaidServicesLock {
    New-Item -ItemType Directory -Path $script:RaidServicesBackupFolder -Force | Out-Null
    try { return [IO.File]::Open((Join-Path $script:RaidServicesBackupFolder 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw 'Một tác vụ dịch vụ khác đang chạy. Chờ tác vụ đó hoàn tất rồi thử lại.' }
}

function Get-RaidServicesTargets([string[]]$SelectedGroups) {
    $inventory=@(Get-RaidServiceInventory)
    $catalog=Get-RaidServicesCatalog
    foreach ($group in $SelectedGroups) {
        foreach ($name in $catalog[$group]) {
            if ($name -eq 'CDPUserSvc_*') {
                $matches=@($inventory | Where-Object { $_ -cmatch '^CDPUserSvc_[0-9a-fA-F]+$' } | Sort-Object -Unique)
                if ($matches.Count -eq 0) { [pscustomobject]@{Name='CDPUserSvc_<instance>';Group=$group;Exists=$false} }
                else { foreach ($instance in $matches) { [pscustomobject]@{Name=$instance;Group=$group;Exists=$true} } }
            } else { [pscustomobject]@{Name=$name;Group=$group;Exists=($inventory -icontains $name)} }
        }
    }
}

function Get-RaidServicesOrder([string[]]$Names,[bool]$DependentsFirst) {
    $remaining=@{};$facts=@{}
    foreach ($name in @($Names)) { $null=Get-RaidServiceGroup $name;$remaining[$name]=$true;$facts[$name]=Get-RaidServiceFacts $name }
    $ordered=New-Object 'System.Collections.Generic.List[string]'
    while ($remaining.Count -gt 0) {
        $ready=@($remaining.Keys | Where-Object {
            $name=$_
            $edges=if ($DependentsFirst) { @($facts[$name].Dependents) } else { @($facts[$name].DependsOn) }
            @($edges | Where-Object { $remaining.ContainsKey([string]$_) }).Count -eq 0
        } | Sort-Object)
        if ($ready.Count -eq 0) { throw 'Phát hiện vòng phụ thuộc dịch vụ; chưa dừng/khởi chạy dịch vụ trong nhóm này.' }
        foreach ($name in $ready) { $ordered.Add($name);$remaining.Remove($name) }
    }
    return @($ordered.ToArray())
}

function Get-RaidServiceRunningDependents($Facts) {
    return @($Facts.Dependents | Where-Object { (Get-RaidServiceState $_) -ne 'Stopped' })
}

function Assert-RaidServiceCanStop($Facts) {
    $busy=@(Get-RaidServiceRunningDependents $Facts)
    if ($busy.Count -gt 0) { throw ('Không dừng '+$Facts.Name+' vì dịch vụ phụ thuộc vẫn đang chạy: '+($busy -join ', ')+'. Không dừng ép dịch vụ phụ thuộc.') }
}

function Assert-RaidServiceCanStart($Facts) {
    $unready=@($Facts.DependsOn | Where-Object { (Get-RaidServiceState $_) -ne 'Running' })
    if ($unready.Count -gt 0) { throw ('Chưa khởi chạy '+$Facts.Name+' vì dịch vụ cần thiết chưa chạy: '+($unready -join ', ')+'. Không tự bật dịch vụ ngoài lựa chọn.') }
}

function Test-RaidServiceOriginalEqual($Actual,$Original) {
    return $Actual.StartupType -ceq $Original.StartupType -and $Actual.State -ceq $Original.State -and (Test-RaidServiceValueEqual $Actual.Start $Original.Start) -and (Test-RaidServiceValueEqual $Actual.DelayedAutoStart $Original.DelayedAutoStart)
}

function New-RaidServiceResult([string]$Name,[string]$Group,[string]$Status,[bool]$Success,[string]$Message,$Before,$After) {
    return [pscustomobject]@{Name=$Name;Status=$Status;Success=$Success;Message=$Message;Group=$Group;Before=$Before;After=$After}
}

function Invoke-RaidServicesAction([string]$RequestedAction,[string[]]$RequestedGroups) {
    $results=New-Object 'System.Collections.Generic.List[object]'
    $lock=$null;$state=$null;$message='';$selected=@();$failure=$null
    try {
        if ($RequestedAction -notin @('Preview','Apply','Restore','Status')) { throw 'Tác vụ dịch vụ không hợp lệ.' }
        $selected=@(Get-RaidServicesGroups $RequestedGroups)
        if ($RequestedAction -in @('Apply','Restore')) { Assert-RaidServicesMutationAllowed;$lock=Enter-RaidServicesLock }
        $state=Read-RaidServicesBackup
        if ($RequestedAction -eq 'Restore') {
            $entries=if ($state) { @($state.Entries | Where-Object { $_.Pending -and (-not $RequestedGroups -or $_.Group -in $selected) }) } else { @() }
            $selected=@($entries | ForEach-Object { $_.Group } | Sort-Object -Unique)
            $configErrors=@{};$restoreBefore=@{};$eligible=New-Object 'System.Collections.Generic.List[string]'
            foreach ($entry in $entries) {
                try {
                    $current=Get-RaidServiceFacts $entry.Name;$restoreBefore[$entry.Name]=$current
                    if ($current.StartupType -cne $entry.Before.StartupType) { Set-RaidServiceStartup $entry.Name $entry.Before.StartupType }
                    Set-RaidServiceDelaySnapshot $entry.Name $entry.Before.DelayedAutoStart
                    $eligible.Add([string]$entry.Name)
                } catch { $configErrors[$entry.Name]=$_.Exception.GetBaseException().Message }
            }
            # Restore stopped services dependent-first, then running services prerequisite-first.
            foreach ($desiredState in @('Stopped','Running')) {
                $names=@($entries | Where-Object { $_.Name -in $eligible -and $_.Before.State -eq $desiredState } | ForEach-Object { $_.Name })
                if ($names.Count -eq 0) { continue }
                try { $order=@(Get-RaidServicesOrder $names ($desiredState -eq 'Stopped')) }
                catch { foreach ($name in $names) { $configErrors[$name]=$_.Exception.GetBaseException().Message };continue }
                foreach ($name in $order) {
                    try {
                        $current=Get-RaidServiceFacts $name
                        if ($current.State -ne $desiredState) {
                            if ($desiredState -eq 'Stopped') { Assert-RaidServiceCanStop $current } else { Assert-RaidServiceCanStart $current }
                            Set-RaidServiceRunState $name $desiredState
                        }
                    } catch { $configErrors[$name]=$_.Exception.GetBaseException().Message }
                }
            }
            foreach ($entry in $entries) {
                $after=$null
                try {
                    $after=Get-RaidServiceFacts $entry.Name
                    if ($configErrors.ContainsKey($entry.Name)) { throw $configErrors[$entry.Name] }
                    if (-not (Test-RaidServiceOriginalEqual $after $entry.Before)) { throw 'Cấu hình đọc lại chưa khớp bản gốc; giữ nhật ký để thử khôi phục lại.' }
                    $entry.Pending=$false;$state.Active=@($state.Entries | Where-Object { $_.Pending }).Count -gt 0
                    try { Save-RaidServicesBackup $state } catch { $entry.Pending=$true;$state.Active=$true;throw }
                    $results.Add((New-RaidServiceResult $entry.Name $entry.Group 'Restored' $true 'Đã khôi phục và kiểm tra đúng kiểu khởi động, cờ khởi động trễ và trạng thái gốc.' $restoreBefore[$entry.Name] $after))
                } catch { $results.Add((New-RaidServiceResult $entry.Name $entry.Group 'Failed' $false ($_.Exception.GetBaseException().Message) $restoreBefore[$entry.Name] $after)) }
            }
            $message=if ($entries.Count) { 'Đã xử lý khôi phục dịch vụ. Mục chưa hoàn tất vẫn được giữ để thử lại.' } else { 'Không có dịch vụ đang chờ khôi phục trong lựa chọn; chưa thay đổi dịch vụ.' }
        } else {
            $targets=@(Get-RaidServicesTargets $selected);$facts=@{};$valid=New-Object 'System.Collections.Generic.List[string]'
            foreach ($target in $targets) {
                if (-not $target.Exists) { $results.Add((New-RaidServiceResult $target.Name $target.Group 'Missing' $true 'Windows này không có dịch vụ này; bỏ qua.' $null $null));continue }
                try {
                    $current=Get-RaidServiceFacts $target.Name
                    if ($current.State -notin @('Running','Stopped')) { throw ('Dịch vụ đang ở trạng thái '+$current.State+'; chờ ổn định rồi thử lại.') }
                    if ($RequestedAction -ne 'Status' -and $current.StartupType -eq 'Disabled' -and $current.State -eq 'Running') { throw 'Dịch vụ đang chạy dù đã Disabled. Giữ nguyên vì không thể khôi phục trạng thái này bằng thao tác khởi chạy thông thường.' }
                    Assert-RaidServiceValue $current.DelayedAutoStart 'DelayedAutoStart'
                    $facts[$target.Name]=$current;$valid.Add([string]$target.Name)
                } catch { $results.Add((New-RaidServiceResult $target.Name $target.Group 'Failed' $false ($_.Exception.GetBaseException().Message) $null $null)) }
            }
            if ($RequestedAction -eq 'Apply') {
                if (-not $state) { $state=[pscustomobject]@{Schema=1;ComputerName=[Environment]::MachineName;MachineId=(Get-RaidServicesMachineId);CreatedAt=(Get-Date).ToString('o');Active=$false;Entries=@()} }
                $added=$false
                foreach ($name in $valid) {
                    if (@($state.Entries | Where-Object { $_.Name -ieq $name }).Count -eq 0) {
                        $state.Entries=@($state.Entries)+@([pscustomobject]@{Name=$name;Group=(Get-RaidServiceGroup $name);Before=$facts[$name];Pending=$false});$added=$true
                    }
                }
                # Capture all new originals atomically before the first service write.
                if ($added) { Save-RaidServicesBackup $state }
                $ordered=@(Get-RaidServicesOrder @($valid.ToArray()) $true)
            } else { $ordered=@($valid.ToArray()) }
            foreach ($name in $ordered) {
                $before=$facts[$name];$group=Get-RaidServiceGroup $name;$after=$before
                try {
                    if ($RequestedAction -eq 'Status') { $results.Add((New-RaidServiceResult $name $group 'Current' $true ($before.StartupType+' / '+$before.State) $before $before));continue }
                    if ($before.StartupType -eq 'Disabled' -and $before.State -eq 'Stopped') { $results.Add((New-RaidServiceResult $name $group 'Unchanged' $true 'Đã tắt và dừng từ trước; không ghi lại cấu hình.' $before $before));continue }
                    $outside=@(Get-RaidServiceRunningDependents $before | Where-Object { $_ -notin $valid })
                    if ($outside.Count -gt 0) {
                        $results.Add((New-RaidServiceResult $name $group 'SkippedDependency' $false ('Giữ nguyên vì dịch vụ ngoài lựa chọn đang phụ thuộc: '+($outside -join ', ')+'.') $before $before));continue
                    }
                    if ($RequestedAction -eq 'Preview') { $results.Add((New-RaidServiceResult $name $group 'Planned' $true 'Sẽ đặt Disabled và dừng; có thể khôi phục đúng cấu hình gốc.' $before $before));continue }
                    # Re-read at the point of mutation; never force-stop dependents.
                    $current=Get-RaidServiceFacts $name
                    if ($current.State -ne 'Stopped') { Assert-RaidServiceCanStop $current }
                    $entry=@($state.Entries | Where-Object { $_.Name -ieq $name })[0]
                    if (-not $entry.Pending) {
                        $entry.Pending=$true;$state.Active=$true
                        try { Save-RaidServicesBackup $state }
                        catch { $entry.Pending=$false;$state.Active=@($state.Entries | Where-Object { $_.Pending }).Count -gt 0;throw }
                    }
                    # Disable first to prevent a trigger restarting the service during this operation.
                    if ($current.StartupType -ne 'Disabled') { Set-RaidServiceStartup $name 'Disabled' }
                    if ($current.State -ne 'Stopped') { Set-RaidServiceRunState $name 'Stopped' }
                    $after=Get-RaidServiceFacts $name
                    if ($after.StartupType -ne 'Disabled' -or $after.State -ne 'Stopped') { throw 'Đọc lại chưa xác nhận dịch vụ đã tắt và dừng; giữ bản sao lưu để khôi phục.' }
                    $results.Add((New-RaidServiceResult $name $group 'Optimized' $true 'Đã đặt Disabled, dừng và kiểm tra lại dịch vụ.' $before $after))
                } catch {
                    $itemFailure=$_.Exception.GetBaseException().Message
                    try { $after=Get-RaidServiceFacts $name } catch { $after=$null }
                    $results.Add((New-RaidServiceResult $name $group 'Failed' $false $itemFailure $before $after))
                }
            }
            $message=switch ($RequestedAction) {
                'Preview' { 'Đã đọc cấu hình thực tế. Chưa thay đổi dịch vụ; nhóm In ấn/Tìm kiếm/Kết nối thiết bị/Chẩn đoán chỉ áp dụng khi tự chọn.' }
                'Status' { 'Đã đọc trạng thái dịch vụ thực tế; chưa thay đổi dịch vụ.' }
                'Apply' { 'Đã xử lý các dịch vụ được chọn. Không thay đổi bảo mật, Update, mạng, âm thanh, driver, Guest Additions hay giao diện Windows.' }
            }
        }
    } catch { $failure=$_.Exception.GetBaseException().Message;$results.Add((New-RaidServiceResult '' '' 'Failed' $false $failure $null $null));$message=$failure }
    finally { if ($lock) { $lock.Dispose() } }
    $failed=@($results | Where-Object { -not $_.Success }).Count
    $changed=@($results | Where-Object { $_.Status -in @('Optimized','Restored') }).Count
    if ($failed -gt 0 -and -not $failure) { $message+=' Có mục chưa hoàn tất; xem từng dòng kết quả, không dừng ép dịch vụ.' }
    return [pscustomobject]@{
        Action=$RequestedAction;Success=($failed -eq 0);Partial=($failed -gt 0 -and $changed -gt 0)
        Message=$message;Results=@($results.ToArray());BackupPath=$script:RaidServicesBackupPath
        BackupActive=($null -ne $state -and [bool]$state.Active)
        PendingCount=@($state.Entries | Where-Object { $_.Pending }).Count
        SelectedGroups=@($selected);RebootRequired=$false
    }
}

function Write-RaidServicesResult($Result,[string]$Path) {
    if ($Path) {
        $full=[IO.Path]::GetFullPath($Path);$folder=[IO.Path]::GetDirectoryName($full)
        if (-not [IO.Directory]::Exists($folder)) { [IO.Directory]::CreateDirectory($folder) | Out-Null }
        [IO.File]::WriteAllText($full,(ConvertTo-Json -InputObject $Result -Depth 14),(New-Object Text.UTF8Encoding($true)))
    }
    Write-Host $Result.Message
    foreach ($item in @($Result.Results)) { Write-Host ($item.Name+': '+$item.Message) }
}

try {
    $result=Invoke-RaidServicesAction $Action $Groups
    Write-RaidServicesResult $result $ResultPath
    if (-not $result.Success) { exit 1 }
    exit 0
} catch { Write-Error $_ -ErrorAction Continue;exit 1 }
