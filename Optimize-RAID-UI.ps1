#Requires -Version 5.1
<#
Windows 11 VM desktop preferences; optional external MAS command requested by user.
Menu: 4 minimal desktop; 5 restore desktop; 6 open external MAS; 0 exit.
Options 4/5 do not remove/install apps or change Windows Update.
Applies to the currently signed-in desktop user and restarts that user's Explorer.
File Explorer windows may close; finish any file copies before applying/restoring.
#>
[CmdletBinding()]
param([ValidateSet('Menu','Apply','Restore','Preview','Activation')][string]$Action='Menu')

$ErrorActionPreference='Stop'
if ($env:COMPUTERNAME -eq 'DESKTOP-IMKRT09' -and $Action -ne 'Preview') {
    throw 'This is the known real host PC. Run this UI command inside a Windows 11 VM.'
}
if ([Environment]::OSVersion.Version.Build -lt 22000) { throw 'Windows 11 is required.' }

function Get-RaidRegistrySnapshot([string]$Path,[string]$Name) {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path,$false)
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
function Set-RaidRegistrySnapshot($Entry) {
    if (-not $Entry.Exists) {
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey([string]$Entry.Path,$true)
        try { if ($key) { $key.DeleteValue([string]$Entry.Name,$false) } }
        finally { if ($key) { $key.Dispose() } }
        return
    }
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey([string]$Entry.Path)
    try {
        $kind=[Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$Entry.Kind)
        $value=$Entry.Value
        switch ([string]$Entry.Kind) {
            'DWord' {$value=[int]$value}
            'QWord' {$value=[long]$value}
            'Binary' {$value=[byte[]]$value}
            'MultiString' {$value=[string[]]$value}
            'String' {$value=[string]$value}
            'ExpandString' {$value=[string]$value}
            default {throw ('Unsupported registry kind: '+$Entry.Kind)}
        }
        $key.SetValue([string]$Entry.Name,$value,$kind)
    } finally { $key.Dispose() }
}

$advanced='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$settings=@(
    [pscustomobject]@{Path=$advanced;Name='TaskbarAl';Kind='DWord';Value=0;Exists=$true}
    [pscustomobject]@{Path=$advanced;Name='TaskbarDa';Kind='DWord';Value=0;Exists=$true}
    [pscustomobject]@{Path=$advanced;Name='ShowTaskViewButton';Kind='DWord';Value=0;Exists=$true}
    [pscustomobject]@{Path='Software\Microsoft\Windows\CurrentVersion\Search';Name='SearchboxTaskbarMode';Kind='DWord';Value=0;Exists=$true}
    [pscustomobject]@{Path='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';Name='EnableTransparency';Kind='DWord';Value=0;Exists=$true}
    [pscustomobject]@{Path='Control Panel\Colors';Name='Background';Kind='String';Value='24 24 24';Exists=$true}
    [pscustomobject]@{Path='Control Panel\Desktop';Name='Wallpaper';Kind='String';Value='';Exists=$true}
)

if ($Action -eq 'Preview') {
    $settings | Select-Object Name,Value | Format-Table -AutoSize
    Write-Host 'Also disables UI animation/drop-shadow preferences and uses a solid dark background.'
    Write-Host 'Keeps existing pinned apps, fonts, drivers, game, power and Windows Update settings.'
    Write-Host 'Preview only: no preferences changed and no Explorer restart.'
    return
}

if (-not ('RaidVmUiNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class RaidVmUiNative {
    [StructLayout(LayoutKind.Sequential)] private struct ANIMATIONINFO { public uint cbSize; public int iMinAnimate; }
    [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)] private static extern bool Spi(uint action,uint param,IntPtr value,uint flags);
    [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool SpiText(uint action,uint param,string value,uint flags);
    [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool SpiReadText(uint action,uint param,StringBuilder value,uint flags);
    [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)] private static extern bool SpiAnimation(uint action,uint param,ref ANIMATIONINFO value,uint flags);
    [DllImport("user32.dll")] private static extern uint GetSysColor(int index);
    [DllImport("user32.dll", SetLastError=true)] private static extern bool SetSysColors(int count,int[] indexes,int[] colors);
    [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr SendMessageTimeout(IntPtr window,uint msg,UIntPtr wParam,string lParam,uint flags,uint timeout,out UIntPtr result);
    private static void Check(bool ok) { if(!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public static bool GetFlag(uint action) {
        IntPtr ptr=Marshal.AllocHGlobal(4);
        try { Marshal.WriteInt32(ptr,0); Check(Spi(action,0,ptr,0)); return Marshal.ReadInt32(ptr)!=0; }
        finally { Marshal.FreeHGlobal(ptr); }
    }
    public static void SetFlag(uint action,bool value) { Check(Spi(action,0,new IntPtr(value?1:0),3)); }
    public static bool GetMinAnimation() {
        ANIMATIONINFO info=new ANIMATIONINFO(); info.cbSize=(uint)Marshal.SizeOf(typeof(ANIMATIONINFO));
        Check(SpiAnimation(0x48,info.cbSize,ref info,0)); return info.iMinAnimate!=0;
    }
    public static void SetMinAnimation(bool enabled) {
        ANIMATIONINFO info=new ANIMATIONINFO(); info.cbSize=(uint)Marshal.SizeOf(typeof(ANIMATIONINFO)); info.iMinAnimate=enabled?1:0;
        Check(SpiAnimation(0x49,info.cbSize,ref info,3));
    }
    public static string GetWallpaper() { StringBuilder text=new StringBuilder(2048); Check(SpiReadText(0x73,2048,text,0)); return text.ToString(); }
    public static void SetWallpaper(string path) { Check(SpiText(0x14,0,path,3)); }
    public static int GetBackground() { return unchecked((int)GetSysColor(1)); }
    public static void SetBackground(int color) { Check(SetSysColors(1,new int[]{1},new int[]{color})); }
    public static uint GetShellPid() { uint pid; GetWindowThreadProcessId(GetShellWindow(),out pid); return pid; }
    public static void Notify() { UIntPtr result; SendMessageTimeout(new IntPtr(0xffff),0x1a,UIntPtr.Zero,"TraySettings",2,2000,out result); }
}
'@
}

$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$userSid=$identity.User.Value
$shellPid=[RaidVmUiNative]::GetShellPid()
if (-not $shellPid) { throw 'Run this command from the signed-in Windows desktop, not a background service.' }
$shellCim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$shellPid)
$shellOwner=Invoke-CimMethod -InputObject $shellCim -MethodName GetOwnerSid
if ($shellOwner.ReturnValue -ne 0 -or $shellOwner.Sid -ne $userSid) {
    throw 'PowerShell must run as the same account that owns this Windows desktop.'
}
$stateFolder=Join-Path $env:LOCALAPPDATA 'RaidVM-UI'
$statePath=Join-Path $stateFolder 'desktop-before.json'

function Restart-RaidExplorer {
    [RaidVmUiNative]::Notify()
    $desktopProcessId=[RaidVmUiNative]::GetShellPid()
    $shell=Get-Process -Id $desktopProcessId -ErrorAction SilentlyContinue
    if (-not $shell -or $shell.ProcessName -ne 'explorer' -or $shell.SessionId -ne (Get-Process -Id $PID).SessionId) {
        Write-Warning 'Could not safely identify this desktop shell. Sign out and back in to refresh the taskbar.'
        return
    }
    Stop-Process -Id $desktopProcessId -Force
    Start-Sleep -Seconds 2
    if ([RaidVmUiNative]::GetShellWindow() -eq [IntPtr]::Zero) {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') | Out-Null
    }
}
function Read-RaidUiBackup {
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    $saved=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($statePath))
    if ($saved.Schema -ne 1 -or $saved.UserSid -ne $userSid) { throw 'The saved UI backup is incompatible with this Windows user.' }
    return $saved
}
function Save-RaidUiBackup($State) {
    New-Item -ItemType Directory -Path $stateFolder -Force | Out-Null
    $tempPath=$statePath+'.tmp'
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $statePath -Force
}
function Invoke-RaidUiApply {
    $saved=Read-RaidUiBackup
    if (-not $saved -or -not $saved.Active) {
        $saved=[pscustomobject]@{
            Schema=1;UserSid=$userSid;ComputerName=$env:COMPUTERNAME;SavedAt=(Get-Date).ToString('o');Active=$true
            Registry=@($settings | ForEach-Object {Get-RaidRegistrySnapshot $_.Path $_.Name})
            Native=[pscustomobject]@{
                UiEffects=[RaidVmUiNative]::GetFlag(0x103e)
                ClientAnimation=[RaidVmUiNative]::GetFlag(0x1042)
                DropShadow=[RaidVmUiNative]::GetFlag(0x1024)
                MinAnimation=[RaidVmUiNative]::GetMinAnimation()
                Wallpaper=[RaidVmUiNative]::GetWallpaper()
                Background=[RaidVmUiNative]::GetBackground()
            }
        }
        Save-RaidUiBackup $saved
    }
    foreach ($setting in $settings) { Set-RaidRegistrySnapshot $setting }
    [RaidVmUiNative]::SetFlag(0x103f,$false)
    [RaidVmUiNative]::SetFlag(0x1043,$false)
    [RaidVmUiNative]::SetFlag(0x1025,$false)
    [RaidVmUiNative]::SetMinAnimation($false)
    [RaidVmUiNative]::SetWallpaper('')
    [RaidVmUiNative]::SetBackground(0x181818)
    Restart-RaidExplorer
    Write-Host 'Applied: left-aligned Start/icons; hidden Widgets/weather, Search and Task View; reduced effects; solid dark background.' -ForegroundColor Green
    Write-Host ('Original preferences saved: '+$statePath)
    Write-Host 'Fonts, pinned apps, installed apps, game drivers and Windows Update were not changed.'
}
function Invoke-RaidUiRestore {
    $saved=Read-RaidUiBackup
    if (-not $saved -or -not $saved.Active) { Write-Host 'No active UI backup to restore.';return }
    [RaidVmUiNative]::SetFlag(0x103f,[bool]$saved.Native.UiEffects)
    [RaidVmUiNative]::SetFlag(0x1043,[bool]$saved.Native.ClientAnimation)
    [RaidVmUiNative]::SetFlag(0x1025,[bool]$saved.Native.DropShadow)
    [RaidVmUiNative]::SetMinAnimation([bool]$saved.Native.MinAnimation)
    [RaidVmUiNative]::SetWallpaper([string]$saved.Native.Wallpaper)
    [RaidVmUiNative]::SetBackground([int]$saved.Native.Background)
    foreach ($entry in @($saved.Registry)) { Set-RaidRegistrySnapshot $entry }
    Restart-RaidExplorer
    $saved.Active=$false
    Save-RaidUiBackup $saved
    Write-Host 'Previous desktop preferences restored.' -ForegroundColor Green
}

function Invoke-RaidActivationTool {
    Write-Host 'Opening the external MAS command requested by the user:' -ForegroundColor Cyan
    Write-Host 'irm https://get.activated.win | iex'
    Write-Host 'This runs third-party code and can request administrator access.'
    Write-Host 'Option 5 restores desktop preferences only; it does not undo actions performed in MAS.'
    $powerShellExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # A separate interactive process keeps the external script out of this menu's scope.
    $tool=Start-Process -FilePath $powerShellExe -ArgumentList '-NoProfile -Command "irm https://get.activated.win | iex"' -Wait -PassThru
    Write-Host ('External PowerShell window closed. Exit code: '+$tool.ExitCode)
}

if ($Action -eq 'Menu') {
    Write-Host ''
    Write-Host 'RAID VM - Menu giao dien' -ForegroundColor Cyan
    Write-Host '4. Toi gian giao dien: Start ben trai, an thoi tiet/Search/Task View, giam hieu ung'
    Write-Host '5. Khoi phuc giao dien da luu'
    Write-Host '6. Mo MAS: irm https://get.activated.win | iex (cong cu ben thu ba)'
    Write-Host '0. Thoat'
    Write-Host 'Luu y: 4/5 tai lai taskbar; cua so File Explorer co the dong. Hoan tat chep file truoc.'
    switch (Read-Host 'Chon 4, 5, 6 hoac 0') {
        '4' {$Action='Apply'}
        '5' {$Action='Restore'}
        '6' {$Action='Activation'}
        '0' {return}
        default {Write-Host 'Khong thay doi gi.';return}
    }
}
if ($Action -eq 'Apply') { Invoke-RaidUiApply }
if ($Action -eq 'Restore') { Invoke-RaidUiRestore }
if ($Action -eq 'Activation') { Invoke-RaidActivationTool }
