#Requires -Version 5.1
<# Vietnamese WinForms control panel. Opening the panel does not change Windows.
Long tasks run in a separate process; this UI only polls its status JSON.
-Demo disables every task. -SmokeTest renders a non-mutating UI check and exits.
#>
[CmdletBinding()]
param([switch]$Demo,[switch]$SmokeTest,[string]$SmokeImagePath,[string]$StartupStatusPath,[string]$LaunchId,[switch]$RenderPreview,[ValidateSet('Cleanup','Install','Update','UiApply','UiRestore','Activation','Services','ServicesRestore','Quick')][string]$PreviewSection='Services')
$ErrorActionPreference='Stop'
$script:instanceMutex=$null
$ownsMutex=$false
function Write-ToolkitStartup([string]$State,[string]$Message,[string]$ErrorText='',[long]$WindowHandle=0){
    if(-not $StartupStatusPath){return}
    $startup=[pscustomobject]@{State=$State;LaunchId=$LaunchId;Pid=$PID;WindowHandle=$WindowHandle;Message=$Message;Error=$ErrorText}
    $temporary=$StartupStatusPath+'.tmp'
    [IO.File]::WriteAllText($temporary,(ConvertTo-Json -InputObject $startup -Depth 5),(New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temporary -Destination $StartupStatusPath -Force
}
try{
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if ($SmokeTest -or $RenderPreview) { $Demo=$true }
if ($PSVersionTable.PSEdition -ne 'Desktop' -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Open with Windows PowerShell 5.1 in STA mode, using Start-RAID-Toolkit.ps1.'
}
if (-not $Demo -and ($env:COMPUTERNAME -eq 'DESKTOP-IMKRT09' -or [Environment]::OSVersion.Version.Build -lt 22000 -or -not [Environment]::Is64BitProcess)) {
    Write-ToolkitStartup 'Failed' 'Hãy mở công cụ bên trong máy ảo Windows 11 x64; máy thật đã biết bị chặn.'
    [Windows.Forms.MessageBox]::Show('Hãy mở công cụ bên trong máy ảo Windows 11 x64. Máy thật đã biết bị chặn.','RAID VM Toolkit','OK','Warning') | Out-Null
    return
}
$script:toolRoot=$PSScriptRoot
$script:desktopSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if(-not $Demo){
    # A new namespace avoids an old hidden v1 instance blocking the fixed UI.
    $script:instanceMutex=New-Object Threading.Mutex($false,('Local\RaidVmToolkit-2-'+$script:desktopSid))
    try{$ownsMutex=$script:instanceMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsMutex=$true}
    if(-not $ownsMutex){
        Write-ToolkitStartup 'AlreadyRunning' 'Công cụ đang mở trong tài khoản này. Dùng cửa sổ đã mở hoặc Alt+Tab để tìm.'
        if(-not $StartupStatusPath){[Windows.Forms.MessageBox]::Show('Công cụ đang mở trong tài khoản này. Hãy dùng cửa sổ đã mở.','RAID VM Toolkit')|Out-Null}
        return
    }
}
$script:currentRun=$null
$script:workerProcess=$null
$script:lastStateText=''
$script:section='Cleanup'
$script:taskButtons=New-Object 'System.Collections.Generic.List[System.Windows.Forms.Control]'
$script:theme=@{Background='#F4F6FA';Surface='#FFFFFF';Text='#17233C';Muted='#4E5D75';Primary='#3730A3';Border='#D8DFEA'}
function Get-ToolkitColor([string]$Name){[Drawing.ColorTranslator]::FromHtml($script:theme[$Name])}
function New-ToolkitLabel([string]$Text,[single]$Size=10,[bool]$Bold=$false){
    $c=New-Object Windows.Forms.Label
    $c.Text=$Text;$c.AutoSize=$true;$c.MaximumSize=New-Object Drawing.Size(700,0)
    $style=if($Bold){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular}
    $c.Font=New-Object Drawing.Font('Segoe UI',$Size,$style)
    $c.ForeColor=Get-ToolkitColor Text;$c.Margin=New-Object Windows.Forms.Padding(0,0,0,8)
    return $c
}
function New-ToolkitButton([string]$Text){
    $b=New-Object Windows.Forms.Button
    $b.Text=$Text;$b.Height=44;$b.Dock='Top';$b.FlatStyle='Flat'
    $b.FlatAppearance.BorderColor=Get-ToolkitColor Border
    $b.BackColor=Get-ToolkitColor Surface;$b.ForeColor=Get-ToolkitColor Text
    $b.Margin=New-Object Windows.Forms.Padding(0,0,0,8)
    $b.UseVisualStyleBackColor=$false;$b.AccessibleName=$Text
    return $b
}
function Show-ToolkitMessage([string]$Text,[string]$Icon='Information'){
    [Windows.Forms.MessageBox]::Show($script:form,$Text,'RAID VM Toolkit',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::$Icon) | Out-Null
}
function Get-ToolkitApps {
    $selected=@()
    foreach($box in $script:appChecks){if($box.Checked){$selected+=@([string]$box.Tag)}}
    return $selected
}
function Get-ToolkitServiceGroups {
    foreach($box in $script:serviceChecks){if($box.Checked){[string]$box.Tag}}
}
function Set-ToolkitBusy([bool]$Busy){
    foreach($b in $script:taskButtons){$b.Enabled=(-not $Busy -and -not $Demo)}
    foreach($box in $script:appChecks){$box.Enabled=(-not $Busy -and -not $Demo)}
    foreach($box in $script:serviceChecks){$box.Enabled=(-not $Busy -and -not $Demo)}
    $script:quickServices.Enabled=(-not $Busy -and -not $Demo)
    $script:progress.Style=if($Busy){'Marquee'}else{'Blocks'}
    if(-not $Busy){$script:progress.Value=0}
}
function Start-ToolkitTask([string]$Action){
    if($Demo -or $script:workerProcess){return}
    $apps=@(Get-ToolkitApps)
    $serviceGroups=@(Get-ToolkitServiceGroups)
    if($Action -in @('Install','Quick') -and -not $apps.Count){Show-ToolkitMessage 'Chọn ít nhất một phần mềm hoặc thư viện để cài.' 'Warning';return}
    if($Action -in @('ServicesApply','ServicesPreview') -and -not $serviceGroups.Count){Show-ToolkitMessage 'Chọn ít nhất một nhóm dịch vụ hoặc dùng Kiểm tra trạng thái.' 'Warning';return}
    if($Action -in @('Cleanup','Quick')){
        $answer=[Windows.Forms.MessageBox]::Show($script:form,'Dọn app có thể xóa dữ liệu của các app bị gỡ, gồm Store/Xbox. Hãy tạo snapshot máy ảo trước. Tiếp tục?','Dọn ứng dụng',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning,[Windows.Forms.MessageBoxDefaultButton]::Button2)
        if($answer -ne 'Yes'){return}
    }
    if($Action -eq 'UpdateBlock'){
        $answer=[Windows.Forms.MessageBox]::Show($script:form,'Chặn cập nhật tự động có thể khiến Windows không nhận bản vá bảo mật tự động. Đây là chính sách có thể khôi phục, không phải chặn vĩnh viễn mọi hình thức cập nhật. Tiếp tục?','Windows Update','YesNo','Warning','Button2')
        if($answer -ne 'Yes'){return}
    }
    if($Action -eq 'Activation'){
        $answer=[Windows.Forms.MessageBox]::Show($script:form,'Mở lệnh công cụ bên thứ ba em đã chọn: irm https://get.activated.win | iex. Công cụ ngoài có thể yêu cầu quyền quản trị. Khôi phục giao diện không hoàn tác thay đổi của công cụ này. Mở cửa sổ riêng?','Công cụ riêng','YesNo','Warning','Button2')
        if($answer -ne 'Yes'){return}
    }
    try{
        $runId=[guid]::NewGuid().ToString('N')
        $script:currentRun=Join-Path $env:LOCALAPPDATA ('RaidVM-Toolkit\Runs\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$runId)
        New-Item -ItemType Directory -Path $script:currentRun -Force | Out-Null
        $requestPath=Join-Path $script:currentRun 'request.json'
        $request=[ordered]@{TaskId=$runId;Action=$Action;Apps=$apps;ExpectedUserSid=$script:desktopSid;IncludeServices=[bool]$script:quickServices.Checked}
        if($Action -in @('ServicesApply','ServicesPreview')){$request.ServiceGroups=$serviceGroups}
        [pscustomobject]$request | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $requestPath -Encoding UTF8
        $workerPath=Join-Path $script:toolRoot 'Invoke-RAID-Task.ps1'
        if(-not (Test-Path -LiteralPath $workerPath)){throw 'Không tìm thấy tệp xử lý. Mở lại bằng lệnh khởi chạy để tải đủ bộ công cụ.'}
        $args='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$workerPath+'" -RequestPath "'+$requestPath+'"'
        $start=@{FilePath=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe');ArgumentList=$args;PassThru=$true;WindowStyle='Hidden'}
        if($Action -in @('PreviewCleanup','Cleanup','Install','UpdateBlock','UpdateRestore','ServicesApply','ServicesRestore','Quick')){$start.Verb='RunAs'}
        $script:workerProcess=Start-Process @start
        $script:runStarted=Get-Date;$script:exitSeen=$null;$script:lastStateText=''
        $script:resultGrid.Rows.Clear();$script:status.Text='Đang khởi chạy tác vụ…';$script:status.ForeColor=Get-ToolkitColor Text
        Set-ToolkitBusy $true
        $script:pollTimer.Start()
    }catch{
        $script:workerProcess=$null;Set-ToolkitBusy $false
        $script:status.Text='Chưa chạy được tác vụ. Nếu đã hủy UAC, hãy bấm lại khi sẵn sàng.'
        Show-ToolkitMessage ($script:status.Text+"`r`n"+$_.Exception.Message) 'Warning'
    }
}
function Select-ToolkitSection([string]$Section){
    $script:section=$Section
    foreach($nav in $script:navButtons){$nav.BackColor=if($nav.Tag -eq $Section){[Drawing.ColorTranslator]::FromHtml('#E7E9FB')}else{Get-ToolkitColor Surface}}
    $script:appPanel.Visible=$Section -in @('Install','Quick')
    $script:servicePanel.Visible=$Section -eq 'Services'
    $script:quickServices.Visible=$Section -eq 'Quick'
    $script:secondary.Visible=$false;$script:updateStatus.Visible=$false
    $script:statusAction='UpdateStatus'
    switch($Section){
        'Cleanup' {$title='1. Dọn ứng dụng Windows';$desc='Gỡ các app tiêu dùng đã chọn trong danh sách của repo, gồm Store và Xbox. Giữ driver, Guest Additions, RAID/Plarium, Defender và thư viện chạy game.';$primary='Dọn app';$secondary='Xem trước danh sách';$note='Nên xem trước và tạo snapshot trước khi dọn. Khôi phục giao diện không cài lại app đã gỡ.';$script:primaryAction='Cleanup';$script:secondaryAction='PreviewCleanup';$script:secondary.Visible=$true}
        'Install' {$title='2. Cài phần mềm và thư viện';$desc='Chọn từng mục cần cài. Bộ cài lấy từ hãng và được kiểm tra chữ ký. Không gỡ app ở mục này.';$primary='Cài các mục đã chọn';$note='WinRAR là bản dùng thử. .NET 8 dành cho ứng dụng cần đúng phiên bản 8; không phải bộ SDK. VC++ v14 gồm cả x86 và x64.';$script:primaryAction='Install'}
        'Update' {$title='3. Windows Update';$desc='Chặn cập nhật tự động bằng chính sách Windows trên phiên bản hỗ trợ. Có bản sao lưu để trả lại thiết lập cũ.';$primary='Chặn cập nhật tự động';$secondary='Khôi phục thiết lập cập nhật';$note='Không bảo đảm chặn mọi cập nhật hoặc chặn vĩnh viễn. Windows Home không hỗ trợ cách này. Công cụ không tắt Defender hoặc sửa quyền dịch vụ.';$script:primaryAction='UpdateBlock';$script:secondaryAction='UpdateRestore';$script:secondary.Visible=$true;$script:updateStatus.Visible=$true}
        'UiApply' {$title='4. Tối giản, giữ giao diện sáng';$desc='Start/icon sang trái; ẩn thời tiết, Search và Task View; giảm hiệu ứng. Giữ theme, hình nền, màu nền và app ghim hiện có.';$primary='Tối giản, giữ màu và nền';$secondary='Khôi phục màu/nền cũ';$note='Nút khôi phục màu/nền chỉ dùng nếu bản cũ từng đổi nền. Hoàn tất chép file trước: Explorer sẽ được tải lại; cửa sổ File Explorer có thể đóng.';$script:primaryAction='UiApply';$script:secondaryAction='UiRestoreAppearance';$script:secondary.Visible=$true}
        'UiRestore' {$title='5. Khôi phục giao diện';$desc='Trả lại thiết lập giao diện đã được lưu trước khi tối giản, cho tài khoản Windows hiện tại.';$primary='Khôi phục giao diện đã lưu';$note='Hoàn tất chép file trước vì Explorer sẽ được tải lại. Mục này không cài lại app và không thay đổi Windows Update.';$script:primaryAction='UiRestore'}
        'Activation' {$title='6. Công cụ riêng';$desc='Mở một cửa sổ PowerShell riêng để chạy đúng lệnh bên thứ ba em đã yêu cầu.';$primary='Mở công cụ riêng';$note='irm https://get.activated.win | iex'+"`r`n"+'Mục này không nằm trong Làm nhanh. Công cụ không tự chọn phương thức hoặc xác nhận kích hoạt thành công.';$script:primaryAction='Activation'}
        'Services' {$title='7. Tối ưu dịch vụ cho RAID';$desc='Chọn nhóm để xem trước hoặc tắt dịch vụ. Mạng, âm thanh, bảo mật, driver và Guest Additions được giữ. Không ép dừng các dịch vụ phụ thuộc.';$primary='Tối ưu nhóm đã chọn';$secondary='Xem trước thay đổi';$note='Bốn nhóm cuối có thể làm mất tính năng ghi trên nhãn. Sao lưu cấu hình gốc trước thay đổi; mục lỗi báo riêng, có thể khôi phục tại mục 8. Không bảo đảm sửa lag hoặc tăng FPS.';$script:primaryAction='ServicesApply';$script:secondaryAction='ServicesPreview';$script:secondary.Visible=$true;$script:updateStatus.Visible=$true;$script:statusAction='ServicesStatus'}
        'ServicesRestore' {$title='8. Khôi phục dịch vụ';$desc='Trả lại startup, delayed start và trạng thái chạy/dừng gốc của những dịch vụ công cụ đã theo dõi trên máy ảo này.';$primary='Khôi phục dịch vụ đã lưu';$note='Khôi phục theo bản sao lưu của chính máy ảo, không dùng một danh sách mặc định chung. Mục lỗi giữ lại để thử tiếp. Không cài lại dịch vụ hay app đã gỡ.';$script:primaryAction='ServicesRestore';$script:updateStatus.Visible=$true;$script:statusAction='ServicesStatus'}
        'Quick' {$title='9. Làm nhanh cho máy treo RAID';$desc='Cài phần mềm đã chọn → dọn app → tối giản, giữ màu/nền. Có thể thêm hai nhóm dịch vụ cơ bản bên dưới. Cài phần mềm lỗi sẽ dừng trước khi dọn.';$primary='Bắt đầu làm nhanh';$note='Dịch vụ cơ bản: app Windows ít dùng và Xbox; không gồm bốn nhóm tùy chọn tại mục 7. Tạo snapshot, hoàn tất chép file trước. Không tự chặn Update hay khởi động lại.';$script:primaryAction='Quick'}
    }
    $script:pageTitle.Text=$title;$script:description.Text=$desc;$script:note.Text=$note;$script:primary.Text=$primary
    if($secondary -is [string]){$script:secondary.Text=$secondary}
}

$script:form=New-Object Windows.Forms.Form
$form.Text='RAID VM Toolkit — Tiếng Việt';$form.Size=New-Object Drawing.Size(1040,740)
$form.MinimumSize=New-Object Drawing.Size(900,660);$form.StartPosition='CenterScreen';$form.AutoScaleMode='Dpi'
$form.Font=New-Object Drawing.Font('Segoe UI',10);$form.BackColor=Get-ToolkitColor Background
$outer=New-Object Windows.Forms.TableLayoutPanel;$outer.Dock='Fill';$outer.Padding=New-Object Windows.Forms.Padding(20);$outer.RowCount=3;$outer.ColumnCount=1
$outer.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',76)))|Out-Null
$outer.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))|Out-Null
$outer.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',24)))|Out-Null
$form.Controls.Add($outer)
$header=New-Object Windows.Forms.FlowLayoutPanel;$header.Dock='Fill';$header.FlowDirection='TopDown';$header.WrapContents=$false
$header.Controls.Add((New-ToolkitLabel 'RAID VM Toolkit' 22 $true))
$subtitle=if($Demo){'CHẾ ĐỘ XEM THỬ — mọi thao tác hệ thống đều bị khóa'}else{'Máy: '+$env:COMPUTERNAME+'  •  Chọn chức năng rồi bấm thực hiện'}
$header.Controls.Add((New-ToolkitLabel $subtitle 10));$outer.Controls.Add($header,0,0)
$body=New-Object Windows.Forms.TableLayoutPanel;$body.Dock='Fill';$body.ColumnCount=2;$body.RowCount=1
$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',212)))|Out-Null
$body.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))|Out-Null;$outer.Controls.Add($body,0,1)
$sidebar=New-Object Windows.Forms.FlowLayoutPanel;$sidebar.Dock='Fill';$sidebar.FlowDirection='TopDown';$sidebar.WrapContents=$false;$sidebar.AutoScroll=$true;$sidebar.Padding=New-Object Windows.Forms.Padding(0,0,12,0)
$body.Controls.Add($sidebar,0,0)
$script:navButtons=@()
foreach($item in @(@('Cleanup','1  Dọn app'),@('Install','2  Cài phần mềm'),@('Update','3  Windows Update'),@('UiApply','4  Tối giản giao diện'),@('UiRestore','5  Khôi phục giao diện'),@('Activation','6  Công cụ riêng'),@('Services','7  Tối ưu dịch vụ'),@('ServicesRestore','8  Khôi phục dịch vụ'),@('Quick','9  Làm nhanh'))){
    $b=New-ToolkitButton $item[1];$b.Width=190;$b.Dock='None';$b.TextAlign='MiddleLeft';$b.Tag=$item[0]
    $b.Add_Click({param($sender,$eventArgs) Select-ToolkitSection ([string]$sender.Tag)})
    $script:navButtons+=@($b);$sidebar.Controls.Add($b)
}
$logButton=New-ToolkitButton 'Mở nhật ký';$logButton.Width=190;$logButton.Dock='None';$sidebar.Controls.Add($logButton)
$logButton.Add_Click({
    $folder=if($script:currentRun){$script:currentRun}else{Join-Path $env:LOCALAPPDATA 'RaidVM-Toolkit\Runs'}
    if(Test-Path -LiteralPath $folder){Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"'+$folder+'"')}else{Show-ToolkitMessage 'Chưa có nhật ký. Chọn một tác vụ để bắt đầu.'}
})
$right=New-Object Windows.Forms.TableLayoutPanel;$right.Dock='Fill';$right.RowCount=3;$right.ColumnCount=1
$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',64)))|Out-Null
$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',112)))|Out-Null
$right.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',36)))|Out-Null;$body.Controls.Add($right,1,0)
$content=New-Object Windows.Forms.FlowLayoutPanel;$content.Dock='Fill';$content.AutoScroll=$true;$content.FlowDirection='TopDown';$content.WrapContents=$false;$content.BackColor=Get-ToolkitColor Surface;$content.Padding=New-Object Windows.Forms.Padding(20)
$right.Controls.Add($content,0,0)
$script:pageTitle=New-ToolkitLabel '' 17 $true;$content.Controls.Add($pageTitle)
$script:description=New-ToolkitLabel '' 10;$content.Controls.Add($description)
$script:appPanel=New-Object Windows.Forms.FlowLayoutPanel;$appPanel.AutoSize=$true;$appPanel.FlowDirection='TopDown';$appPanel.WrapContents=$false;$appPanel.Margin=New-Object Windows.Forms.Padding(0,4,0,8)
$script:appChecks=@()
foreach($app in @(@('Chrome','Google Chrome'),@('WinRAR','WinRAR x64 — dùng thử'),@('DotNet8','.NET Desktop Runtime 8 x64'),@('VCx86','Visual C++ v14 x86'),@('VCx64','Visual C++ v14 x64'))){
    $box=New-Object Windows.Forms.CheckBox;$box.Text=$app[1];$box.Tag=$app[0];$box.AutoSize=$true;$box.Checked=$true;$box.Margin=New-Object Windows.Forms.Padding(0,1,0,5);$box.AccessibleName=$app[1]
    $appChecks+=@($box);$appPanel.Controls.Add($box)
}
$content.Controls.Add($appPanel)
$script:servicePanel=New-Object Windows.Forms.FlowLayoutPanel;$servicePanel.AutoSize=$true;$servicePanel.FlowDirection='TopDown';$servicePanel.WrapContents=$false;$servicePanel.Margin=New-Object Windows.Forms.Padding(0,4,0,8)
$script:serviceChecks=@()
foreach($group in @(@('OptionalWindows','Windows ít dùng: Fax, Maps, Retail Demo, Remote Registry, WMP', $true),@('Xbox','Xbox: đăng nhập, lưu cloud, phụ kiện — không dùng Game Pass', $true),@('Printing','In ấn: tắt máy in và Microsoft Print to PDF', $false),@('Search','Chỉ mục tìm kiếm: tìm file có thể chậm hơn', $false),@('ConnectedDevices','Thiết bị kết nối: tắt chia sẻ và trải nghiệm liên thiết bị', $false),@('Diagnostics','Chẩn đoán từ xa: giảm gửi dữ liệu sử dụng', $false))){
    $box=New-Object Windows.Forms.CheckBox;$box.Text=$group[1];$box.Tag=$group[0];$box.AutoSize=$true;$box.Checked=[bool]$group[2];$box.Margin=New-Object Windows.Forms.Padding(0,1,0,7);$box.AccessibleName=$group[1]
    $serviceChecks+=@($box);$servicePanel.Controls.Add($box)
}
$content.Controls.Add($servicePanel)
$script:quickServices=New-Object Windows.Forms.CheckBox;$quickServices.Text='Thêm tối ưu dịch vụ cơ bản (Windows ít dùng + Xbox)';$quickServices.Checked=$true;$quickServices.AutoSize=$true;$quickServices.Margin=New-Object Windows.Forms.Padding(0,4,0,8);$quickServices.AccessibleName=$quickServices.Text;$content.Controls.Add($quickServices)
$script:note=New-ToolkitLabel '' 9;$note.ForeColor=Get-ToolkitColor Muted;$content.Controls.Add($note)
$actionHost=New-Object Windows.Forms.FlowLayoutPanel;$actionHost.Dock='Fill';$actionHost.FlowDirection='TopDown';$actionHost.WrapContents=$false;$actionHost.BackColor=Get-ToolkitColor Surface;$actionHost.Padding=New-Object Windows.Forms.Padding(20,4,20,0);$right.Controls.Add($actionHost,0,1)
$actionPanel=New-Object Windows.Forms.FlowLayoutPanel;$actionPanel.AutoSize=$true;$actionPanel.WrapContents=$true;$actionPanel.FlowDirection='LeftToRight';$actionPanel.Margin=New-Object Windows.Forms.Padding(0)
$script:primary=New-ToolkitButton 'Thực hiện';$primary.AutoSize=$true;$primary.MinimumSize=New-Object Drawing.Size(210,44);$primary.Dock='None';$primary.BackColor=Get-ToolkitColor Primary;$primary.ForeColor=[Drawing.Color]::White;$primary.Padding=New-Object Windows.Forms.Padding(12,0,12,0)
$script:secondary=New-ToolkitButton 'Xem trước';$secondary.AutoSize=$true;$secondary.MinimumSize=New-Object Drawing.Size(210,44);$secondary.Dock='None';$secondary.Margin=New-Object Windows.Forms.Padding(8,0,0,0)
$script:updateStatus=New-ToolkitButton 'Kiểm tra trạng thái';$updateStatus.AutoSize=$true;$updateStatus.Dock='None';$updateStatus.Margin=New-Object Windows.Forms.Padding(0)
$actionPanel.Controls.Add($primary);$actionPanel.Controls.Add($secondary);$actionHost.Controls.Add($actionPanel);$actionHost.Controls.Add($updateStatus)
$taskButtons.Add($primary);$taskButtons.Add($secondary);$taskButtons.Add($updateStatus)
$primary.Add_Click({Start-ToolkitTask $script:primaryAction});$secondary.Add_Click({Start-ToolkitTask $script:secondaryAction});$updateStatus.Add_Click({Start-ToolkitTask $script:statusAction})
$resultPanel=New-Object Windows.Forms.TableLayoutPanel;$resultPanel.Dock='Fill';$resultPanel.RowCount=3;$resultPanel.ColumnCount=1;$resultPanel.Padding=New-Object Windows.Forms.Padding(0,12,0,0)
$resultPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',48)))|Out-Null
$resultPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',12)))|Out-Null
$resultPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent',100)))|Out-Null;$right.Controls.Add($resultPanel,0,2)
$script:status=New-ToolkitLabel 'Sẵn sàng. Chưa có tác vụ nào được thực hiện.' 10 $true;$status.Dock='Fill';$resultPanel.Controls.Add($status,0,0)
$script:progress=New-Object Windows.Forms.ProgressBar;$progress.Dock='Fill';$progress.MarqueeAnimationSpeed=30;$resultPanel.Controls.Add($progress,0,1)
$script:resultGrid=New-Object Windows.Forms.DataGridView;$resultGrid.Dock='Fill';$resultGrid.ReadOnly=$true;$resultGrid.AllowUserToAddRows=$false;$resultGrid.AllowUserToDeleteRows=$false;$resultGrid.RowHeadersVisible=$false;$resultGrid.AutoSizeColumnsMode='Fill';$resultGrid.BackgroundColor=Get-ToolkitColor Surface;$resultGrid.BorderStyle='None';$resultGrid.SelectionMode='FullRowSelect';$resultGrid.AutoSizeRowsMode='AllCells';$resultGrid.DefaultCellStyle.WrapMode='True'
$null=$resultGrid.Columns.Add('Step','Tác vụ');$null=$resultGrid.Columns.Add('Result','Kết quả');$null=$resultGrid.Columns.Add('Message','Thông tin')
$resultGrid.Columns[0].FillWeight=25;$resultGrid.Columns[1].FillWeight=20;$resultGrid.Columns[2].FillWeight=55;$resultPanel.Controls.Add($resultGrid,0,2)
$outer.Controls.Add((New-ToolkitLabel 'Chạy trong máy ảo • Giữ màu/nền • Sao lưu giao diện, dịch vụ và cập nhật • Không tự khởi động lại' 9),0,2)
$resizeContent={
    $width=[Math]::Max(300,$content.ClientSize.Width-56)
    foreach($label in @($script:pageTitle,$script:description,$script:note)){$label.MaximumSize=New-Object Drawing.Size($width,0)}
    foreach($box in @($script:appChecks)+@($script:serviceChecks)+@($script:quickServices)){$box.MaximumSize=New-Object Drawing.Size($width,0)}
    $actionPanel.MaximumSize=New-Object Drawing.Size($width,0)
}
$content.Add_SizeChanged($resizeContent)
$script:pollTimer=New-Object Windows.Forms.Timer;$pollTimer.Interval=700
$pollTimer.Add_Tick({
    try{
        $path=Join-Path $script:currentRun 'status.json'
        if(Test-Path -LiteralPath $path){
            try{$s=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8))}catch{$s=$null}
            if($s -and $s.State -in @('Running','Completed','Partial','Failed')){
            $fingerprint=ConvertTo-Json -InputObject $s -Depth 10 -Compress
            if($fingerprint -cne $script:lastStateText){
                $script:lastStateText=$fingerprint;$script:status.Text=[string]$s.Message
                $script:resultGrid.Rows.Clear()
                foreach($r in @($s.Results)){
                    $state=if($r.DisplayState){[string]$r.DisplayState}else{switch([string]$r.State){'Completed'{'Hoàn tất'} 'Partial'{'Một phần'} 'Failed'{'Thất bại'} 'Running'{'Đang chạy'} default{if($r.Success -eq $true){'Hoàn tất'}else{'Cần kiểm tra'}}}}
                    $displayNames=@{PreviewCleanup='Xem trước';Cleanup='Dọn app';Install='Cài phần mềm';UpdateStatus='Kiểm tra Update';UpdateBlock='Chặn Update';UpdateRestore='Khôi phục Update';UiApply='Tối giản giao diện';UiRestore='Khôi phục giao diện';Activation='Công cụ riêng'}
                    $name=if($r.Name){[string]$r.Name}elseif($displayNames.ContainsKey([string]$r.Action)){$displayNames[[string]$r.Action]}else{'Tác vụ'}
                    $message=[string]$r.Message
                    if($r.Action -eq 'UpdateStatus' -and $r.ModuleResult){
                        $block=if($r.ModuleResult.PolicyRequestsBlock){'có'}else{'không'}
                        $backup=if($r.ModuleResult.BackupActive){'có'}else{'không'}
                        $supported=if($r.ModuleResult.Supported){'có'}else{'không'}
                        $message='Chính sách yêu cầu chặn: '+$block+'. Bản sao lưu đang hoạt động: '+$backup+'. Phiên bản Windows hỗ trợ: '+$supported+'.'
                    }
                    $null=$script:resultGrid.Rows.Add($name,$state,$message)
                    if($r.Action -eq 'PreviewCleanup' -and $r.ModuleResult){
                        foreach($app in @($r.ModuleResult.Results)){$null=$script:resultGrid.Rows.Add([string]$app.Name,'Xem trước','App sẽ được gỡ khi chọn Dọn app.')}
                    }
                    if($r.Action -eq 'Install' -and $r.ModuleResult){
                        $appNames=@{Chrome='Google Chrome';WinRAR='WinRAR';DotNet8='.NET Desktop 8';VCx86='Visual C++ x86';VCx64='Visual C++ x64'}
                        foreach($app in @($r.ModuleResult.Results)){
                            $appState=switch([string]$app.Status){'Present'{'Đã có'} 'Installed'{'Đã cài'} 'Planned'{'Dự kiến'} 'NotRun'{'Chưa chạy'} default{'Lỗi'}}
                            $null=$script:resultGrid.Rows.Add($appNames[[string]$app.App],$appState,[string]$app.Message)
                        }
                    }
                    if($r.Action -like 'Services*' -and $r.ModuleResult){
                        foreach($service in @($r.ModuleResult.Results)){
                            $serviceState=switch([string]$service.Status){'Missing'{'Không có'} 'Planned'{'Dự kiến'} 'Current'{'Hiện tại'} 'Unchanged'{'Đã đúng / chỉ đọc'} 'Optimized'{'Đã tối ưu'} 'Restored'{'Đã khôi phục'} 'SkippedDependency'{'Bỏ qua: phụ thuộc'} default{'Lỗi'}}
                            $details=[string]$service.Message
                            if($service.Before){$details+=' | Trước: '+(ConvertTo-Json -InputObject $service.Before -Depth 4 -Compress)}
                            if($service.After){$details+=' | Sau: '+(ConvertTo-Json -InputObject $service.After -Depth 4 -Compress)}
                            $null=$script:resultGrid.Rows.Add([string]$service.Name,$serviceState,$details)
                        }
                    }
                }
            }
            if($s.State -in @('Completed','Partial','Failed')){
                $script:pollTimer.Stop();Set-ToolkitBusy $false
                $script:status.ForeColor=if($s.State -eq 'Completed'){[Drawing.Color]::DarkGreen}else{[Drawing.Color]::FromArgb(153,70,0)}
                if($s.RebootRequired){$script:status.Text+=' Cần khởi động lại khi em thuận tiện.'}
                $script:workerProcess=$null;return
            }
            }
        }
        if($script:workerProcess -and $script:workerProcess.HasExited){
            if(-not $script:exitSeen){$script:exitSeen=Get-Date}
            if(((Get-Date)-$script:exitSeen).TotalSeconds -ge 3){
                $script:pollTimer.Stop();Set-ToolkitBusy $false;$script:workerProcess=$null
                $script:status.Text='Tác vụ đã dừng nhưng chưa có kết quả đầy đủ. Bấm Mở nhật ký để xem lỗi.'
            }
        }
    }catch{$script:status.Text='Không đọc được trạng thái. Bấm Mở nhật ký để kiểm tra.'}
})
$form.Add_FormClosing({param($sender,$eventArgs)
    if($script:workerProcess){$eventArgs.Cancel=$true;Show-ToolkitMessage 'Đang có tác vụ chạy. Hãy chờ kết quả trước khi đóng cửa sổ.' 'Warning'}
})
$form.Add_FormClosed({$script:pollTimer.Stop();$script:pollTimer.Dispose()})
$form.Add_Shown({
    try{
        if(-not $script:form.Visible -or -not $script:form.IsHandleCreated){throw 'The toolkit window did not become visible.'}
        Write-ToolkitStartup 'Ready' 'Cửa sổ RAID VM Toolkit đã hiển thị.' '' ($script:form.Handle.ToInt64())
    }catch{
        Write-ToolkitStartup 'Failed' 'Không xác nhận được cửa sổ công cụ.' ($_|Out-String)
    }
})
Select-ToolkitSection 'Cleanup';Set-ToolkitBusy $false
if($RenderPreview){
    # Draw offscreen only: never Show(), activate a window, or run the UI loop.
    if(-not $SmokeImagePath){throw 'RenderPreview requires SmokeImagePath.'}
    Select-ToolkitSection $PreviewSection
    function Initialize-PreviewControl([Windows.Forms.Control]$Control){
        $null=$Control.Handle
        foreach($childControl in $Control.Controls){Initialize-PreviewControl $childControl}
        $Control.PerformLayout()
    }
    Initialize-PreviewControl $form
    $form.CreateControl();$form.PerformLayout();$outer.PerformLayout();$body.PerformLayout();$right.PerformLayout();$content.PerformLayout();$actionHost.PerformLayout();$actionPanel.PerformLayout()
    & $resizeContent
    $form.PerformLayout();$content.PerformLayout()
    $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
    try{$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save($SmokeImagePath,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose();$form.Dispose()}
    return
}
if($SmokeTest){
    $smokeTimer=New-Object Windows.Forms.Timer;$smokeTimer.Interval=1000
    $smokeTimer.Add_Tick({
        $smokeTimer.Stop()
        Select-ToolkitSection 'Install'
        if($SmokeImagePath){
            $bitmap=New-Object Drawing.Bitmap($script:form.Width,$script:form.Height)
            try{$script:form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)));$bitmap.Save($SmokeImagePath,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
        }
        $script:form.Close()
    })
    $form.Add_Shown({$smokeTimer.Start()})
}
try{[Windows.Forms.Application]::Run($form)}finally{
    $form.Dispose()
}
}catch{
    $startupError=($_|Out-String)+"`r`n"+$_.ScriptStackTrace
    try{Write-ToolkitStartup 'Failed' $_.Exception.GetBaseException().Message $startupError}catch{}
    throw
}finally{
    if($script:instanceMutex){if($ownsMutex){try{$script:instanceMutex.ReleaseMutex()}catch{}};$script:instanceMutex.Dispose()}
}
