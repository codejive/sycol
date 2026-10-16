$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$engine=(Get-Process -Id $PID).Path
$temp=Join-Path ([IO.Path]::GetTempPath()) ('sycol-discovery-'+[Guid]::NewGuid().ToString('N'))
$original=Get-Location
function Write-TestFile([string]$Relative, [string]$Text) {
    [IO.File]::WriteAllText((Join-Path $temp $Relative), $Text, (New-Object Text.UTF8Encoding($false)))
}
try {
    [void][IO.Directory]::CreateDirectory("$temp/lib/native/nested")
    [void][IO.Directory]::CreateDirectory("$temp/lib/sdk/nested")
    Copy-Item -LiteralPath "$root/sycol.ps1" -Destination "$temp/sycol.ps1"
    Copy-Item -LiteralPath "$root/lib/native/core.ps1" -Destination "$temp/lib/native/builtins.ps1"
    Copy-Item -Path "$root/lib/sdk/*.tcl" -Destination "$temp/lib/sdk"
    Copy-Item -LiteralPath "$root/tests/discovery.tcl" -Destination "$temp/test.tcl"
    Write-TestFile empty.tcl ''
    Write-TestFile lib/native/z-last.ps1 @'
Register-SyNative native.order { param([string[]]$Words); $script:Sy.R='last' }
Register-SyNative native.echo { param([string[]]$Words); ConvertTo-SyList $Words }
Register-SyNative getenv { param([string[]]$Words); $script:Sy.R='overridden' }
'@
    Write-TestFile lib/native/a-first.ps1 @'
Register-SyNative native.order { param([string[]]$Words); $script:Sy.R='first' }
'@
    Write-TestFile lib/sdk/z-last.tcl 'proc sdk.order {} { return last }'
    Write-TestFile lib/sdk/a-first.tcl 'proc sdk.order {} { return first }'
    foreach ($file in @('lib/native/.hidden.ps1','lib/native/ignored.PS1','lib/native/wrong.sh','lib/native/nested/ignored.ps1')) {
        Write-TestFile $file "throw 'ignored-file-was-loaded'"
    }
    foreach ($file in @('lib/sdk/.hidden.tcl','lib/sdk/ignored.TCL','lib/sdk/wrong.ps1','lib/sdk/nested/ignored.tcl')) {
        Write-TestFile $file 'error ignored-file-was-loaded'
    }
    # Embedding loads natives immediately, and SDK only when starting a script.
    Set-Location -LiteralPath $temp
    . ./sycol.ps1
    Invoke-SyCommand @('incr','n')
    if ($script:Sy.C -ne 1 -or $script:Sy.R -cne 'unknown command: incr') { throw 'SDK loaded during sourcing' }
    Register-SyNative native.order { param([string[]]$Words); $script:Sy.R='embedded' }
    Invoke-SyCommand @('native.order')
    if ($script:Sy.C -or $script:Sy.R -cne 'embedded') { throw 'embedding override failed' }
    Set-Location -LiteralPath $root
    $status=Start-Sycol @("$temp/empty.tcl")
    if ($status) { throw 'embedding startup after cwd change failed' }
    Set-Location -LiteralPath $temp
    & $engine -NoProfile -ExecutionPolicy Bypass -File ./sycol.ps1 test.tcl
    if ($LASTEXITCODE) { throw 'discovery failed' }
    Write-TestFile lib/sdk/0-broken.tcl 'error sdk-broken'
    # Capture native stderr without Windows PowerShell promoting it to a terminating error.
    $ErrorActionPreference='Continue'
    $output=& $engine -NoProfile -ExecutionPolicy Bypass -File ./sycol.ps1 "$root/examples/hello.tcl" 2>&1
    $status=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if (!$status -or "$output" -notlike '*0-broken.tcl: sdk-broken*' -or "$output" -like '*Hello, world!*') { throw 'SDK failure did not stop startup' }
    [IO.File]::Delete("$temp/lib/sdk/0-broken.tcl")
    Write-TestFile lib/native/0-broken.ps1 "throw 'native-broken'"
    $ErrorActionPreference='Continue'
    $output=& $engine -NoProfile -ExecutionPolicy Bypass -File ./sycol.ps1 empty.tcl 2>&1
    $status=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if (!$status -or "$output" -notlike '*cannot load native file:*0-broken.ps1*') { throw 'native failure did not stop startup' }
    [IO.File]::Delete("$temp/lib/native/0-broken.ps1")
    foreach ($file in [IO.Directory]::GetFiles("$temp/lib/sdk")) { [IO.File]::Delete($file) }
    & $engine -NoProfile -ExecutionPolicy Bypass -File ./sycol.ps1 empty.tcl
    if ($LASTEXITCODE) { throw 'empty SDK discovery failed' }
    foreach ($file in [IO.Directory]::GetFiles("$temp/lib/native")) { [IO.File]::Delete($file) }
    Write-TestFile empty-native.ps1 '. "$PSScriptRoot/sycol.ps1"'
    & $engine -NoProfile -ExecutionPolicy Bypass -File ./empty-native.ps1
    if ($LASTEXITCODE) { throw 'empty native discovery failed' }
    $missingFailed=$false
    try { Get-SyLibraryFiles "$temp/missing" '.tcl' } catch { $missingFailed=$true }
    if (!$missingFailed) { throw 'missing library directory was accepted' }
    Write-Output 'library lifecycle tests passed'
} finally {
    Set-Location -LiteralPath $original.ProviderPath
    # Delete only files in the known generated directories, then those empty directories.
    foreach ($directory in @("$temp/lib/native/nested","$temp/lib/sdk/nested","$temp/lib/native","$temp/lib/sdk","$temp/lib",$temp)) {
        if ([IO.Directory]::Exists($directory)) {
            foreach ($file in [IO.Directory]::GetFiles($directory)) { [IO.File]::Delete($file) }
            [IO.Directory]::Delete($directory)
        }
    }
}
