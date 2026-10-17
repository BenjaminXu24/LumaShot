#requires -Version 7.2

$ErrorActionPreference = 'Stop'

function Get-LumaShotRoot {
    (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
}

function Invoke-LumaShotDotnet {
    param([Parameter(Mandatory)][string[]]$Arguments)
    Push-Location (Get-LumaShotRoot)
    try {
        & dotnet @Arguments
        if ($LASTEXITCODE -ne 0) { throw "dotnet $($Arguments[0]) failed (exit $LASTEXITCODE)." }
    }
    finally { Pop-Location }
}

function Assert-LumaShotEnvironment {
    param([switch]$Windows)
    if ($Windows -and !$IsWindows) { throw 'The WPF application requires Windows. Core tests can run with test.ps1 -CoreOnly.' }
    if ($Windows -and ![Environment]::Is64BitOperatingSystem) { throw 'LumaShot requires 64-bit Windows (x64 or ARM64).' }
    if (!(Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'Install the .NET 10 SDK (not only the runtime), reopen the terminal, and retry. See Windows/README.md.'
    }
    Push-Location (Get-LumaShotRoot)
    try {
        $taskSdk = & dotnet --version
        if ($LASTEXITCODE -ne 0 -or $taskSdk -notmatch '^10\.0\.\d+$') {
            throw 'A stable .NET 10 SDK is required by global.json. Install it, reopen the terminal, and retry.'
        }
        Write-Host "PowerShell $($PSVersionTable.PSVersion); .NET SDK $taskSdk; $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    }
    finally { Pop-Location }
}

function Resolve-LumaShotInnoCompiler {
    param([string]$InnoCompiler)
    if ($InnoCompiler) {
        if (!(Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) { throw "Inno compiler not found: $InnoCompiler" }
        $taskCompiler = (Resolve-Path -LiteralPath $InnoCompiler).Path
    }
    else {
        $taskCandidates = @()
        $taskCommand = Get-Command ISCC.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        foreach ($taskBase in (@(${env:ProgramFiles(x86)}, $env:ProgramFiles, "$env:LOCALAPPDATA/Programs") | Where-Object { $_ })) {
            foreach ($taskMajor in @(6, 7)) { $taskCandidates += Join-Path $taskBase "Inno Setup $taskMajor/ISCC.exe" }
        }
        # Package-manager PATH entries can be launcher shims with version 0.0.0.0.
        # Prefer the real compiler so its version can be checked before publishing.
        if ($taskCommand) { $taskCandidates += $taskCommand.Source }
        $taskCompiler = $taskCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if (!$taskCompiler) { throw 'Install Inno Setup 6.3+ or pass -InnoCompiler C:\path\to\ISCC.exe. See Windows/README.md.' }
    $taskVersionText = (Get-Item -LiteralPath $taskCompiler).VersionInfo.FileVersion
    if ($taskVersionText -notmatch '(\d+\.\d+(?:\.\d+)?)' -or [version]$Matches[1] -lt [version]'6.3') {
        throw "Inno Setup 6.3+ is required. Found: $taskVersionText ($taskCompiler). If this is a launcher shim, pass -InnoCompiler with the actual ISCC.exe path."
    }
    $taskCompiler
}
