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
    $n=$a.Count; $script:Sy.R=''; $script:Sy.C=0
    if ($script:Sy.Procs.ContainsKey($cmd)) { Invoke-SyProcedure $script:Sy.Procs[$cmd] $a; return }
    if ($script:Sy.Native.ContainsKey($cmd)) { & $script:Sy.Native[$cmd] $a; return }
    switch -CaseSensitive ($cmd) {
        set {
            if ($n -eq 1) { Get-SyVariable $a[0] } elseif ($n -eq 2) { Set-SyVariable $a[0] $a[1] }
            else { Set-SyArity 'set name ?value?' }
        }
        unset {
            if ($n -ne 1) { Set-SyArity 'unset name'; return }; $key=Get-SyKey $a[0]; if ($script:Sy.C) { return }
            if ($script:Sy.Vars.ContainsKey($key)) { $script:Sy.Vars.Remove($key) }
            else { Set-SyError "no such variable: $($a[0])" }
        }
        global { foreach ($name in $a) { if ($name.StartsWith('::')) { $name=$name.Substring(2) }; $script:Sy.Aliases["$($script:Sy.F):$name"]='' } }
        proc {
            if ($n -ne 3) { Set-SyArity 'proc name arguments body'; return }
            $formals=ConvertFrom-SyList $a[1]; if ($script:Sy.C) { return }
            foreach ($formal in $formals) {
                $param=ConvertFrom-SyList $formal; if ($script:Sy.C) { return }
                if ($param.Count -lt 1 -or $param.Count -gt 2 -or !$param[0].Length -or $param[0].StartsWith('::')) { Set-SyError 'invalid formal parameter'; return }
            }
            $script:Sy.Procs[$a[0]]=@{Args=$a[1]; Body=$a[2]}; $script:Sy.R=''
        }
        eval { if ($n -eq 1) { Invoke-SyScript $a[0] } else { Set-SyArity 'eval script' } }
        uplevel {
            if ($n -ne 2) { Set-SyArity 'uplevel level script'; return }
            $old=$script:Sy.F; $frame=$old
            if ($a[0] -ceq '#0') { $frame=0 } else {
                Convert-SyInteger $a[0]; if ($script:Sy.C) { return }; $level=[int]$script:Sy.R
                if ($level -lt 0 -or $level -gt 128) { Set-SyError 'bad level'; return }
                while ($level -gt 0) {
                    if (!$frame) { Set-SyError 'bad level'; return }; $frame=$script:Sy.Parent[$frame]; $level--
                }
            }
            $script:Sy.F=$frame
            try { Invoke-SyScript $a[1] } finally { $script:Sy.F=$old }
        }
        catch {
            if ($n -lt 1 -or $n -gt 3) { Set-SyArity 'catch script ?resultVar? ?optionsVar?'; return }
            Invoke-SyScript $a[0]; $value=$script:Sy.R; $code=$script:Sy.C
            $rc=$script:Sy.RC; $rl=$script:Sy.RL; $script:Sy.C=0; $script:Sy.RC=0; $script:Sy.RL=0
            if ($n -gt 1) { Set-SyVariable $a[1] $value; if ($script:Sy.C) { return } }
            if ($n -gt 2) {
                if ($code -eq 2) { $options="-code $rc -level $rl" } else { $options="-code $code -level 0" }
                Set-SyVariable $a[2] $options; if ($script:Sy.C) { return }
            }
            $script:Sy.R=[string]$code
        }
        return {
            $code=0; $level=1; $i=0
            while ($n-$i -gt 1) {
                if ($a[$i] -cne '-code' -and $a[$i] -cne '-level') { Set-SyArity 'return ?-code 0..4? ?-level n? ?value?'; return }
                Convert-SyInteger $a[$i+1]; if ($script:Sy.C) { return }; $v=[int]$script:Sy.R
                if ($a[$i] -ceq '-code') { $code=$v } elseif ($a[$i] -ceq '-level') { $level=$v }
                $i+=2
            }
            if ($code -lt 0 -or $code -gt 4 -or $level -lt 0 -or $level -gt 128) { Set-SyError 'invalid return options'; return }
            $script:Sy.R=''; if ($i -lt $n) { $script:Sy.R=$a[$i] }
            $script:Sy.RC=$code; $script:Sy.RL=$level; $script:Sy.C=2
            if (!$level) { $script:Sy.C=$code; if ($code -eq 2) { $script:Sy.RC=0; $script:Sy.RL=1 } }
        }
        { $_ -ceq 'break' -or $_ -ceq 'continue' } {
            if ($n) { Set-SyArity $cmd } elseif ($cmd -ceq 'break') { $script:Sy.C=3 } else { $script:Sy.C=4 }
        }
        error { if ($n -eq 1) { Set-SyError $a[0] } else { Set-SyArity 'error message' } }
        if {
            if (($n -ne 2 -and $n -ne 4) -or ($n -eq 4 -and $a[2] -cne 'else')) { Set-SyArity 'if boolean body ?else body?'; return }
            Convert-SyTruth $a[0]; if ($script:Sy.C) { return }
            if ($script:Sy.R -ceq '1') { Invoke-SyScript $a[1] }
            elseif ($n -eq 4) { Invoke-SyScript $a[3] } else { $script:Sy.R='' }
        }
        while {
            if ($n -ne 2) { Set-SyArity 'while testScript body'; return }
            while ($true) {
                Invoke-SyScript $a[0]; if ($script:Sy.C) { return }
                Convert-SyTruth $script:Sy.R; if ($script:Sy.C) { return }
                if ($script:Sy.R -ceq '0') { $script:Sy.R=''; return }
                Invoke-SyScript $a[1]
                if ($script:Sy.C -eq 3) { $script:Sy.C=0; $script:Sy.R=''; return }
                if ($script:Sy.C -eq 4) { $script:Sy.C=0 } elseif ($script:Sy.C) { return }
            }
        }
        list { ConvertTo-SyList $a }
        { $_ -ceq 'llength' -or $_ -ceq 'lindex' } {
            if (($cmd -ceq 'llength' -and $n -ne 1) -or ($cmd -ceq 'lindex' -and $n -ne 2)) { Set-SyArity "$cmd list ?index?"; return }
            $items=ConvertFrom-SyList $a[0]; if ($script:Sy.C) { return }
            if ($cmd -ceq 'llength') { $script:Sy.R=[string]$items.Count }
            else {
                Convert-SyInteger $a[1]; if ($script:Sy.C) { return }; $index=[int]$script:Sy.R; $script:Sy.R=''
                if ($index -ge 0 -and $index -lt $items.Count) { $script:Sy.R=$items[$index] }
            }
        }
        string {
            if ($n -eq 2 -and $a[0] -ceq 'length') { $script:Sy.R=[string]$a[1].Length }
            elseif ($n -eq 3 -and $a[0] -ceq 'equal') { $script:Sy.R=[string][int]([string]::Equals($a[1],$a[2],[StringComparison]::Ordinal)) }
            elseif ($n -eq 4 -and $a[0] -ceq 'range') {
                Convert-SyInteger $a[2]; if ($script:Sy.C) { return }; $first=[Math]::Max(0,[int]$script:Sy.R)
                Convert-SyInteger $a[3]; if ($script:Sy.C) { return }; $last=[Math]::Min($a[1].Length-1,[int]$script:Sy.R)
                $script:Sy.R=''; if ($last -ge $first) { $script:Sy.R=$a[1].Substring($first,$last-$first+1) }
            } else { Set-SyArity 'string length value | equal a b | range value first last' }
        }
        { @('+','-','*','/','%','<','<=','>','>=','==','!=','!') -ccontains $_ } {
            if (($cmd -ceq '!' -and $n -ne 1) -or ($cmd -cne '!' -and $n -ne 2)) { Set-SyArity "$cmd integers"; return }
            Convert-SyInteger $a[0]; if ($script:Sy.C) { return }; $x=[long]$script:Sy.R
            if ($cmd -ceq '!') { $script:Sy.R=[string][int](!$x); return }
            Convert-SyInteger $a[1]; if ($script:Sy.C) { return }; $y=[long]$script:Sy.R
            switch -CaseSensitive ($cmd) {
                '+' { $value=$x+$y }; '-' { $value=$x-$y }; '*' { $value=$x*$y }
                '/' { if (!$y) { Set-SyError 'division by zero'; return }; $value=[Math]::Truncate($x/[double]$y) }
                '%' { if (!$y) { Set-SyError 'division by zero'; return }; $value=$x%$y }
                '<' { $value=[int]($x -lt $y) }; '<=' { $value=[int]($x -le $y) }; '>' { $value=[int]($x -gt $y) }; '>=' { $value=[int]($x -ge $y) }
                '==' { $value=[int]($x -eq $y) }; '!=' { $value=[int]($x -ne $y) }
            }
            if ($value -lt -2147483648 -or $value -gt 2147483647) { Set-SyError 'integer overflow' }
            else { $script:Sy.R=([long]$value).ToString([Globalization.CultureInfo]::InvariantCulture) }
        }
        puts {
            if ($n -eq 1) { [Console]::Out.WriteLine($a[0]) }
            elseif ($n -eq 2 -and $a[0] -ceq '-nonewline') { [Console]::Out.Write($a[1]) }
            else { Set-SyArity 'puts ?-nonewline? value' }
        }
        { $_ -ceq 'source' -or $_ -ceq 'readfile' } {
            if ($n -ne 1) { Set-SyArity "$cmd path"; return }
            try { $text=[IO.File]::ReadAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($a[0]), (New-Object Text.UTF8Encoding($false,$true))) }
            catch { Set-SyError "cannot read file: $($a[0])"; return }
            if ($text.IndexOf([char]0) -ge 0) { Set-SyError "NUL in text file: $($a[0])"; return }
            if ($cmd -ceq 'source') { Invoke-SyScript ($text.Replace("`r`n","`n")); Complete-SyReturn } else { $script:Sy.R=$text }
        }
        writefile {
            if ($n -ne 2) { Set-SyArity 'writefile path text'; return }
            try { [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($a[0]),$a[1],(New-Object Text.UTF8Encoding($false))) }
            catch { Set-SyError "cannot write file: $($a[0])" }
        }
        pwd { if ($n) { Set-SyArity pwd } else { $script:Sy.R=(Get-Location).ProviderPath } }
        cd {
            if ($n -ne 1) { Set-SyArity 'cd path'; return }
            try { Set-Location -LiteralPath $a[0] -ErrorAction Stop } catch { Set-SyError "cannot change directory: $($a[0])" }
        }
        getenv {
            if ($n -ne 1 -or $a[0] -cnotmatch '^[a-zA-Z_][a-zA-Z0-9_]*$') { Set-SyArity 'getenv name' }
            else { $script:Sy.R=[string][Environment]::GetEnvironmentVariable($a[0]) }
        }
        exec { Invoke-SyProcess $a }
        default { Set-SyError "unknown command: $cmd" }
    }
}
# Windows PowerShell lacks ProcessStartInfo.ArgumentList. Quote each argument by
# the Windows CRT convention, including empty strings and final backslashes.
function ConvertTo-SyWindowsArgument([string]$Value) {
    $b=New-Object Text.StringBuilder; [void]$b.Append('"'); $slashes=0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -ceq '\') { $slashes++; continue }
        if ($ch -ceq '"') { [void]$b.Append(('\' * (2*$slashes+1))) }
        else { [void]$b.Append(('\' * $slashes)) }
        [void]$b.Append($ch); $slashes=0
    }
    [void]$b.Append(('\' * (2*$slashes))); [void]$b.Append('"'); return $b.ToString()
}
function Invoke-SyProcess([string[]]$Arguments) {
    if (!$Arguments.Count) { Set-SyArity 'exec program ?arg ...?'; return }
    $process=New-Object Diagnostics.Process
    try {
        $info=$process.StartInfo; $info.FileName=$Arguments[0]; $info.UseShellExecute=$false
        $info.WorkingDirectory=(Get-Location).ProviderPath; $info.RedirectStandardOutput=$true
        $info.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
        if ($info.PSObject.Properties['ArgumentList']) {
            for ($i=1; $i -lt $Arguments.Count; $i++) { $info.ArgumentList.Add($Arguments[$i]) }
        } else {
            $quoted=@(); for ($i=1; $i -lt $Arguments.Count; $i++) { $quoted+=ConvertTo-SyWindowsArgument $Arguments[$i] }
            $info.Arguments=[string]::Join(' ',[string[]]$quoted)
        }
        if (!$process.Start()) { Set-SyError "cannot execute: $($Arguments[0])"; return }
        $output=$process.StandardOutput.ReadToEnd(); $process.WaitForExit()
        if ($process.ExitCode) { Set-SyError "process exited with status $($process.ExitCode)"; return }
        if ($output.EndsWith("`n")) { $output=$output.Substring(0,$output.Length-1); if ($output.EndsWith("`r")) { $output=$output.Substring(0,$output.Length-1) } }
        $script:Sy.R=$output
    } catch { Set-SyError "cannot execute: $($Arguments[0])" }
    finally { $process.Dispose() }
}
function Start-Sycol([string[]]$Arguments) {
    $ErrorActionPreference='Stop'
    if (!$Arguments.Count) { [Console]::Error.WriteLine('usage: powershell -File sycol.ps1 script.tcl [args ...]'); return 2 }
    $file=$Arguments[0]; $rest=@(); if ($Arguments.Count -gt 1) { $rest=$Arguments[1..($Arguments.Count-1)] }
    ConvertTo-SyList $rest; Set-SyVariable argv $script:Sy.R; Set-SyVariable argc ([string]$rest.Count)
    Set-SyVariable argv0 $file; Set-SyVariable sycol_host powershell
    try {
        Invoke-SyCommand @('source', "$script:SyHome/lib/core.tcl")
        if (!$script:Sy.C) { Invoke-SyCommand @('source',$file) }
    } catch { Set-SyError "host failure: $($_.Exception.Message)" }
    if ($script:Sy.C) { [Console]::Error.WriteLine("sycol: $($script:Sy.R) (completion $($script:Sy.C))"); return 1 }
    return 0
}
if ($MyInvocation.InvocationName -ne '.') { exit (Start-Sycol ([string[]]$args)) }
