# Run once per host: powershell/pwsh -NoProfile -File tests/run.ps1
param([switch]$Timed)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$engine=(Get-Process -Id $PID).Path
. "$PSScriptRoot/timing.ps1"
if (!$Timed) {
    $timingLocation=Get-Location
    $timingPreviousFile=$env:SYCOL_TIMING_FILE
    try {
        Set-Location -LiteralPath $root
        & $engine -NoProfile -ExecutionPolicy Bypass -File tests/timing-check.ps1
        if ($LASTEXITCODE) { throw 'Timing reporting suite failed' }
        Initialize-SyTiming
        $timingWatch=[Diagnostics.Stopwatch]::StartNew()
        & $engine -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1 -Timed
        $timingStatus=$LASTEXITCODE
        Write-SyTiming suite total ([string]$timingWatch.ElapsedMilliseconds)
        Write-SyTiming status exit ([string]$timingStatus)
        Show-SyTiming
    } finally {
        $env:SYCOL_TIMING_FILE=$timingPreviousFile
        Set-Location -LiteralPath $timingLocation.ProviderPath
    }
    exit $timingStatus
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('sycol-tests-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
[void][IO.Directory]::CreateDirectory("$temp/filesystem/source/nested")
[void][IO.Directory]::CreateDirectory("$temp/filesystem/empty")
[IO.File]::WriteAllText("$temp/filesystem/source/a ; [literal].txt",'payload')
[IO.File]::WriteAllText("$temp/filesystem/source/.hidden",'hidden')
[IO.File]::SetLastWriteTimeUtc("$temp/filesystem/source/.hidden",[DateTime]::new(2020,1,2,3,4,5,[DateTimeKind]::Utc))
[IO.File]::WriteAllText("$temp/filesystem/source/nested/child",'child')
foreach ($name in @('readonly-target','readonly-file')) {
    [IO.File]::WriteAllText("$temp/filesystem/$name",'old')
    [IO.File]::SetAttributes("$temp/filesystem/$name",[IO.FileAttributes]::ReadOnly)
}
$links=0
try {
    $null=New-Item -ItemType SymbolicLink -Path "$temp/filesystem/link" -Target "$temp/filesystem/source" -ErrorAction Stop
    $null=New-Item -ItemType SymbolicLink -Path "$temp/filesystem/dangling" -Target "$temp/filesystem/missing" -ErrorAction Stop
    $null=New-Item -ItemType SymbolicLink -Path "$temp/filesystem/file-link" -Target "$temp/filesystem/source/.hidden" -ErrorAction Stop
    $links=1
} catch { Write-Output 'Symbolic link tests unavailable: host does not permit link creation' }
Write-SyTiming meta symbolic-links ([string]$links)
$original=Get-Location
$cross=Join-Path $root ('.test-tmp/sycol-cross-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($cross)
try {
    Set-Location -LiteralPath $root
    $engine=(Get-Process -Id $PID).Path
    Measure-SyTiming group shared { & $engine -NoProfile -ExecutionPolicy Bypass -File tests/timed.ps1 tests/all.tcl $temp 'argument with spaces; $literal [brackets]' $links; if ($LASTEXITCODE) { throw 'Shared Tcl suite failed' } }
    if ([IO.File]::GetLastWriteTimeUtc("$temp/filesystem/source/.hidden") -ne [IO.File]::GetLastWriteTimeUtc("$temp/filesystem/attributes-copy")) { throw 'Copy did not preserve modification time' }
    if ([IO.Directory]::GetLastWriteTimeUtc("$temp/filesystem/source") -ne [IO.Directory]::GetLastWriteTimeUtc("$temp/filesystem/attributes-dir")) { throw 'Copy did not preserve directory modification time' }
    if ([IO.Path]::GetPathRoot($temp) -ne [IO.Path]::GetPathRoot($cross)) { Write-Output 'Testing rename across Windows volumes' }
    else { Write-Output 'Cross-filesystem rename coverage depends on the fixture roots being on separate mounts' }
    Measure-SyTiming group files-move { & $engine -NoProfile -ExecutionPolicy Bypass -File tests/timed.ps1 tests/files-move.tcl $temp $cross; if ($LASTEXITCODE) { throw 'Filesystem move suite failed' } }
    . ./.sycol/bin/sycol.ps1
    Register-SyNative host.echo {
        param([string[]]$Words)
        if ($Words.Count -ne 1) { Set-SyArity 'host.echo value'; return }
        $script:Sy.R=$Words[0]; $script:Sy.C=0
    }
    Measure-SyTiming group native { Invoke-SyCommand @('source','./tests/native.tcl') }
    if ($script:Sy.C) { throw $script:Sy.R }
    ConvertTo-SyList @($engine,'-NoProfile','-ExecutionPolicy','Bypass','-File',"$root/tests/fixtures/probe.ps1")
    $probe=$script:Sy.R
    Measure-SyTiming group exec { & $engine -NoProfile -ExecutionPolicy Bypass -File tests/timed.ps1 tests/exec.tcl $probe $temp; if ($LASTEXITCODE) { throw 'Process suite failed' } }
    Measure-SyTiming group discovery { & $engine -NoProfile -ExecutionPolicy Bypass -File tests/discovery.ps1; if ($LASTEXITCODE) { throw 'Discovery suite failed' } }
    Measure-SyTiming group encoding { & $engine -NoProfile -ExecutionPolicy Bypass -File tests/encoding.ps1; if ($LASTEXITCODE) { throw 'Encoding suite failed' } }
    Measure-SyTiming group launchers { & $engine -NoProfile -ExecutionPolicy Bypass -File tests/launchers.ps1; if ($LASTEXITCODE) { throw 'Launcher suite failed' } }
} finally {
    Set-Location -LiteralPath $original.ProviderPath
    # Only the known generated file and this empty, unique directory are removed.
    [IO.File]::Delete((Join-Path $temp 'round trip.txt'))
    # This is the fixed fixture subtree of the unique test directory. Use the
    # link-aware helper so cleanup never descends through symbolic links.
    . "$root/.sycol/bin/sycol.ps1"
    Import-SyNative files.ps1
    Remove-SyFile "$temp/filesystem" $true $true
    if ([IO.Directory]::Exists("$temp/move-source")) { Remove-SyFile "$temp/move-source" $true $true }
    # A unique fixture under the explicit workspace .test-tmp directory.
    $crossResolved=[IO.Path]::GetFullPath($cross)
    $crossParent=[IO.Path]::GetFullPath((Join-Path $root '.test-tmp'))+[IO.Path]::DirectorySeparatorChar
    if (!$crossResolved.StartsWith($crossParent,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected cross-volume fixture path' }
    Remove-SyFile $crossResolved $true $true
    [IO.Directory]::Delete($temp)
}
