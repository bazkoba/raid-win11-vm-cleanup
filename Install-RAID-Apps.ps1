#Requires -Version 5.1
<#
Install selected apps/runtimes in a Windows 11 x64 VM. Never removes apps.
Downloads from official vendors and verifies every required installer before
launching any installer. Existing matching installations are preserved.
WinRAR is a trial. This script does not provide a license or activate software.
#>
[CmdletBinding()]
param(
    [ValidateSet('Chrome','WinRAR','DotNet8','VCx86','VCx64')]
    [string[]]$Apps=@('Chrome','WinRAR','DotNet8','VCx86','VCx64'),
    [switch]$Preview,
    [string]$ResultPath
)
$ErrorActionPreference='Stop'

function Get-RaidInstalledApp([string]$App) {
    switch ($App) {
        'Chrome' {
            $paths=@(
                (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
                (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
                (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
            )
            $file=$paths | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
            $version=if($file){(Get-Item -LiteralPath $file).VersionInfo.ProductVersion}else{$null}
            return [pscustomobject]@{Present=[bool]$file;Version=$version}
        }
        'WinRAR' {
            $file=@((Join-Path $env:ProgramFiles 'WinRAR\WinRAR.exe'),(Join-Path ${env:ProgramFiles(x86)} 'WinRAR\WinRAR.exe')) | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
            $version=if($file){(Get-Item -LiteralPath $file).VersionInfo.ProductVersion}else{$null}
            return [pscustomobject]@{Present=[bool]$file;Version=$version}
        }
        'DotNet8' {
            $desktop=Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.WindowsDesktop.App'
            $versions=@(Get-ChildItem -LiteralPath $desktop -Directory -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match '^8\.0\.\d+$' -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'System.Windows.Forms.dll') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'PresentationFramework.dll') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $env:ProgramFiles ('dotnet\shared\Microsoft.NETCore.App\'+$_.Name+'\coreclr.dll')) -PathType Leaf)
            } | Sort-Object {[version]$_.Name} -Descending)
            $version=if($versions.Count){$versions[0].Name}else{$null}
            return [pscustomobject]@{Present=$versions.Count -gt 0;Version=$version}
        }
        {$_ -in @('VCx86','VCx64')} {
            $arch=if($App -eq 'VCx86'){'x86'}else{'x64'}
            foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
                $base=$null;$key=$null
                try {
                    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
                    $key=$base.OpenSubKey(('SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\'+$arch),$false)
                    if($key -and [int]$key.GetValue('Installed',0) -eq 1) {
                        $version=[string]$key.GetValue('Version','')
                        $parsed=$null
                        if([version]::TryParse($version.TrimStart('v','V'),[ref]$parsed) -and $parsed.Major -eq 14) {
                            return [pscustomobject]@{Present=$true;Version=$version}
                        }
                    }
                } finally {if($key){$key.Dispose()};if($base){$base.Dispose()}}
            }
            return [pscustomobject]@{Present=$false;Version=$null}
        }
        default {throw ('Unsupported app: '+$App)}
    }
}

function Resolve-RaidInstaller([string]$App,[string]$Folder) {
    $publisher='(^|,\s*)O="?Microsoft Corporation"?(,|$)'
    $sha512=$null;$version=$null;$type='exe'
    switch ($App) {
        'Chrome' {
            $uri='https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
            $publisher='(^|,\s*)O="?Google (LLC|Inc\.)"?(,|$)';$type='msi';$file='Chrome-x64.msi'
        }
        'WinRAR' {
            $page=Invoke-WebRequest -UseBasicParsing -Uri 'https://www.rarlab.com/download.htm' -TimeoutSec 120
            $match=[regex]::Match($page.Content,'href\s*=\s*["''](?<path>/rar/winrar-x64-\d+\.exe)["'']','IgnoreCase')
            if(-not $match.Success){throw 'Không tìm thấy bản WinRAR x64 ổn định trên trang RARLAB.'}
            $uri='https://www.rarlab.com'+$match.Groups['path'].Value
            $publisher='(^|,\s*)O="?(win\.rar|WinRAR) GmbH"?(,|$)';$file='WinRAR-x64.exe'
        }
        'DotNet8' {
            $metadata=Invoke-RestMethod -Uri 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json' -TimeoutSec 120
            $release=@($metadata.releases | Where-Object {$_.'release-version' -match '^8\.0\.\d+$' -and $_.windowsdesktop.version -match '^8\.0\.\d+$'} | Sort-Object {[version]$_.windowsdesktop.version} -Descending | Select-Object -First 1)
            if($release.Count -ne 1){throw 'Không tìm thấy bản .NET Desktop Runtime 8 ổn định.'}
            $target=@($release[0].windowsdesktop.files | Where-Object {$_.rid -eq 'win-x64' -and $_.name -eq 'windowsdesktop-runtime-win-x64.exe'})
            if($target.Count -ne 1 -or $target[0].hash -notmatch '^[0-9a-fA-F]{128}$'){throw 'Metadata .NET Desktop Runtime không hợp lệ.'}
            $url=[uri]$target[0].url
            if($url.Scheme -ne 'https' -or $url.Host -notin @('builds.dotnet.microsoft.com','download.visualstudio.microsoft.com')){throw 'Địa chỉ bộ cài .NET không thuộc máy chủ Microsoft được phép.'}
            $uri=$url.AbsoluteUri;$sha512=[string]$target[0].hash;$version=[string]$release[0].windowsdesktop.version;$file='WindowsDesktop-Runtime8-x64.exe'
        }
        'VCx86' {$uri='https://aka.ms/vc14/vc_redist.x86.exe';$file='VC-redist-x86.exe'}
        'VCx64' {$uri='https://aka.ms/vc14/vc_redist.x64.exe';$file='VC-redist-x64.exe'}
        default {throw ('Unsupported app: '+$App)}
    }
    return [pscustomobject]@{App=$App;Uri=$uri;Path=(Join-Path $Folder $file);PublisherPattern=$publisher;Sha512=$sha512;Version=$version;Type=$type;LogPath=(Join-Path $Folder ($App+'-installer.log'))}
}

function Get-RaidVerifiedInstaller($Package) {
    Write-Host ('Đang tải '+$Package.App+' từ '+$Package.Uri)
    Invoke-WebRequest -UseBasicParsing -Uri $Package.Uri -OutFile $Package.Path -TimeoutSec 600
    if($Package.Sha512 -and (Get-FileHash -LiteralPath $Package.Path -Algorithm SHA512).Hash -ine $Package.Sha512){throw ('SHA-512 không khớp: '+$Package.App)}
    $signature=Get-AuthenticodeSignature -LiteralPath $Package.Path
    if($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch $Package.PublisherPattern){throw ('Chữ ký hoặc nhà phát hành không hợp lệ: '+$Package.App)}
    Write-Host ('Đã xác minh nhà phát hành: '+$signature.SignerCertificate.Subject)
}

function Invoke-RaidInstaller($Package) {
    if($Package.Type -eq 'msi') {
        $exe=Join-Path $env:SystemRoot 'System32\msiexec.exe'
        $arguments='/i "'+$Package.Path+'" /qn /norestart /L*v "'+$Package.LogPath+'"'
    } elseif($Package.App -eq 'WinRAR') {$exe=$Package.Path;$arguments='/S'}
    else {$exe=$Package.Path;$arguments='/install /quiet /norestart /log "'+$Package.LogPath+'"'}
    $process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    return [int]$process.ExitCode
}

function Save-RaidInstallResult($Report,[string]$Path) {
    if(-not $Path){return}
    $fullPath=[IO.Path]::GetFullPath($Path)
    $parent=Split-Path -Parent $fullPath
    if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $json=ConvertTo-Json -InputObject $Report -Depth 8
    [IO.File]::WriteAllText($fullPath,$json,(New-Object Text.UTF8Encoding($true)))
}

function Invoke-RaidAppInstall([string[]]$AppIds,[switch]$Preview,[string]$ResultPath) {
    $selected=@($AppIds | Select-Object -Unique)
    if(-not $selected.Count){throw 'Chưa chọn phần mềm để cài.'}
    foreach($app in $selected){if($app -notin @('Chrome','WinRAR','DotNet8','VCx86','VCx64')){throw ('Unsupported app: '+$app)}}
    $results=New-Object System.Collections.Generic.List[object]
    $packages=New-Object System.Collections.Generic.List[object]
    $report=[pscustomobject]@{Schema=1;Action='Install';Preview=[bool]$Preview;Success=$true;Partial=$false;Message='';RestartRequired=$false;LogFolder=$null;Results=@()}
    foreach($app in $selected) {
        try {
            $present=Get-RaidInstalledApp $app
            $status=if($present.Present){'Present'}elseif($Preview){'Planned'}else{'Pending'}
            $message=if($present.Present){'Đã có; giữ nguyên bản đang cài.'}elseif($Preview){'Sẽ tải bộ cài chính hãng, xác minh và cài đặt.'}else{'Đang chuẩn bị bộ cài.'}
            $results.Add([pscustomobject]@{App=$app;Status=$status;Success=$true;Version=$present.Version;ExitCode=$null;RestartRequired=$false;Message=$message})
            Write-Host ($app+': '+$message)
        } catch {
            $results.Add([pscustomobject]@{App=$app;Status='Failed';Success=$false;Version=$null;ExitCode=$null;RestartRequired=$false;Message=$_.Exception.GetBaseException().Message})
        }
    }
    if(-not $Preview -and @($results|Where-Object Status -eq 'Pending').Count) {
        $folder=Join-Path $env:ProgramData ('RaidVM-Toolkit\Install\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $folder -Force|Out-Null
        $report.LogFolder=$folder
        [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        foreach($result in @($results|Where-Object Status -eq 'Pending')) {
            try {
                $package=Resolve-RaidInstaller $result.App $folder
                Get-RaidVerifiedInstaller $package
                $packages.Add($package)
            } catch {$result.Status='Failed';$result.Success=$false;$result.Message=$_.Exception.GetBaseException().Message}
        }
        if(@($results|Where-Object {-not $_.Success}).Count) {
            foreach($result in @($results|Where-Object Status -eq 'Pending')){$result.Status='NotRun';$result.Success=$false;$result.Message='Chưa cài: một bộ cài được chọn chưa vượt qua bước chuẩn bị/xác minh.'}
        } else {
            foreach($package in $packages) {
                $result=$results|Where-Object App -eq $package.App|Select-Object -First 1
                try {
                    Write-Host ('Đang cài '+$package.App+'...')
                    $code=Invoke-RaidInstaller $package
                    $result.ExitCode=$code
                    $accepted=@(0,3010)
                    if($package.App -in @('VCx86','VCx64')){$accepted+=1638}
                    if($code -notin $accepted){throw ('Bộ cài trả mã lỗi '+$code+'. Xem nhật ký: '+$package.LogPath)}
                    $after=Get-RaidInstalledApp $package.App
                    if(-not $after.Present){throw ('Chưa xác nhận được '+$package.App+' sau khi cài. Xem nhật ký: '+$package.LogPath)}
                    if($package.Version -and [version]$after.Version -lt [version]$package.Version){throw 'Bản runtime đọc lại cũ hơn bản vừa yêu cầu cài.'}
                    $result.Status='Installed';$result.Version=$after.Version;$result.RestartRequired=$code -eq 3010
                    $result.Message='Đã cài và kiểm tra lại thành công.'
                } catch {$result.Status='Failed';$result.Success=$false;$result.Message=$_.Exception.GetBaseException().Message}
            }
        }
    }
    $report.Results=@($results.ToArray())
    $report.Success=@($results|Where-Object {-not $_.Success}).Count -eq 0
    $report.Partial=-not $report.Success -and @($results|Where-Object {$_.Success}).Count -gt 0
    $report.Message=if($Preview){'Đã xem trước các phần mềm đã chọn; chưa tải hoặc cài bộ cài.'}elseif($report.Success){'Các phần mềm đã chọn đã có hoặc đã cài và kiểm tra thành công.'}else{'Một số phần mềm chưa hoàn tất. Xem kết quả từng mục và nhật ký.'}
    $report.RestartRequired=@($results|Where-Object RestartRequired).Count -gt 0
    Save-RaidInstallResult $report $ResultPath
    if(-not $report.Success){
        $failedMessages=@($results|Where-Object {-not $_.Success}|ForEach-Object {$_.App+': '+$_.Message})
        throw ('Một số mục chưa hoàn tất. '+($failedMessages -join '; '))
    }
    return $report
}

if(-not $Preview) {
    if($env:COMPUTERNAME -eq 'DESKTOP-IMKRT09'){throw 'This is the known real host PC. Run this installer inside the Windows VM.'}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator privileges are required for installation.'}
    if(-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw 'Windows x64 and 64-bit Windows PowerShell are required.'}
    if([Environment]::OSVersion.Version.Build -lt 22000){throw 'Windows 11 is required.'}
}
Invoke-RaidAppInstall -AppIds $Apps -Preview:$Preview -ResultPath $ResultPath
