$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$engine=(Get-Process -Id $PID).Path
$temp=Join-Path ([IO.Path]::GetTempPath()) ('sycol-encoding-'+[Guid]::NewGuid().ToString('N'))
$original=Get-Location
try {
    [void][IO.Directory]::CreateDirectory($temp)
    Set-Location -LiteralPath $root
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $text=$utf8.GetString([byte[]](0xC2,0x80,0xDF,0xBF,0xE0,0xA0,0x80,0xED,0x9F,0xBF,0xEE,0x80,0x80,0xEF,0xBF,0xBF,0xF0,0x90,0x80,0x80,0xF4,0x8F,0xBF,0xBF))
    [IO.File]::WriteAllText("$temp/plain.tcl","return {$text}`r`n",$utf8)
    [IO.File]::WriteAllText("$temp/bom.tcl","return {$text}`r`n",(New-Object Text.UTF8Encoding($true,$true)))
    & $engine -NoProfile -ExecutionPolicy Bypass -File .sycol/bin/sycol.ps1 tests/encoding.tcl $temp $text
    if ($LASTEXITCODE) { throw 'UTF-8 file suite failed' }
} finally {
    Set-Location -LiteralPath $original.ProviderPath
    # Delete only generated files in this unique directory, then the empty directory.
    if ([IO.Directory]::Exists($temp)) {
        foreach ($file in [IO.Directory]::GetFiles($temp)) { [IO.File]::Delete($file) }
        [IO.Directory]::Delete($temp)
    }
}
