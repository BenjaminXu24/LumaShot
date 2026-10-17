#requires -Version 7.2
param([switch]$CoreOnly)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-LumaShotEnvironment -Windows:(!$CoreOnly)
$taskRoot = Get-LumaShotRoot
if (!$CoreOnly) {
    if (![Environment]::UserInteractive) { throw 'Native checks require an unlocked interactive Windows desktop. Use -CoreOnly for a headless session.' }
    if (Get-Process -Name LumaShot -ErrorAction SilentlyContinue) { throw 'Quit LumaShot from its tray menu before native checks (closing the main window leaves it running).' }
    Write-Host 'Native checks use the mouse, shortcuts, and clipboard. Keep the desktop unlocked and do not use the mouse until completion.'
}
Invoke-LumaShotDotnet -Arguments @('run', '--project', (Join-Path $taskRoot 'Windows/LumaShot.Core.Tests'), '-c', 'Release')
if ($CoreOnly) { return }

& (Join-Path $PSScriptRoot 'build.ps1')
$taskOutput = Join-Path $taskRoot 'build/windows-smoke'
# A unique directory prevents an old report or partial history from affecting a rerun.
$taskRunOutput = Join-Path $taskOutput (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff')
New-Item $taskRunOutput -ItemType Directory -Force | Out-Null
$taskDll = Join-Path $taskRoot 'Windows/LumaShot.Windows/bin/Release/net10.0-windows/LumaShot.dll'
$taskDotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
$taskProcess = Start-Process -FilePath $taskDotnet -ArgumentList @('"' + $taskDll + '"', '--smoke-test', '"' + $taskRunOutput + '"') -PassThru
try {
    if (!$taskProcess.WaitForExit(120000)) { $taskProcess.Kill($true); throw 'Native smoke test timed out after 120 seconds.' }
    if ($taskProcess.ExitCode -ne 0) {
        if (Test-Path (Join-Path $taskRunOutput 'failure.txt')) { Get-Content (Join-Path $taskRunOutput 'failure.txt') | Write-Host }
        throw "Native smoke test failed (exit $($taskProcess.ExitCode)). Diagnostics: $taskRunOutput"
    }
    $taskReport = Join-Path $taskRunOutput 'checks.json'
    if (!(Test-Path $taskReport)) { throw "Native smoke test did not write checks.json. Diagnostics: $taskRunOutput" }
    Get-Content $taskReport | Write-Host
    Write-Host "All checks passed. Diagnostics: $taskRunOutput"
}
finally { $taskProcess.Dispose() }
