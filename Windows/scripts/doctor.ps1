#requires -Version 7.2
param([switch]$Packaging, [string]$InnoCompiler)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-LumaShotEnvironment -Windows
if ($Packaging) {
    $taskCompiler = Resolve-LumaShotInnoCompiler -InnoCompiler $InnoCompiler
    Write-Host "Inno Setup: $taskCompiler"
}
Write-Host 'Environment ready. See Windows/README.md for build, test, and packaging commands.'
