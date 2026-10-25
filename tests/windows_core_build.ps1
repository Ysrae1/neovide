#requires -Version 5.1
<# Isolated core-build timeout/log regression. No build, install, download or GUI.
   On non-Windows hosts a temporary no-op taskkill shim lets the owned child exit
   naturally after three seconds; this does not validate Windows taskkill. #>
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path $PSScriptRoot -Parent) 'portable/windows/build-core.ps1'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ('Core build script has parse errors: '+($parseErrors -join '; ')) }
foreach ($name in @('Quote-CoreArgument','Invoke-CoreBuild')) {
    $functions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true))
    if ($functions.Count -ne 1) { throw ('Expected exactly one actual function: '+$name) }
    Invoke-Expression $functions[0].Extent.Text
}
$work=Join-Path ([IO.Path]::GetTempPath()) ('glow-core-build-test-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
$savedWindir=$env:WINDIR
$windowsHost=$env:OS -eq 'Windows_NT'
try {
    if (-not $windowsHost) {
        $env:WINDIR=Join-Path $work 'windows-shim'
        $system32=Join-Path $env:WINDIR 'System32'
        $null=New-Item -ItemType Directory -Path $system32
        $shim=Join-Path $system32 'taskkill.exe'
        [IO.File]::WriteAllText($shim,"#!/bin/sh`nexit 0`n",[Text.UTF8Encoding]::new($false))
        & chmod '+x' $shim
        if ($LASTEXITCODE -ne 0) { throw 'Unable to make the isolated taskkill shim executable.' }
    }
    $child=Join-Path $work 'timeout-child.ps1'
    [IO.File]::WriteAllText($child,@'
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'child.pid'),[string]$PID)
[Console]::Out.WriteLine('core-timeout-stdout-marker')
[Console]::Error.WriteLine('core-timeout-stderr-marker')
Start-Sleep -Seconds 3
'@,[Text.UTF8Encoding]::new($false))
    $executable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $caught=$null
    try { Invoke-CoreBuild $executable @('-NoProfile','-NonInteractive','-File',$child) 'timeout-fixture' 1 }
    catch { $caught=$_.Exception.Message }
    $log=Join-Path $work 'timeout-fixture.log'
    if (-not $caught -or $caught -notlike 'Build phase timed out: timeout-fixture*') { throw ('Expected the original timeout failure, got: '+$caught) }
    if (-not $caught.Contains($log)) { throw ('Timeout failure does not point to the saved log: '+$caught) }
    $output=[IO.File]::ReadAllText($log)
    foreach ($marker in @('core-timeout-stdout-marker','core-timeout-stderr-marker')) {
        if (-not $output.Contains($marker)) { throw ('Timeout output was lost: '+$marker) }
    }
    $childId=[int][IO.File]::ReadAllText((Join-Path $work 'child.pid'))
    $remaining=Get-Process -Id $childId -ErrorAction SilentlyContinue
    if ($remaining) { throw 'The isolated timeout child is still running.' }
    if ($windowsHost) { Write-Output 'PASS: core timeout preserves stdout/stderr and the owned Windows child exits.' }
    else { Write-Output 'PASS: core timeout preserves stdout/stderr after natural child exit; Windows taskkill was not exercised.' }
} finally {
    $env:WINDIR=$savedWindir
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
