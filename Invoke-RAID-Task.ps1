#Requires -Version 5.1
<#
Background worker for the RAID VM Toolkit. The launcher supplies a local JSON
request; status.json and worker.log are written beside that request. Never call
the combined legacy Setup script here: installation and cleanup are separate.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RequestPath)

$ErrorActionPreference='Stop'

function Write-RaidTaskJson([string]$Path,$Value) {
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject $Value -Depth 16),[Text.UTF8Encoding]::new($true))
    for($attempt=0;$attempt -lt 5;$attempt++) {
        try {
            if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)}
            else{[IO.File]::Move($temp,$Path)}
            return
        } catch [IO.IOException] {
            if($attempt -eq 4){throw}
            Start-Sleep -Milliseconds 80
        }
    }
}

function Assert-RaidTaskEnvironment($Request) {
    $currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if([string]::IsNullOrWhiteSpace([string]$Request.ExpectedUserSid) -or $Request.ExpectedUserSid -cne $currentSid){
        throw 'Tài khoản chạy tác vụ khác tài khoản Desktop. Hãy dùng đúng tài khoản Windows đang đăng nhập.'
    }
    if([Environment]::OSVersion.Version.Build -lt 22000 -or -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){
        throw 'Công cụ này cần Windows 11 x64 và Windows PowerShell 64-bit.'
    }
    if($env:COMPUTERNAME -eq 'DESKTOP-IMKRT09' -and $Request.Action -notin @('PreviewCleanup','UpdateStatus')){
        throw 'Đây là máy thật đã được chặn. Chỉ thực hiện tác vụ bên trong máy ảo Windows 11.'
    }
    if($Request.Action -in @('PreviewCleanup','Cleanup','Install','UpdateBlock','UpdateRestore','Quick')){
        $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
            throw 'Tác vụ cần quyền quản trị. Hãy chấp nhận UAC bằng đúng tài khoản Windows hiện tại.'
        }
    }
}

function Get-RaidTaskPlan([string]$Action) {
    switch($Action){
        'PreviewCleanup' {return @('PreviewCleanup')}
        'Cleanup' {return @('Cleanup')}
        'Install' {return @('Install')}
        'UpdateStatus' {return @('UpdateStatus')}
        'UpdateBlock' {return @('UpdateBlock')}
        'UpdateRestore' {return @('UpdateRestore')}
        'UiApply' {return @('UiApply')}
        'UiRestore' {return @('UiRestore')}
        'Quick' {return @('Install','Cleanup','UiApply')}
        'Activation' {return @('Activation')}
        default {throw 'Tác vụ không hợp lệ.'}
    }
}

function Get-RaidStepLabel([string]$Action) {
    switch($Action){
        'PreviewCleanup' {return 'Xem trước danh sách app cần dọn'}
        'Cleanup' {return 'Dọn ứng dụng Windows đã chọn'}
        'Install' {return 'Cài phần mềm và thư viện đã chọn'}
        'UpdateStatus' {return 'Kiểm tra thiết lập cập nhật tự động'}
        'UpdateBlock' {return 'Chặn cập nhật Windows tự động'}
        'UpdateRestore' {return 'Khôi phục thiết lập cập nhật Windows'}
        'UiApply' {return 'Áp dụng giao diện tối giản'}
        'UiRestore' {return 'Khôi phục giao diện đã lưu'}
        'Activation' {return 'Mở công cụ riêng trong cửa sổ PowerShell'}
        default {return $Action}
    }
}

function Get-RaidStepStateLabel([string]$State) {
    switch($State){
        'Completed' {return 'Hoàn tất'}
        'Partial' {return 'Một phần'}
        'Failed' {return 'Lỗi'}
        default {return $State}
    }
}

function Invoke-RaidChildModule([string]$ModuleName,[hashtable]$Parameters,[string]$RunFolder,[string]$StepName) {
    $allowed=@('Debloat-Win11-RAID.ps1','Optimize-RAID-UI.ps1','Install-RAID-Apps.ps1','Manage-RAID-Update.ps1')
    if($ModuleName -notin $allowed){throw 'Tên module không hợp lệ.'}
    $modulePath=Join-Path $PSScriptRoot $ModuleName
    if(-not (Test-Path -LiteralPath $modulePath -PathType Leaf)){throw ('Thiếu module: '+$ModuleName)}
    # Only fixed source is encoded. All data (paths and parameters) is decoded
    # from JSON, never interpolated as PowerShell executable source.
    $errorDetailsPath=Join-Path $RunFolder ($StepName+'.error-details.txt')
    $payload=[pscustomobject]@{ModulePath=$modulePath;Parameters=$Parameters;ErrorDetailsPath=$errorDetailsPath}
    $payloadBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 8 -Compress)))
    $childSource=@'
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=$utf8
$OutputEncoding=$utf8
$payload=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')))
$invokeParameters=@{}
foreach($property in $payload.Parameters.PSObject.Properties){$invokeParameters[$property.Name]=$property.Value}
try {
    & ([string]$payload.ModulePath) @invokeParameters *>&1 | Out-String -Stream -Width 220 | ForEach-Object {[Console]::WriteLine($_)}
    exit 0
} catch {
    $failure=$_
    try {
        $details=($failure | Format-List * -Force | Out-String -Width 220)+[Environment]::NewLine+$failure.ScriptStackTrace
        [IO.File]::WriteAllText([string]$payload.ErrorDetailsPath,$details,[Text.UTF8Encoding]::new($true))
    } catch {[Console]::Error.WriteLine('Không ghi được nhật ký lỗi chi tiết.')}
    [Console]::Error.WriteLine($failure.Exception.GetBaseException().Message)
    exit 1
}
'@
    $childSource=$childSource.Replace('__PAYLOAD__',$payloadBase64)
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childSource))
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments='-NoLogo -NoProfile -NonInteractive -STA -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand '+$encoded
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$start
    try {
        if(-not $process.Start()){throw 'Không khởi chạy được tiến trình tác vụ.'}
        $outTask=$process.StandardOutput.ReadToEndAsync()
        $errTask=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout=$outTask.GetAwaiter().GetResult()
        $stderr=$errTask.GetAwaiter().GetResult()
        $outPath=Join-Path $RunFolder ($StepName+'.output.txt')
        $errPath=Join-Path $RunFolder ($StepName+'.error.txt')
        [IO.File]::WriteAllText($outPath,$stdout,[Text.UTF8Encoding]::new($true))
        [IO.File]::WriteAllText($errPath,$stderr,[Text.UTF8Encoding]::new($true))
        if($stdout){Write-Host $stdout}
        if($stderr){Write-Host $stderr -ForegroundColor Yellow}
        $detailsPath=if($process.ExitCode -ne 0 -and (Test-Path -LiteralPath $errorDetailsPath -PathType Leaf)){$errorDetailsPath}else{$null}
        if($detailsPath){Write-Host ('Chi tiết lỗi: '+$detailsPath)}
        return [pscustomobject]@{ExitCode=$process.ExitCode;OutputPath=$outPath;ErrorPath=$errPath;ErrorDetailsPath=$detailsPath}
    } finally {$process.Dispose()}
}

function Invoke-RaidTaskStep([string]$Action,[string[]]$Apps,[string]$RunFolder) {
    $resultPath=Join-Path $RunFolder ($Action+'.result.json')
    $parameters=@{ResultPath=$resultPath}
    $started=Get-Date
    switch($Action){
        'PreviewCleanup' {$module='Debloat-Win11-RAID.ps1';$parameters.Preview=$true}
        'Cleanup' {$module='Debloat-Win11-RAID.ps1'}
        'Install' {$module='Install-RAID-Apps.ps1';$parameters.Apps=@($Apps)}
        'UpdateStatus' {$module='Manage-RAID-Update.ps1';$parameters.Action='Status'}
        'UpdateBlock' {$module='Manage-RAID-Update.ps1';$parameters.Action='Block'}
        'UpdateRestore' {$module='Manage-RAID-Update.ps1';$parameters.Action='Restore'}
        'UiApply' {$module='Optimize-RAID-UI.ps1';$parameters.Action='Apply'}
        'UiRestore' {$module='Optimize-RAID-UI.ps1';$parameters.Action='Restore'}
        'Activation' {
            Write-Host 'Mở lệnh bên thứ ba theo lựa chọn của người dùng. Đóng cửa sổ đó để quay lại công cụ.'
            $external=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList '-NoProfile -Command "irm https://get.activated.win | iex"' -WindowStyle Normal -Wait -PassThru
            if($external.ExitCode -ne 0){throw ('Công cụ ngoài đóng với mã lỗi '+$external.ExitCode+'.')}
            return [pscustomobject]@{Action=$Action;Name=(Get-RaidStepLabel $Action);State='Completed';DisplayState='Hoàn tất';Success=$true;Partial=$false;Message='Cửa sổ công cụ ngoài đã đóng. Chưa xác minh kết quả kích hoạt.';RebootRequired=$false;ExitCode=$external.ExitCode;DurationSeconds=[Math]::Round(((Get-Date)-$started).TotalSeconds,1);ModuleResult=$null;OutputPath=$null;ErrorPath=$null;ErrorDetailsPath=$null}
        }
        default {throw 'Tác vụ không hợp lệ.'}
    }
    $child=Invoke-RaidChildModule -ModuleName $module -Parameters $parameters -RunFolder $RunFolder -StepName $Action
    if(-not (Test-Path -LiteralPath $resultPath -PathType Leaf)){
        throw ('Module '+$module+' không trả kết quả có cấu trúc; xem nhật ký. Mã thoát: '+$child.ExitCode)
    }
    $moduleResult=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($resultPath,[Text.Encoding]::UTF8))
    if($moduleResult.Success -isnot [bool]){throw ('Kết quả module '+$module+' thiếu trạng thái Success hợp lệ.')}
    $success=$child.ExitCode -eq 0 -and $moduleResult.Success
    $partial=-not $success -and [bool]$moduleResult.Partial
    $state=if($success){'Completed'}elseif($partial){'Partial'}else{'Failed'}
    $message=if($moduleResult.Message){[string]$moduleResult.Message}elseif($success){'Hoàn tất.'}else{'Chưa hoàn tất; xem chi tiết trong nhật ký.'}
    return [pscustomobject]@{Action=$Action;Name=(Get-RaidStepLabel $Action);State=$state;DisplayState=(Get-RaidStepStateLabel $state);Success=[bool]$success;Partial=[bool]$partial;Message=$message;RebootRequired=([bool]$moduleResult.RebootRequired -or [bool]$moduleResult.RestartRequired);ExitCode=$child.ExitCode;DurationSeconds=[Math]::Round(((Get-Date)-$started).TotalSeconds,1);ModuleResult=$moduleResult;OutputPath=$child.OutputPath;ErrorPath=$child.ErrorPath;ErrorDetailsPath=$child.ErrorDetailsPath}
}

function Invoke-RaidTaskRequest([string]$Path) {
    $fullPath=[IO.Path]::GetFullPath($Path)
    if(-not (Test-Path -LiteralPath $fullPath -PathType Leaf)){throw 'Không tìm thấy yêu cầu tác vụ.'}
    $runFolder=Split-Path -Parent $fullPath
    $statusPath=Join-Path $runFolder 'status.json'
    $logPath=Join-Path $runFolder 'worker.log'
    $request=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($fullPath,[Text.Encoding]::UTF8))
    $taskGuid=[guid]::Empty
    if(-not [guid]::TryParse([string]$request.TaskId,[ref]$taskGuid)){throw 'Mã tác vụ không hợp lệ.'}
    $plan=@(Get-RaidTaskPlan ([string]$request.Action))
    $apps=@($request.Apps | Where-Object {$_})
    if(@($apps|Where-Object {$_ -notin @('Chrome','WinRAR','DotNet8','VCx86','VCx64')}).Count){throw 'Danh sách phần mềm không hợp lệ.'}
    if($request.Action -in @('Install','Quick') -and -not $apps.Count){throw 'Chưa chọn phần mềm hoặc thư viện cần cài.'}
    $status=[pscustomobject]@{Schema=1;TaskId=$taskGuid.ToString();Action=[string]$request.Action;State='Running';Message='Đang kiểm tra điều kiện chạy tác vụ…';Step=0;TotalSteps=$plan.Count;Results=@();LogPath=$logPath;RebootRequired=$false;StartedAt=(Get-Date).ToString('o');FinishedAt=$null}
    $transcribing=$false
    try {
        Start-Transcript -LiteralPath $logPath -Force | Out-Null
        $transcribing=$true
        Write-RaidTaskJson $statusPath $status
        Assert-RaidTaskEnvironment $request
        foreach($stepAction in $plan){
            $status.Step++
            $status.Message=Get-RaidStepLabel $stepAction
            Write-RaidTaskJson $statusPath $status
            Write-Host ('--- '+$status.Step+'/'+$status.TotalSteps+': '+$status.Message+' ---')
            try {$step=Invoke-RaidTaskStep -Action $stepAction -Apps $apps -RunFolder $runFolder}
            catch {$step=[pscustomobject]@{Action=$stepAction;Name=(Get-RaidStepLabel $stepAction);State='Failed';DisplayState='Lỗi';Success=$false;Partial=$false;Message=$_.Exception.GetBaseException().Message;RebootRequired=$false;ExitCode=1;DurationSeconds=$null;ModuleResult=$null;OutputPath=$null;ErrorPath=$null;ErrorDetailsPath=$null};Write-Host $step.Message -ForegroundColor Yellow}
            $status.Results=@($status.Results)+@($step)
            $status.RebootRequired=$status.RebootRequired -or $step.RebootRequired
            Write-RaidTaskJson $statusPath $status
            # Do not uninstall apps if the requested installation was incomplete.
            if($request.Action -eq 'Quick' -and $stepAction -eq 'Install' -and -not $step.Success){break}
        }
        $failed=@($status.Results|Where-Object {-not $_.Success})
        if(-not $failed.Count){$status.State='Completed';$status.Message='Đã hoàn tất các bước đã chọn.'}
        elseif(@($status.Results|Where-Object {$_.Success -or $_.Partial}).Count){$status.State='Partial';$status.Message='Hoàn tất một phần. Một số mục cần kiểm tra hoặc thử lại; xem kết quả từng bước.'}
        else{$status.State='Failed';$status.Message='Tác vụ chưa hoàn tất. Xem kết quả từng bước và nhật ký để xử lý.'}
        if($request.Action -eq 'Quick' -and $status.Results.Count -eq 1 -and -not $status.Results[0].Success){$status.Message='Bước cài phần mềm chưa hoàn tất. Đã dừng trước khi dọn app và chỉnh giao diện.'}
    } catch {
        $status.State='Failed'
        $status.Message=$_.Exception.GetBaseException().Message
        Write-Host $status.Message -ForegroundColor Red
    } finally {
        $status.FinishedAt=(Get-Date).ToString('o')
        try {Write-RaidTaskJson $statusPath $status} finally {if($transcribing){Stop-Transcript | Out-Null}}
    }
    return $status
}

try {
    $taskStatus=Invoke-RaidTaskRequest -Path $RequestPath
    if($taskStatus.State -eq 'Completed'){exit 0}
    if($taskStatus.State -eq 'Partial'){exit 2}
    exit 1
} catch {Write-Error -Message ($_ | Out-String) -ErrorAction Continue;exit 1}
