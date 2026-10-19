# Exercise the real CMD command line, independently of PowerShell native quoting.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('sycol launch & (test) '+[Guid]::NewGuid().ToString('N'))
$original=Get-Location
$oldPath=$env:PATH
$oldLiteral=$env:SYCOL_LAUNCH_LITERAL
$oldExpand=$env:SYCOL_LAUNCH_EXPAND
function Assert-Output([string]$Name, [string]$Output, [string]$ErrorText, [int]$Status, [string[]]$ExpectedArgs) {
    ConvertTo-SyList $ExpectedArgs
    $expected=([string]$ExpectedArgs.Count)+"`nargument probe.tcl`n"+$script:Sy.R+"`n"
    if ($Status -ne 0 -or $ErrorText -ne '' -or $Output.Replace("`r`n","`n") -cne $expected) {
        throw "$Name failed (exit $Status): stdout=<$Output> stderr=<$ErrorText> expected=<$expected>"
    }
}
function Invoke-CmdProbe([string]$Launcher, [string]$Tail, [string[]]$ExpectedArgs, [string]$Delayed='off') {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$env:ComSpec
    $start.UseShellExecute=$false
    $start.WorkingDirectory="$temp/work"
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $command=$Launcher
    if ($Launcher -ne 'sycol') { $command='"'+$Launcher+'"' }
    $start.Arguments='/d /v:'+$Delayed+' /s /c "'+$command+' "argument probe.tcl" '+$Tail+'"'
    $process=[Diagnostics.Process]::Start($start)
    $output=$process.StandardOutput.ReadToEnd()
    $errorText=$process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Assert-Output "$Launcher /v:$Delayed" $output $errorText $process.ExitCode $ExpectedArgs
    $process.Dispose()
}
function Assert-Release([string]$Launcher, [string[]]$Query, [int]$Status, [string]$Expected, [string]$ExpectedError='') {
    $literalArgs=($Query | ForEach-Object { "'"+$_.Replace("'","''")+"'" }) -join ','
    $runner='$probeArgs=@('+$literalArgs+"); & '"+$Launcher.Replace("'","''")+"' @probeArgs; exit `$LASTEXITCODE"
    [IO.File]::WriteAllText("$temp/runner.ps1",$runner)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=(Get-Process -Id $PID).Path
    $start.UseShellExecute=$false
    $start.WorkingDirectory="$temp/work"
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$temp+'/runner.ps1"'
    $process=[Diagnostics.Process]::Start($start)
    $output=$process.StandardOutput.ReadToEnd().Replace("`r`n","`n")
    $errorText=$process.StandardError.ReadToEnd().Replace("`r`n","`n")
    $process.WaitForExit()
    try {
        if ($process.ExitCode -ne $Status -or $output -cne $Expected -or $errorText -cne $ExpectedError) {
            throw "Release probe failed: $Launcher (exit $($process.ExitCode)): stdout=<$output> stderr=<$errorText>"
        }
    } finally { $process.Dispose() }
}
try {
    [void][IO.Directory]::CreateDirectory("$temp/.sycol/bin")
    [void][IO.Directory]::CreateDirectory("$temp/.sycol/native")
    [void][IO.Directory]::CreateDirectory("$temp/.sycol/lib")
    [void][IO.Directory]::CreateDirectory("$temp/work")
    Copy-Item -LiteralPath "$root/sycol.bat" -Destination "$temp/sycol.bat"
    Copy-Item -Path "$root/.sycol/bin/*" -Destination "$temp/.sycol/bin"
    Copy-Item -LiteralPath "$root/.sycol/VERSION" -Destination "$temp/.sycol/VERSION"
    Copy-Item -Path "$root/.sycol/native/*" -Destination "$temp/.sycol/native"
    Copy-Item -Path "$root/.sycol/lib/*" -Destination "$temp/.sycol/lib"
    Copy-Item -LiteralPath "$root/tests/fixtures/argv.tcl" -Destination "$temp/work/argument probe.tcl"
    . "$temp/.sycol/bin/sycol.ps1"
    Set-Location -LiteralPath "$temp/work"
    [string[]]$arguments=@('', 'two words', 'say "hello"', 'tail\', 'two words\', 'a&b|c<d>e(f)^g!h', '$literal;[brackets]', '100%')
    [string[]]$psArguments=@($arguments)+@('say "a&b"', '%SYCOL_LAUNCH_EXPAND%', "line one`nline two", '--version')
    # Direct PowerShell invocation bypasses the CMD parser, including on PATH.
    $psLaunchers=@("$temp/.sycol/bin/sycol.ps1", 'sycol.ps1')
    if ($env:OS -eq 'Windows_NT') { $psLaunchers+= 'sycol' }
    foreach ($launcher in $psLaunchers) {
        $env:PATH="$temp/.sycol/bin"+[IO.Path]::PathSeparator+$oldPath
        if ($launcher -eq 'sycol' -and (Get-Command sycol).Source -ne "$temp/.sycol/bin/sycol.ps1".Replace('/',[IO.Path]::DirectorySeparatorChar)) {
            throw 'PowerShell did not select sycol.ps1 from PATH'
        }
        $literalArgs=($psArguments | ForEach-Object { "'"+$_.Replace("'","''")+"'" }) -join ','
        $runner=' $probeArgs=@('+$literalArgs+"); & '"+$launcher.Replace("'","''")+"' 'argument probe.tcl' @probeArgs; exit `$LASTEXITCODE"
        [IO.File]::WriteAllText("$temp/runner.ps1",$runner)
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=(Get-Process -Id $PID).Path
        $start.UseShellExecute=$false
        $start.WorkingDirectory="$temp/work"
        $start.RedirectStandardOutput=$true
        $start.RedirectStandardError=$true
        $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$temp+'/runner.ps1"'
        $process=[Diagnostics.Process]::Start($start)
        $output=$process.StandardOutput.ReadToEnd()
        $errorText=$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        Assert-Output $launcher $output $errorText $process.ExitCode $psArguments
        $process.Dispose()
    }
    if ($env:OS -eq 'Windows_NT') {
        $env:SYCOL_LAUNCH_LITERAL='%SYCOL_LAUNCH_EXPAND%'
        $env:SYCOL_LAUNCH_EXPAND='must-not-expand-again'
        foreach ($launcher in @("$temp/sycol.bat", "$temp/.sycol/bin/sycol.bat", 'sycol')) {
            # Trailing backslashes must be doubled before the closing quote for Windows argv parsing.
            Invoke-CmdProbe $launcher '"" "two words" "say \"hello\"" "tail\\" "two words\\" "a&b|c<d>e(f)^g!h" "$literal;[brackets]" "100%"' $arguments
            Invoke-CmdProbe $launcher '"%SYCOL_LAUNCH_LITERAL%"' @('%SYCOL_LAUNCH_EXPAND%')
            Invoke-CmdProbe $launcher '"plain argument"' @('plain argument') 'on'
            # Usage and interpreter failures must survive both batch levels.
            foreach ($case in @(@('',2), @('"missing.tcl"',1))) {
                $start=New-Object Diagnostics.ProcessStartInfo
                $start.FileName=$env:ComSpec
                $start.UseShellExecute=$false
                $start.RedirectStandardError=$true
                $command=$launcher
                if ($launcher -ne 'sycol') { $command='"'+$launcher+'"' }
                $start.Arguments='/d /v:off /s /c "'+$command+' '+$case[0]+'"'
                $process=[Diagnostics.Process]::Start($start)
                $errorText=$process.StandardError.ReadToEnd()
                $process.WaitForExit()
                if ($process.ExitCode -ne $case[1] -or !$errorText) { throw 'Batch exit status/stderr propagation failed' }
                $process.Dispose()
            }
        }
    }
    # Changing one file updates both query interfaces in a relocated installation.
    [IO.File]::WriteAllText("$temp/.sycol/VERSION","9.8.7-test+build`r`n")
    [IO.File]::WriteAllText("$temp/work/version.tcl",'puts $::sycol_version')
    $releaseLaunchers=@("$temp/.sycol/bin/sycol.ps1")
    if ($env:OS -eq 'Windows_NT') { $releaseLaunchers+=@("$temp/sycol.bat","$temp/.sycol/bin/sycol.bat") }
    foreach ($launcher in $releaseLaunchers) {
        foreach ($case in @(@('exit',0), @('proc stop {} { exit 37 }; catch {stop}; error unreachable',37), @('exit 255',255))) {
            [IO.File]::WriteAllText("$temp/work/exit.tcl",$case[0])
            Assert-Release $launcher @('exit.tcl') $case[1] ''
        }
        Assert-Release $launcher @('--version') 0 "9.8.7-test+build`n"
        Assert-Release $launcher @('version.tcl') 0 "9.8.7-test+build`n"
        Assert-Release $launcher @('--version','extra') 2 '' "usage: sycol script.tcl [args ...] | sycol --version`n"
    }
    [IO.File]::WriteAllText("$temp/.sycol/lib/core.tcl",'error version-must-not-load-sdk')
    Assert-Release $releaseLaunchers[0] @('--version') 0 "9.8.7-test+build`n"
    foreach ($value in @('', 'invalid version')) {
        [IO.File]::WriteAllText("$temp/.sycol/VERSION",$value)
        Assert-Release $releaseLaunchers[0] @('--version') 1 '' "sycol: invalid version file (completion 1)`n"
    }
    [IO.File]::Delete("$temp/.sycol/VERSION")
    Assert-Release $releaseLaunchers[0] @('--version') 1 '' "sycol: cannot read version file (completion 1)`n"
    Write-Output 'launcher argument, version, and exit status tests passed'
} finally {
    Set-Location -LiteralPath $original.ProviderPath
    $env:PATH=$oldPath
    $env:SYCOL_LAUNCH_LITERAL=$oldLiteral
    $env:SYCOL_LAUNCH_EXPAND=$oldExpand
    foreach ($directory in @("$temp/.sycol/bin","$temp/.sycol/native","$temp/.sycol/lib","$temp/.sycol","$temp/work",$temp)) {
        if ([IO.Directory]::Exists($directory)) {
            foreach ($file in [IO.Directory]::GetFiles($directory)) { [IO.File]::Delete($file) }
            [IO.Directory]::Delete($directory)
        }
    }
}
