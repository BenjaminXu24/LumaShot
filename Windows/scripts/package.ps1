param([ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
[xml]$taskProps = Get-Content (Join-Path $taskRoot 'Windows/Directory.Build.props')
$taskVersion = [string]$taskProps.Project.PropertyGroup.Version
$taskOutput = Join-Path $taskRoot "build/windows/$Runtime"
$taskRelease = Join-Path $taskRoot 'build/windows-releases'
New-Item $taskRelease -ItemType Directory -Force | Out-Null
dotnet publish (Join-Path $taskRoot 'Windows/LumaShot.Windows/LumaShot.Windows.csproj') -c Release -r $Runtime --self-contained true -p:DebugType=None -p:DebugSymbols=false -o $taskOutput
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
if (!(Test-Path (Join-Path $taskOutput 'LumaShot.exe')) -or !(Test-Path (Join-Path $taskOutput 'LICENSE.txt'))) { throw 'Publish is missing application or license.' }
$taskArch = $Runtime.Substring(4)
$taskZip = Join-Path $taskRelease "LumaShot-v$taskVersion-windows-$taskArch-portable.zip"
Compress-Archive -Path "$taskOutput/*" -DestinationPath $taskZip -Force
$taskCompiler = @("${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe", "$env:ProgramFiles/Inno Setup 6/ISCC.exe", "$env:ProgramFiles/Inno Setup 7/ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (!$taskCompiler) { throw 'Install Inno Setup 6.3+ to create the installer.' }
& $taskCompiler "/DAppVersion=$taskVersion" "/DRuntimeArch=$taskArch" "/DPublishDir=$taskOutput" "/DReleaseDir=$taskRelease" (Join-Path $taskRoot 'Windows/installer/LumaShot.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Get-ChildItem $taskRelease -File | Where-Object { $_.Name -match '\.(exe|zip)$' } | Sort-Object Name | ForEach-Object {
    $taskHash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$taskHash  $($_.Name)"
} | Set-Content (Join-Path $taskRelease 'SHA256SUMS-windows.txt') -Encoding utf8NoBOM
Write-Output "Packages: $taskRelease"
