# sycol: PowerShell 5.1+ implementation of the string-only Tcl subset.
# Dot-source to embed; native commands set Sy.R / Sy.C and emit no pipeline data.
$script:Sy = @{ R=''; C=0; RC=0; RL=0; F=0; NF=0; Depth=0;
    Vars=@{}; Procs=@{}; Parent=@{0=0}; Native=@{} }
$script:SyHome = $PSScriptRoot
# Tcl names are case-sensitive, unlike ordinary PowerShell hashtables.
foreach ($table in @('Vars','Procs','Native','Aliases')) {
    $script:Sy[$table]=New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
}

function Set-SyError([string]$Message) { $script:Sy.R=$Message; $script:Sy.C=1 }
function Set-SyArity([string]$Usage) { Set-SyError "wrong # args: $Usage" }
function Convert-SyInteger([string]$Text) {
    [long]$number=0
    if ($Text -cnotmatch '^[+-]?[0-9]+$') { Set-SyError "expected integer: $Text"; return }
    if (![long]::TryParse($Text, [ref]$number) -or $number -lt -2147483648 -or $number -gt 2147483647) {
        Set-SyError 'integer overflow'; return
    }
    $script:Sy.R=$number.ToString([Globalization.CultureInfo]::InvariantCulture)
}
function Convert-SyTruth([string]$Text) {
    if ($Text -ceq 'true') { $script:Sy.R='1' }
    elseif ($Text -ceq 'false') { $script:Sy.R='0' }
    else { Convert-SyInteger $Text; if (!$script:Sy.C) { $script:Sy.R=[string][int]([long]$script:Sy.R -ne 0) } }
}
function Get-SyKey([string]$Name) {
    $frame=$script:Sy.F
    if ($Name.StartsWith('::')) { $frame=0; $Name=$Name.Substring(2) }
    if (!$Name.Length) { Set-SyError 'empty variable name'; return '' }
    if ($script:Sy.Aliases.ContainsKey("${frame}:$Name")) { $frame=0 }
    return "${frame}:$Name"
}
function Get-SyVariable([string]$Name) {
    $key=Get-SyKey $Name; if ($script:Sy.C) { return }
    if ($script:Sy.Vars.ContainsKey($key)) { $script:Sy.R=$script:Sy.Vars[$key] }
    else { Set-SyError "no such variable: $Name" }
}
function Set-SyVariable([string]$Name, [string]$Value) {
    $key=Get-SyKey $Name; if ($script:Sy.C) { return }
    $script:Sy.Vars[$key]=$Value; $script:Sy.R=$Value
}
function ConvertTo-SyList([string[]]$Words) {
    $parts=New-Object 'System.Collections.Generic.List[string]'
    foreach ($word in $Words) {
        if (!$word.Length) { $parts.Add('{}'); continue }
        $b=New-Object Text.StringBuilder
        foreach ($ch in $word.ToCharArray()) {
            switch -CaseSensitive ([string]$ch) {
                "`n" { [void]$b.Append('\n') }
                "`r" { [void]$b.Append('\r') }
                "`t" { [void]$b.Append('\t') }
                default {
                    if (' \{}[]$";#'.Contains([string]$ch)) { [void]$b.Append('\') }
                    [void]$b.Append($ch)
                }
            }
        }
        $parts.Add($b.ToString())
    }
    $script:Sy.R=[string]::Join(' ', $parts.ToArray())
}
function Read-SyEscape($Parser) {
    $Parser.I++
    if ($Parser.I -ge $Parser.S.Length) { Set-SyError 'trailing backslash'; return }
    $ch=[string]$Parser.S[$Parser.I]; $Parser.I++
    switch -CaseSensitive ($ch) {
        n { $script:Sy.R="`n" }; r { $script:Sy.R="`r" }; t { $script:Sy.R="`t" }
        "`n" {
            while ($Parser.I -lt $Parser.S.Length -and " `t".Contains([string]$Parser.S[$Parser.I])) { $Parser.I++ }
            $script:Sy.R=' '
        }
        default { $script:Sy.R=$ch }
    }
}
function Read-SySubstitution($Parser) {
    $ch=[string]$Parser.S[$Parser.I]
    switch -CaseSensitive ($ch) {
        '\' { Read-SyEscape $Parser }
        '$' {
            $Parser.I++; $start=$Parser.I
            if ($Parser.I -lt $Parser.S.Length -and $Parser.S[$Parser.I] -ceq '{') {
                $Parser.I++; $start=$Parser.I
                while ($Parser.I -lt $Parser.S.Length -and $Parser.S[$Parser.I] -cne '}') { $Parser.I++ }
                if ($Parser.I -eq $Parser.S.Length) { Set-SyError 'missing variable close brace'; return }
                $name=$Parser.S.Substring($start,$Parser.I-$start); $Parser.I++
            } else {
                while ($Parser.I -lt $Parser.S.Length -and [string]$Parser.S[$Parser.I] -cmatch '^[a-zA-Z0-9_:]$') { $Parser.I++ }
                $name=$Parser.S.Substring($start,$Parser.I-$start)
                if (!$name.Length) { $script:Sy.R='$'; return }
            }
            Get-SyVariable $name
        }
        '[' {
            $nested=@{S=$Parser.S; I=$Parser.I+1; B=$true; M=$false}
            Invoke-SyParser $nested; $Parser.I=$nested.I
        }
        default { $script:Sy.R=$ch; $Parser.I++ }
    }
}
function Read-SyWord($Parser) {
    $b=New-Object Text.StringBuilder; $mode='bare'; $depth=0
    if ($Parser.S[$Parser.I] -ceq '{') { $mode='brace'; $depth=1; $Parser.I++ }
    elseif ($Parser.S[$Parser.I] -ceq '"') { $mode='quote'; $Parser.I++ }
    while ($Parser.I -lt $Parser.S.Length) {
        $ch=[string]$Parser.S[$Parser.I]
        if ($mode -eq 'brace') {
            $Parser.I++
            if ($ch -ceq '{') { $depth++ }
            elseif ($ch -ceq '}') { $depth--; if (!$depth) { break } }
            elseif ($ch -ceq '\' -and $Parser.I -lt $Parser.S.Length) {
                if ($Parser.S[$Parser.I] -ceq "`n") {
                    $Parser.I--; Read-SyEscape $Parser; [void]$b.Append($script:Sy.R); continue
                }
                [void]$b.Append($ch); [void]$b.Append($Parser.S[$Parser.I]); $Parser.I++; continue
            }
            [void]$b.Append($ch); continue
        }
        if ($mode -eq 'quote' -and $ch -ceq '"') { $Parser.I++; $mode='closed'; break }
        if ($mode -eq 'bare') {
            if (" `t`r`n".Contains($ch)) { break }
            if ($ch -ceq '\' -and $Parser.I+1 -lt $Parser.S.Length -and $Parser.S[$Parser.I+1] -ceq "`n") { break }
            if (!$Parser.M -and ($ch -ceq ';' -or ($Parser.B -and $ch -ceq ']'))) { break }
        }
        if ($Parser.M -and $ch -cne '\') { $script:Sy.R=$ch; $Parser.I++ }
        else { Read-SySubstitution $Parser }
        if ($script:Sy.C) { return }; [void]$b.Append($script:Sy.R)
    }
    if ($mode -eq 'brace' -and $depth) { Set-SyError 'missing close brace'; return }
    if ($mode -eq 'quote') { Set-SyError 'missing close quote'; return }
    if ($mode -ne 'bare' -and $Parser.I -lt $Parser.S.Length) {
        $ch=[string]$Parser.S[$Parser.I]
        if (!" `t`r`n".Contains($ch) -and ($Parser.M -or ($ch -cne ';' -and (!$Parser.B -or $ch -cne ']')))) {
            Set-SyError 'extra characters after close quote or brace'; return
        }
    }
    $script:Sy.R=$b.ToString()
}
function ConvertFrom-SyList([string]$Text) {
    $p=@{S=$Text; I=0; M=$true; B=$false}; $items=New-Object 'System.Collections.Generic.List[string]'
    while ($p.I -lt $p.S.Length) {
        if (" `t`r`n".Contains([string]$p.S[$p.I])) { $p.I++; continue }
        if ($p.S[$p.I] -ceq '\' -and $p.I+1 -lt $p.S.Length -and $p.S[$p.I+1] -ceq "`n") { Read-SyEscape $p; continue }
        Read-SyWord $p; if ($script:Sy.C) { return ,@() }; $items.Add($script:Sy.R)
    }
    return ,$items.ToArray()
}
function Invoke-SyScript([string]$Text) { Invoke-SyParser @{S=$Text; I=0; M=$false; B=$false} }
function Invoke-SyParser($Parser) {
    $script:Sy.Depth++; $script:Sy.R=''; $script:Sy.C=0
    try {
        if ($script:Sy.Depth -gt 64) { Set-SyError 'evaluation depth exceeded'; return }
        $words=New-Object 'System.Collections.Generic.List[string]'
        while ($Parser.I -lt $Parser.S.Length) {
            $ch=[string]$Parser.S[$Parser.I]
            if (" `t`r".Contains($ch)) { $Parser.I++; continue }
            if ($ch -ceq '\' -and $Parser.I+1 -lt $Parser.S.Length -and $Parser.S[$Parser.I+1] -ceq "`n") {
                $saved=$script:Sy.R; Read-SyEscape $Parser; $script:Sy.R=$saved; continue
            }
            if ($ch -ceq '#' -and !$words.Count) {
                while ($Parser.I -lt $Parser.S.Length -and $Parser.S[$Parser.I] -cne "`n") {
                    if ($Parser.S[$Parser.I] -ceq '\' -and $Parser.I+1 -lt $Parser.S.Length -and $Parser.S[$Parser.I+1] -ceq "`n") { $Parser.I+=2 }
                    else { $Parser.I++ }
                }
                continue
            }
            if ($ch -ceq ';' -or $ch -ceq "`n" -or ($Parser.B -and $ch -ceq ']')) {
                if ($words.Count) { Invoke-SyCommand $words.ToArray(); $words.Clear() }
                $Parser.I++
                if ($script:Sy.C -or ($Parser.B -and $ch -ceq ']')) { return }
                continue
            }
            Read-SyWord $Parser; if ($script:Sy.C) { return }; $words.Add($script:Sy.R)
        }
        if ($Parser.B) { Set-SyError 'missing close bracket'; return }
        if ($words.Count) { Invoke-SyCommand $words.ToArray() }
    } finally { $script:Sy.Depth-- }
}
function Complete-SyReturn {
    if ($script:Sy.C -eq 2) {
        $script:Sy.RL--
        if ($script:Sy.RL -le 0) {
            $script:Sy.C=$script:Sy.RC; $script:Sy.RC=0; $script:Sy.RL=0
            if ($script:Sy.C -eq 2) { $script:Sy.RL=1 }
        }
    }
}
function Invoke-SyProcedure($Procedure, [string[]]$Actual) {
    $formals=ConvertFrom-SyList $Procedure.Args; if ($script:Sy.C) { return }
    $old=$script:Sy.F; $script:Sy.NF++; $frame=$script:Sy.NF
    $script:Sy.Parent[$frame]=$old; $script:Sy.F=$frame
    try {
        $variadic=$false
        for ($i=0; $i -lt $formals.Count; $i++) {
            $param=ConvertFrom-SyList $formals[$i]; if ($script:Sy.C) { return }
            if ($param[0] -ceq 'args' -and $i -eq $formals.Count-1) {
                $rest=@(); if ($i -lt $Actual.Count) { $rest=$Actual[$i..($Actual.Count-1)] }
                ConvertTo-SyList $rest; Set-SyVariable args $script:Sy.R; $variadic=$true; break
            }
            if ($i -lt $Actual.Count) { $value=$Actual[$i] }
            elseif ($param.Count -eq 2) { $value=$param[1] }
            else { Set-SyArity 'procedure arguments'; return }
            Set-SyVariable $param[0] $value
        }
        if (!$variadic -and $Actual.Count -gt $formals.Count) { Set-SyArity 'procedure arguments'; return }
        Invoke-SyScript $Procedure.Body; Complete-SyReturn
    } finally {
        $script:Sy.F=$old; $script:Sy.Parent.Remove($frame)
        foreach ($key in @($script:Sy.Vars.Keys)) { if ($key.StartsWith("${frame}:")) { $script:Sy.Vars.Remove($key) } }
        foreach ($key in @($script:Sy.Aliases.Keys)) { if ($key.StartsWith("${frame}:")) { $script:Sy.Aliases.Remove($key) } }
    }
}
function Register-SyNative([string]$Name, [scriptblock]$Handler) { $script:Sy.Native[$Name]=$Handler }
function Invoke-SyCommand([string[]]$Words) {
    $cmd=$Words[0]; $a=@(); if ($Words.Count -gt 1) { $a=$Words[1..($Words.Count-1)] }
    $script:Sy.R=''; $script:Sy.C=0
    if ($script:Sy.Procs.ContainsKey($cmd)) { Invoke-SyProcedure $script:Sy.Procs[$cmd] $a; return }
    if ($script:Sy.Native.ContainsKey($cmd)) { & $script:Sy.Native[$cmd] $a; return }
    Set-SyError "unknown command: $cmd"
}
# Exact extensions and non-hidden direct files, in culture-independent order.
function Get-SyLibraryFiles([string]$Directory, [string]$Extension) {
    [string[]]$files=@([IO.Directory]::GetFiles($Directory) | Where-Object {
        ![IO.Path]::GetFileName($_).StartsWith('.') -and [IO.Path]::GetExtension($_) -ceq $Extension
    })
    [Array]::Sort($files, [StringComparer]::Ordinal)
    return $files
}
function Import-SySdk {
    foreach ($file in @(Get-SyLibraryFiles "$script:SyHome/../sdk" '.tcl')) {
        Invoke-SyCommand @('source',$file)
        if ($script:Sy.C) { $script:Sy.R="cannot load SDK file: ${file}: $($script:Sy.R)"; return }
    }
}
function Start-Sycol([string[]]$Arguments) {
    $ErrorActionPreference='Stop'
    if (!$Arguments.Count) { [Console]::Error.WriteLine('usage: powershell -File sycol.ps1 script.tcl [args ...]'); return 2 }
    $file=$Arguments[0]; $rest=@(); if ($Arguments.Count -gt 1) { $rest=$Arguments[1..($Arguments.Count-1)] }
    ConvertTo-SyList $rest; Set-SyVariable argv $script:Sy.R; Set-SyVariable argc ([string]$rest.Count)
    Set-SyVariable argv0 $file; Set-SyVariable sycol_host powershell
    try {
        Import-SySdk
        if (!$script:Sy.C) { Invoke-SyCommand @('source',$file) }
    } catch { Set-SyError "host failure: $($_.Exception.Message)" }
    if ($script:Sy.C) { [Console]::Error.WriteLine("sycol: $($script:Sy.R) (completion $($script:Sy.C))"); return 1 }
    return 0
}
# Dot-source at this scope so module helper functions survive embedding.
$syLoadPreference=$ErrorActionPreference
try {
    $ErrorActionPreference='Stop'
    foreach ($syNativeFile in @(Get-SyLibraryFiles "$script:SyHome/../native" '.ps1')) {
        try { . $syNativeFile } catch { throw "cannot load native file: ${syNativeFile}: $($_.Exception.Message)" }
    }
} finally {
    $ErrorActionPreference=$syLoadPreference
}
if ($MyInvocation.InvocationName -ne '.') { exit (Start-Sycol ([string[]]$args)) }
