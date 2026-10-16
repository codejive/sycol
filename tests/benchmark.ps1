# Optional, non-gating timings. Use -Runtime to compare another installation.
param([string]$Runtime='.sycol/bin/sycol.ps1')
$ErrorActionPreference='Stop'
$original=Get-Location
$root=Split-Path $PSScriptRoot -Parent
$engine=(Get-Process -Id $PID).Path
$temp=Join-Path ([IO.Path]::GetTempPath()) ('sycol-benchmark-'+[Guid]::NewGuid().ToString('N'))
function Measure-SyCase([string]$Name,[int]$Count,[scriptblock]$Action) {
    & $Action
    if ($script:Sy.C) { throw $script:Sy.R }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    for ($iteration=0;$iteration -lt $Count;$iteration++) {
        & $Action
        if ($script:Sy.C) { throw $script:Sy.R }
    }
    $watch.Stop()
    [string]::Format([Globalization.CultureInfo]::InvariantCulture,
        '{0,-28} {1,10:F3} ms/run ({2} runs)',$Name,($watch.Elapsed.TotalMilliseconds/$Count),$Count)
}
try {
    Set-Location -LiteralPath $root
    $Runtime=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Runtime)
    . $Runtime
    [void][IO.Directory]::CreateDirectory($temp)
    $path=Join-Path $temp 'data.txt'
    $text='x'*16384
    [IO.File]::WriteAllText($path,('x'*65536),(New-Object Text.UTF8Encoding($false)))
    "PowerShell $($PSVersionTable.PSVersion); runtime $Runtime; one warmup per case"
    Measure-SyCase 'readfile 64 KiB' 20 { Invoke-SyNativeRead 'readfile' @($path) }
    Measure-SyCase 'load SDK' 5 { Import-SySdk }
    Measure-SyCase 'file exists (SDK)' 5 { Invoke-SyScript 'file exists .sycol/VERSION' }
    Measure-SyCase 'file join long path (SDK)' 3 {
        Invoke-SyScript 'file join C:/sycol-benchmark/long-temporary-directory/another-segment/filesystem child'
    }
    Measure-SyCase 'Windows path split (SDK)' 3 {
        Invoke-SyScript 'sy.path.parts {C:\sycol-benchmark\long-temporary-directory\another-segment\filesystem} 1'
    }
    Measure-SyCase 'startup + hello example' 5 {
        & $engine -NoProfile -ExecutionPolicy Bypass -File $Runtime examples/hello.tcl > $null
        if ($LASTEXITCODE) { throw 'benchmark startup failed' }
    }
    Measure-SyCase 'parse bare 16 KiB' 20 { Invoke-SyScript "set value $text" }
    Measure-SyCase 'parse quoted 16 KiB' 20 { Invoke-SyScript "set value `"$text`"" }
    Measure-SyCase 'parse braced 16 KiB' 20 { Invoke-SyScript "set value {$text}" }
    Measure-SyCase 'parse comment 16 KiB' 20 { Invoke-SyScript "#$text" }
    Measure-SyCase 'parse list 16 KiB' 20 { $null=ConvertFrom-SyList $text }
    Measure-SyCase 'encode list 16 KiB' 20 { ConvertTo-SyList @($text) }
    $commands='set value word;'*200
    $substitutions='set value value;'+('set copy prefix${value}[set value]tail;'*100)
    $dense=('\{}[]$";#'+" `t`r`n")*80
    Measure-SyCase '200 short commands' 10 { Invoke-SyScript $commands }
    Measure-SyCase '100 substitution commands' 10 { Invoke-SyScript $substitutions }
    Measure-SyCase 'encode many specials' 10 { ConvertTo-SyList @($dense) }
} finally {
    Set-Location -LiteralPath $original.ProviderPath
    # Delete only the known generated file and its unique, empty directory.
    if ([IO.Directory]::Exists($temp)) {
        [IO.File]::Delete((Join-Path $temp 'data.txt'))
        [IO.Directory]::Delete($temp)
    }
}
