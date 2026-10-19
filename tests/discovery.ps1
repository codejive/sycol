$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$engine=(Get-Process -Id $PID).Path
$temp=Join-Path ([IO.Path]::GetTempPath()) ('sycol-modules-'+[Guid]::NewGuid().ToString('N'))
$original=Get-Location
function Write-TestFile([string]$Relative,[string]$Text) {
    [IO.File]::WriteAllText((Join-Path $temp $Relative),$Text,(New-Object Text.UTF8Encoding($false)))
}
try {
    foreach ($directory in @('.sycol/bin','.sycol/lib/sub','.sycol/lib-sibling','.sycol/native/sub','user','extra-sdk','extra-native')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $temp $directory))
    }
    [void][IO.Directory]::CreateDirectory("$temp/.sycol/lib/directory.tcl")
    Write-TestFile user/directory.tcl 'proc wrong.directory.fallback {} {}'
    Copy-Item -LiteralPath "$root/.sycol/bin/sycol.ps1" -Destination "$temp/.sycol/bin/"
    Copy-Item -LiteralPath "$root/.sycol/VERSION" -Destination "$temp/.sycol/"
    Copy-Item -Path "$root/.sycol/native/*.ps1" -Destination "$temp/.sycol/native/"
    Copy-Item -Path "$root/.sycol/lib/*.tcl" -Destination "$temp/.sycol/lib/"
    Copy-Item -LiteralPath "$root/tests/discovery.tcl" -Destination "$temp/test.tcl"
    [IO.File]::AppendAllText("$temp/.sycol/lib/core.tcl",'proc fileless.path {name} { return "[pwd]/$name" }')
    Write-TestFile '.sycol/lib/sample.tcl' @'
incr ::tcl_loads
proc replacement {} { return fallback }

'@
    Write-TestFile '.sycol/lib/pure.tcl' @'
proc portable {} { return portable }

'@
    Write-TestFile '.sycol/lib/sub/nested.tcl' @'
proc nested.native {} { return fallback }

'@
    Write-TestFile '.sycol/lib/space name.tcl' @'
proc space.native {} { return fallback }

'@
    Write-TestFile '.sycol/lib/broken.tcl' @'
error first-broken

'@
    Write-TestFile '.sycol/lib/bad-native.tcl' @'
proc should.not.exist {} {}

'@
    Write-TestFile '.sycol/lib/rogue.tcl' @'
error unrelated-sdk-was-loaded

'@
    Write-TestFile 'user/files.tcl' @'
proc user.files {} { return user }

'@
    Write-TestFile 'user/sample.tcl' @'
proc user.sample {} { return user }

'@
    Write-TestFile 'user/library.tcl' @'
proc library {} { return user }

'@
    Write-TestFile 'user/extra.tcl' @'
proc precedence {} { return user }

'@
    Write-TestFile 'user/broken.tcl' @'
error wrong-fallback

'@
    Write-TestFile 'extra-sdk/extra.tcl' @'
proc precedence {} { return sdk }

'@
    Write-TestFile 'cwd-only.tcl' @'
proc cwd.only {} { return cwd }

'@
    Write-TestFile 'scope.tcl' @'
set marker after

'@
    Write-TestFile 'return.tcl' @'
return returned
error unreachable

'@
    Write-TestFile 'empty.tcl' @'

'@
    Write-TestFile .sycol/native/sample.ps1 @'
$script:ModuleLoads++
Register-SyNative replacement { param([string[]]$Words); $script:Sy.R='native' }
Register-SyNative native.loads { param([string[]]$Words); $script:Sy.R=[string]$script:ModuleLoads }
'@
    Write-TestFile .sycol/native/sub/nested.ps1 "Register-SyNative nested.native { param([string[]]`$Words); `$script:Sy.R='nested' }"
    Write-TestFile '.sycol/native/space name.ps1' "Register-SyNative space.native { param([string[]]`$Words); `$script:Sy.R='space' }"
    Write-TestFile .sycol/native/bad-native.ps1 @'
$script:FailedLoads++
Register-SyNative native.failed-loads { param([string[]]$Words); $script:Sy.R=[string]$script:FailedLoads }
throw 'bad-native'
'@
    Write-TestFile extra-sdk/secondary.tcl 'proc secondary.native {} { return fallback }'
    Write-TestFile extra-native/secondary.ps1 "Register-SyNative secondary.native { param([string[]]`$Words); `$script:Sy.R='secondary' }"
    Write-TestFile extra-native/bad-native.ps1 '# Must not be tried after the first backend fails.'
    Write-TestFile .sycol/lib-sibling/outsider.tcl 'proc outsider {} {}'
    Write-TestFile .sycol/native/outsider.ps1 "Register-SyNative outsider.native { param([string[]]`$Words); `$script:Sy.R='wrong' }"
    Write-TestFile .sycol/native/unrelated.ps1 "throw 'unrelated-native-was-loaded'"
    Set-Location -LiteralPath $temp
    & $engine -NoProfile -ExecutionPolicy Bypass -File .sycol/bin/sycol.ps1 test.tcl
    if ($LASTEXITCODE) { throw 'module conformance failed' }
    . ./.sycol/bin/sycol.ps1
    Invoke-SyCommand @('incr','n')
    if ($script:Sy.C -ne 1) { throw 'SDK loaded during embedding' }
    $script:Sy.C=0
    Set-Location -LiteralPath $root
    if (Start-Sycol @("$temp/empty.tcl")) { throw 'embedded cwd independence failed' }
    foreach ($directory in @('override sdk','override native')) { [void][IO.Directory]::CreateDirectory("$temp/$directory") }
    Copy-Item -LiteralPath "$temp/.sycol/lib/core.tcl" -Destination "$temp/override sdk/"
    Copy-Item -LiteralPath "$temp/.sycol/native/core.ps1" -Destination "$temp/override native/"
    Write-TestFile user/env.tcl 'proc from.environment {} {return yes}'
    Write-TestFile env-main.tcl 'source env.tcl; puts [from.environment]'
    $oldSdk=$env:SYCOL_SDK_PATH; $oldNative=$env:SYCOL_NATIVE_PATH; $oldSource=$env:SYCOL_SOURCE_PATH
    try {
        $separator=[IO.Path]::PathSeparator
        $env:SYCOL_SDK_PATH="$temp/missing${separator}$temp/override sdk"
        $env:SYCOL_NATIVE_PATH="$temp/missing${separator}$temp/override native"
        $env:SYCOL_SOURCE_PATH="$temp/user"
        $output=& $engine -NoProfile -ExecutionPolicy Bypass -File .sycol/bin/sycol.ps1 "$temp/env-main.tcl"
        if ($LASTEXITCODE -or "$output" -cne 'yes') { throw 'environment paths failed' }
    } finally { $env:SYCOL_SDK_PATH=$oldSdk; $env:SYCOL_NATIVE_PATH=$oldNative; $env:SYCOL_SOURCE_PATH=$oldSource }
    Write-TestFile .sycol/lib/core.tcl 'error core-broken'
    $ErrorActionPreference='Continue'
    $output=& $engine -NoProfile -ExecutionPolicy Bypass -File "$temp/.sycol/bin/sycol.ps1" "$temp/empty.tcl" 2>&1
    $status=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if (!$status -or "$output" -notlike '*core-broken*') { throw 'broken core accepted' }
    [IO.File]::Delete("$temp/.sycol/lib/core.tcl")
    $ErrorActionPreference='Continue'
    $output=& $engine -NoProfile -ExecutionPolicy Bypass -File "$temp/.sycol/bin/sycol.ps1" "$temp/empty.tcl" 2>&1
    $status=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if (!$status -or "$output" -notlike '*cannot find SDK file: core.tcl*') { throw 'missing core accepted' }
    [IO.File]::Delete("$temp/.sycol/native/core.ps1")
    $ErrorActionPreference='Continue'
    $output=& $engine -NoProfile -ExecutionPolicy Bypass -File "$temp/.sycol/bin/sycol.ps1" "$temp/empty.tcl" 2>&1
    $status=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if (!$status -or "$output" -notlike '*cannot find native file: core.ps1*') { throw 'missing native core accepted' }
    Write-Output 'library lifecycle tests passed'
} finally {
    Set-Location -LiteralPath $original.ProviderPath
    # Verify the exact generated fixture root before recursive deletion.
    $expected=Join-Path ([IO.Path]::GetTempPath()) 'sycol-modules-'
    if (![IO.Path]::GetFullPath($temp).StartsWith($expected,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected fixture root' }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
