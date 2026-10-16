# Run once per host: powershell/pwsh -NoProfile -File tests/run.ps1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('sycol-tests-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$original=Get-Location
try {
    Set-Location -LiteralPath $root
    $engine=(Get-Process -Id $PID).Path
    & $engine -NoProfile -ExecutionPolicy Bypass -File ./sycol.ps1 tests/all.tcl $temp 'argument with spaces; $literal [brackets]'
    if ($LASTEXITCODE) { throw 'Shared Tcl suite failed' }
    . ./sycol.ps1
    Register-SyNative host.echo {
        param([string[]]$Words)
        if ($Words.Count -ne 1) { Set-SyArity 'host.echo value'; return }
        $script:Sy.R=$Words[0]; $script:Sy.C=0
    }
    Invoke-SyCommand @('source','tests/native.tcl')
    if ($script:Sy.C) { throw $script:Sy.R }
    ConvertTo-SyList @($engine,'-NoProfile','-ExecutionPolicy','Bypass','-File',"$root/tests/fixtures/probe.ps1")
    $probe=$script:Sy.R
    & $engine -NoProfile -ExecutionPolicy Bypass -File ./sycol.ps1 tests/exec.tcl $probe $temp
    if ($LASTEXITCODE) { throw 'Process suite failed' }
} finally {
    Set-Location -LiteralPath $original.ProviderPath
    # Only the known generated file and this empty, unique directory are removed.
    [IO.File]::Delete((Join-Path $temp 'round trip.txt'))
    [IO.Directory]::Delete($temp)
}
