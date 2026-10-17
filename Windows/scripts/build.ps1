#requires -Version 7.2
param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Release', [switch]$Run)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-LumaShotEnvironment -Windows
$taskProject = Join-Path (Get-LumaShotRoot) 'Windows/LumaShot.Windows/LumaShot.Windows.csproj'
Invoke-LumaShotDotnet -Arguments @('build', $taskProject, '-c', $Configuration)
if ($Run) { Invoke-LumaShotDotnet -Arguments @('run', '--project', $taskProject, '-c', $Configuration, '--no-build') }
