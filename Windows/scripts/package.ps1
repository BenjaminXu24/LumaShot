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
$taskAssets = Get-Content (Join-Path $taskRoot 'Windows/LumaShot.Windows/obj/project.assets.json') -Raw | ConvertFrom-Json
$taskDependencies = Get-Content (Join-Path $taskOutput 'LumaShot.deps.json') -Raw | ConvertFrom-Json
foreach ($taskPackage in @("microsoft.netcore.app.runtime.$Runtime", "microsoft.windowsdesktop.app.runtime.$Runtime")) {
    # Runtime packs are PackageDownload items, so they need not appear in assets.libraries.
    # Follow the published runtime version and the actual restore cache locations.
    $taskLibrary = $taskDependencies.libraries.PSObject.Properties | Where-Object { $_.Name.StartsWith("runtimepack.$taskPackage/", [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if (!$taskLibrary) { throw "Runtime package missing from published dependencies: $taskPackage" }
    $taskPackagePath = $taskLibrary.Name.Substring('runtimepack.'.Length).ToLowerInvariant()
    $taskPackageDirectory = $taskAssets.packageFolders.PSObject.Properties.Name | ForEach-Object { Join-Path $_ $taskPackagePath } | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
    if (!$taskPackageDirectory) { throw "Runtime license package not found: $($taskLibrary.Name)" }
    $taskNotices = Get-ChildItem -LiteralPath $taskPackageDirectory -File | Where-Object { $_.Name -match '^(LICENSE(\.TXT)?|THIRD-PARTY-NOTICES(\.TXT)?)$' }
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
