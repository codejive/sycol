# Test-only embedding launcher. Preserve normal Start-Sycol initialization.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/timing.ps1"
$timingWatch=[Diagnostics.Stopwatch]::StartNew()
. "$PSScriptRoot/../.sycol/bin/sycol.ps1"
Write-SyTiming phase "$($args[0])/native-load" ([string]$timingWatch.ElapsedMilliseconds)
$script:TimingScript=$args[0]
$script:TimingSource=$script:Sy.Native['source']
Register-SyNative source {
    param([string[]]$Words)
    if ($Words.Count -eq 1 -and ($Words[0].StartsWith("$script:SyHome/../sdk/",[StringComparison]::Ordinal) -or $Words[0].StartsWith("$script:SyHome/../sdk\",[StringComparison]::Ordinal))) {
        Measure-SyTiming phase "$script:TimingScript/sdk/$([IO.Path]::GetFileName($Words[0]))" { & $script:TimingSource $Words }
    } else { & $script:TimingSource $Words }
}
Register-SyNative test.time {
    param([string[]]$Words)
    if ($Words.Count -ne 2) { Set-SyArity 'test.time name script'; return }
    Measure-SyTiming test $Words[0] { Invoke-SyScript $Words[1] }
}
exit (Start-Sycol ([string[]]$args))
