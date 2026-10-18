# Test-only timing support. Same integer-millisecond TSV format as timing.sh.
function Resolve-SyTimingPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path $root $Path
}
function Write-SyTiming([string]$Kind,[string]$Name,[string]$Value) {
    if (($Name+$Value).IndexOfAny([char[]]"`t`r`n") -ge 0) { throw 'Timing values cannot contain tabs or newlines' }
    [IO.File]::AppendAllText($env:SYCOL_TIMING_FILE, "$Kind`t$Name`t$Value`n", (New-Object Text.UTF8Encoding($false)))
}
function Measure-SyTiming([string]$Kind,[string]$Name,[scriptblock]$Action) {
    $timingWatch=[Diagnostics.Stopwatch]::StartNew()
    try { & $Action } finally { Write-SyTiming $Kind $Name ([string]$timingWatch.ElapsedMilliseconds) }
}
function Read-SyTiming([string]$Path) {
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $parts=$line.Split("`t")
        if ($parts.Count -ne 3) { throw 'Invalid timing row' }
        [pscustomobject]@{Kind=$parts[0]; Name=$parts[1]; Value=$parts[2]}
    }
}
function Get-SyTimingOptions {
    $script:TimingAbsolute=100L; $script:TimingRelative=25L
    if ($env:SYCOL_TIMING_REGRESSION_MS) { $script:TimingAbsolute=Convert-SyTimingNumber $env:SYCOL_TIMING_REGRESSION_MS }
    if ($env:SYCOL_TIMING_REGRESSION_PERCENT) { $script:TimingRelative=Convert-SyTimingNumber $env:SYCOL_TIMING_REGRESSION_PERCENT }
    $script:TimingExpected=New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    if ($env:SYCOL_TIMING_EXPECTED) {
        foreach ($line in [IO.File]::ReadAllLines((Resolve-SyTimingPath $env:SYCOL_TIMING_EXPECTED))) {
            if (!$line -or $line.StartsWith('#')) { continue }
            $parts=$line.Split("`t")
            if ($parts.Count -ne 2) { throw 'Invalid expected timing row (use key TAB integer milliseconds)' }
            $script:TimingExpected[$parts[0]]=Convert-SyTimingNumber $parts[1]
        }
    }
    if ($env:SYCOL_TIMING_BASELINE -and !(Test-Path -LiteralPath (Resolve-SyTimingPath $env:SYCOL_TIMING_BASELINE) -PathType Leaf)) { throw 'Cannot read timing baseline' }
}
function Convert-SyTimingNumber([string]$Value) {
    if ($Value -cnotmatch '^[0-9]{1,9}$') { throw 'Timing values must be nonnegative integers of at most nine digits' }
    return [long]$Value
}
function Initialize-SyTiming {
    Get-SyTimingOptions
    [void][IO.Directory]::CreateDirectory("$root/.test-tmp")
    $env:SYCOL_TIMING_FILE=Join-Path $root ('.test-tmp/timings-'+[Guid]::NewGuid().ToString('N'))
    Write-SyTiming meta format sycol-timing-v1
    Write-SyTiming meta host powershell
    Write-SyTiming meta runtime "$($PSVersionTable.PSVersion) $($PSVersionTable.PSEdition) $($PSVersionTable.CLRVersion)"
    Write-SyTiming meta executable $engine
    Write-SyTiming meta machine ([Environment]::MachineName)
    Write-SyTiming meta os ([Environment]::OSVersion.VersionString)
    Write-SyTiming meta architecture "$env:PROCESSOR_ARCHITECTURE; pointer-bytes=$([IntPtr]::Size)"
    Write-SyTiming meta locale ([Globalization.CultureInfo]::CurrentCulture.Name)
    Write-SyTiming meta clock stopwatch-ms
    Measure-SyTiming phase startup {
        & $engine -NoProfile -ExecutionPolicy Bypass -File .sycol/bin/sycol.ps1 tests/fixtures/startup.tcl
        if ($LASTEXITCODE) { throw 'Startup timing probe failed' }
    }
}
function Show-SyTiming {
    Get-SyTimingOptions
    $rows=@(Read-SyTiming $env:SYCOL_TIMING_FILE)
    $baseline=New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $baselineStatus='not configured'
    if ($env:SYCOL_TIMING_BASELINE) {
        $old=@(Read-SyTiming (Resolve-SyTimingPath $env:SYCOL_TIMING_BASELINE))
        $metadata=($rows | Where-Object Kind -eq meta | ForEach-Object { $_.Name+"`t"+$_.Value }) -join "`n"
        $oldMetadata=($old | Where-Object Kind -eq meta | ForEach-Object { $_.Name+"`t"+$_.Value }) -join "`n"
        if ($metadata -ceq $oldMetadata) {
            $baselineStatus='matched environment'
            foreach ($row in $old) {
                if ($row.Kind -ne 'meta') { $baseline[$row.Kind+'/'+$row.Name]=Convert-SyTimingNumber $row.Value }
            }
        } else { $baselineStatus='environment mismatch; comparison skipped' }
    }
    $tests=@($rows | Where-Object Kind -eq test)
    $total=($rows | Where-Object Kind -eq suite | Select-Object -Last 1).Value
    Write-Output "`nTiming: $total ms total; $($tests.Count) named tests"
    Write-Output 'Startup/module loading and suite groups (ms):'
    foreach ($row in $rows) { if ($row.Kind -in @('phase','group')) { Write-Output ('  {0,8}  {1}/{2}' -f $row.Value,$row.Kind,$row.Name) } }
    Write-Output 'Slowest named tests (ms):'
    foreach ($row in @($tests | Sort-Object @{Expression={[long]$_.Value};Descending=$true},Name | Select-Object -First 10)) {
        Write-Output ('  {0,8}  {1}' -f $row.Value,$row.Name)
    }
    Write-Output "Baseline: $baselineStatus"
    foreach ($row in $rows) {
        if ($row.Kind -notin @('test','phase','group','suite')) { continue }
        $key=$row.Kind+'/'+$row.Name; $value=Convert-SyTimingNumber $row.Value
        if ($script:TimingExpected.ContainsKey($key) -and $value -gt $script:TimingExpected[$key]) {
            Write-Output "TIMING warning: $key $value ms exceeds expected $($script:TimingExpected[$key]) ms"
        }
        if ($baseline.ContainsKey($key)) {
            $previous=$baseline[$key]; $delta=$value-$previous
            if ($previous -gt 0 -and $delta -gt $script:TimingAbsolute -and $delta*100 -gt $previous*$script:TimingRelative) {
                $percent=[Math]::Floor($delta*1000/[double]$previous)/10
                Write-Output ([string]::Format([Globalization.CultureInfo]::InvariantCulture,'TIMING warning: {0} +{1} ms (+{2:F1}%)',$key,$delta,$percent))
            }
        }
    }
    $output=$env:SYCOL_TIMING_OUTPUT
    if (!$output) { $output=Join-Path $root '.test-tmp/timings-powershell.tsv' }
    $output=Resolve-SyTimingPath $output
    [IO.File]::Copy($env:SYCOL_TIMING_FILE,$output,$true)
    [IO.File]::Delete($env:SYCOL_TIMING_FILE)
    Write-Output "Timing results: $output"
}
