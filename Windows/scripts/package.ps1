#requires -Version 7.2
param(
    [ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64',
    [string]$InnoCompiler
)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-LumaShotEnvironment -Windows
$taskCompiler = Resolve-LumaShotInnoCompiler -InnoCompiler $InnoCompiler
$taskRoot = Get-LumaShotRoot
[xml]$taskProps = Get-Content (Join-Path $taskRoot 'Windows/Directory.Build.props')
$taskVersion = [string]$taskProps.Project.PropertyGroup.Version
$taskOutput = Join-Path $taskRoot "build/windows/$Runtime"
$taskRelease = Join-Path $taskRoot 'build/windows-releases'
New-Item $taskRelease -ItemType Directory -Force | Out-Null
Invoke-LumaShotDotnet -Arguments @('publish', (Join-Path $taskRoot 'Windows/LumaShot.Windows/LumaShot.Windows.csproj'), '-c', 'Release', '-r', $Runtime, '--self-contained', 'true', '-p:DebugType=None', '-p:DebugSymbols=false', '-o', $taskOutput)
if (!(Test-Path (Join-Path $taskOutput 'LumaShot.exe')) -or !(Test-Path (Join-Path $taskOutput 'LICENSE.txt'))) { throw 'Publish is missing application or license.' }
$taskNuget = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.nuget/packages' }
foreach ($taskPackage in @("microsoft.netcore.app.runtime.$Runtime", "microsoft.windowsdesktop.app.runtime.$Runtime")) {
    $taskPackageRoot = Join-Path $taskNuget $taskPackage
    if (!(Test-Path $taskPackageRoot)) { throw "Runtime license package not found: $taskPackage" }
    $taskPackageVersion = Get-ChildItem $taskPackageRoot -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $taskNotices = Get-ChildItem $taskPackageVersion.FullName -File | Where-Object { $_.Name -match '^(LICENSE(\.TXT)?|THIRD-PARTY-NOTICES(\.TXT)?)$' }
    if (!$taskNotices) { throw "Runtime license notices not found: $taskPackage" }
    $taskNoticeDir = Join-Path $taskOutput "third-party/$taskPackage"
    New-Item $taskNoticeDir -ItemType Directory -Force | Out-Null
    $taskNotices | Copy-Item -Destination $taskNoticeDir
}
$taskArch = $Runtime.Substring(4)
$taskZip = Join-Path $taskRelease "LumaShot-v$taskVersion-windows-$taskArch-portable.zip"
Compress-Archive -Path "$taskOutput/*" -DestinationPath $taskZip -Force
& $taskCompiler "/DAppVersion=$taskVersion" "/DRuntimeArch=$taskArch" "/DPublishDir=$taskOutput" "/DReleaseDir=$taskRelease" (Join-Path $taskRoot 'Windows/installer/LumaShot.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Get-ChildItem $taskRelease -File | Where-Object { $_.Name -match '\.(exe|zip)$' } | Sort-Object Name | ForEach-Object {
    $taskHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$taskHash  $($_.Name)"
} | Set-Content (Join-Path $taskRelease 'SHA256SUMS-windows.txt') -Encoding utf8NoBOM
Write-Output "Packages: $taskRelease"
