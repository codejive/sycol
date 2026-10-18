$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot/timing.ps1"
$work=Join-Path $root ('.test-tmp/timing-check-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
try {
    $env:SYCOL_TIMING_FILE="$work/current"
    $env:SYCOL_TIMING_BASELINE="$work/baseline"
    $env:SYCOL_TIMING_EXPECTED="$work/expected"
    $env:SYCOL_TIMING_OUTPUT="$work/output"
    $env:SYCOL_TIMING_REGRESSION_MS='50'; $env:SYCOL_TIMING_REGRESSION_PERCENT='25'
    [IO.File]::Copy("$PSScriptRoot/fixtures/timings-current.tsv",$env:SYCOL_TIMING_FILE)
    [IO.File]::Copy("$PSScriptRoot/fixtures/timings-baseline.tsv",$env:SYCOL_TIMING_BASELINE)
    [IO.File]::WriteAllText($env:SYCOL_TIMING_EXPECTED,"# Expected durations`r`n`r`ntest/slow`t150`r`ntest/tiny`t8`r`n")
    # All configured paths resolve from the repository, even when launched elsewhere.
    $relative='.test-tmp/'+[IO.Path]::GetFileName($work)
    $env:SYCOL_TIMING_EXPECTED="$relative/expected"
    $env:SYCOL_TIMING_BASELINE="$relative/baseline"
    $env:SYCOL_TIMING_OUTPUT="$relative/output"
    $report=(Show-SyTiming) -join "`n"
    foreach ($expected in @('1500 ms total; 6 named tests','1100  absolute','matched environment','test/slow +100 ms (+100.0%)','test/slow 200 ms exceeds expected 150 ms','test/tiny 11 ms exceeds expected 8 ms')) {
        if (!$report.Contains($expected)) { throw "Missing timing output: $expected" }
    }
    foreach ($unexpected in @('test/tiny +','test/absolute +','test/relative +','test/zero +','test/equal +')) {
        if ($report.Contains($unexpected)) { throw "Unexpected timing output: $unexpected" }
    }
    if ([IO.File]::ReadAllText("$work/output") -cne [IO.File]::ReadAllText("$PSScriptRoot/fixtures/timings-current.tsv")) { throw 'Timing output changed records' }
    [IO.File]::Copy("$PSScriptRoot/fixtures/timings-current.tsv",$env:SYCOL_TIMING_FILE)
    [IO.File]::AppendAllText("$work/baseline","meta`tmachine`tother`n")
    $report=(Show-SyTiming) -join "`n"
    if (!$report.Contains('environment mismatch; comparison skipped') -or $report.Contains('test/slow +') -or !$report.Contains('exceeds expected')) { throw 'Mismatched baseline was compared' }
    $caught=$false
    try { Measure-SyTiming test failure { throw 'expected failure' } } catch { $caught=$_.Exception.Message -eq 'expected failure' }
    $row=Read-SyTiming $env:SYCOL_TIMING_FILE
    if (!$caught -or $row.Kind -ne 'test' -or $row.Name -ne 'failure') { throw 'Failed measurement was not preserved' }
    $env:SYCOL_TIMING_REGRESSION_MS='invalid'; $caught=$false
    try { Get-SyTimingOptions } catch { $caught=$true }
    if (!$caught) { throw 'Invalid threshold accepted' }
    Write-Output 'timing reporting tests passed'
} finally {
    foreach ($name in @('current','baseline','output','expected')) { [IO.File]::Delete("$work/$name") }
    [IO.Directory]::Delete($work)
}
