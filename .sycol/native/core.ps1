# Built-in native handlers. Loaded by discovery before SDK initialization.

Register-SyNative 'set' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -eq 1) { Get-SyVariable $a[0] } elseif ($n -eq 2) { Set-SyVariable $a[0] $a[1] }
    else { Set-SyArity 'set name ?value?' }
}

Register-SyNative 'unset' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -ne 1) { Set-SyArity 'unset name'; return }; $key=Get-SyKey $a[0]; if ($script:Sy.C) { return }
    if ($script:Sy.Vars.ContainsKey($key)) { $script:Sy.Vars.Remove($key) }
    else { Set-SyError "no such variable: $($a[0])" }
}

Register-SyNative 'global' {
    param([string[]]$a)
    foreach ($name in $a) { if ($name.StartsWith('::')) { $name=$name.Substring(2) }; $script:Sy.Aliases["$($script:Sy.F):$name"]='' }
}

Register-SyNative 'proc' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -ne 3) { Set-SyArity 'proc name arguments body'; return }
    $formals=ConvertFrom-SyList $a[1]; if ($script:Sy.C) { return }
    foreach ($formal in $formals) {
        $param=ConvertFrom-SyList $formal; if ($script:Sy.C) { return }
        if ($param.Count -lt 1 -or $param.Count -gt 2 -or !$param[0].Length -or $param[0].StartsWith('::')) { Set-SyError 'invalid formal parameter'; return }
    }
    $script:Sy.Procs[$a[0]]=@{Args=$a[1]; Body=$a[2]}; $script:Sy.R=''
}

Register-SyNative 'eval' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -eq 1) { Invoke-SyScript $a[0] } else { Set-SyArity 'eval script' }
}

Register-SyNative 'uplevel' {
    param([string[]]$a)
    $n=$a.Count
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

Register-SyNative 'catch' {
    param([string[]]$a)
    $n=$a.Count
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

Register-SyNative 'return' {
    param([string[]]$a)
    $n=$a.Count
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

function Invoke-SyNativeFlow([string]$cmd, [string[]]$a) {
    $n=$a.Count
    if ($n) { Set-SyArity $cmd } elseif ($cmd -ceq 'break') { $script:Sy.C=3 } else { $script:Sy.C=4 }
}
Register-SyNative 'break' { param([string[]]$a); Invoke-SyNativeFlow 'break' $a }
Register-SyNative 'continue' { param([string[]]$a); Invoke-SyNativeFlow 'continue' $a }

Register-SyNative 'error' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -eq 1) { Set-SyError $a[0] } else { Set-SyArity 'error message' }
}

Register-SyNative 'if' {
    param([string[]]$a)
    $n=$a.Count
    if (($n -ne 2 -and $n -ne 4) -or ($n -eq 4 -and $a[2] -cne 'else')) { Set-SyArity 'if boolean body ?else body?'; return }
    Convert-SyTruth $a[0]; if ($script:Sy.C) { return }
    if ($script:Sy.R -ceq '1') { Invoke-SyScript $a[1] }
    elseif ($n -eq 4) { Invoke-SyScript $a[3] } else { $script:Sy.R='' }
}

Register-SyNative 'while' {
    param([string[]]$a)
    $n=$a.Count
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

Register-SyNative 'list' {
    param([string[]]$a)
    ConvertTo-SyList $a
}

function Invoke-SyNativeListIndex([string]$cmd, [string[]]$a) {
    $n=$a.Count
    if (($cmd -ceq 'llength' -and $n -ne 1) -or ($cmd -ceq 'lindex' -and $n -ne 2)) { Set-SyArity "$cmd list ?index?"; return }
    $items=ConvertFrom-SyList $a[0]; if ($script:Sy.C) { return }
    if ($cmd -ceq 'llength') { $script:Sy.R=[string]$items.Count }
    else {
        Convert-SyInteger $a[1]; if ($script:Sy.C) { return }; $index=[int]$script:Sy.R; $script:Sy.R=''
        if ($index -ge 0 -and $index -lt $items.Count) { $script:Sy.R=$items[$index] }
    }
}
Register-SyNative 'llength' { param([string[]]$a); Invoke-SyNativeListIndex 'llength' $a }
Register-SyNative 'lindex' { param([string[]]$a); Invoke-SyNativeListIndex 'lindex' $a }

Register-SyNative 'string' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -eq 2 -and $a[0] -ceq 'length') { $script:Sy.R=[string]$a[1].Length }
    elseif ($n -eq 3 -and $a[0] -ceq 'equal') { $script:Sy.R=[string][int]([string]::Equals($a[1],$a[2],[StringComparison]::Ordinal)) }
    elseif ($n -eq 4 -and $a[0] -ceq 'range') {
        Convert-SyInteger $a[2]; if ($script:Sy.C) { return }; $first=[Math]::Max(0,[int]$script:Sy.R)
        Convert-SyInteger $a[3]; if ($script:Sy.C) { return }; $last=[Math]::Min($a[1].Length-1,[int]$script:Sy.R)
        $script:Sy.R=''; if ($last -ge $first) { $script:Sy.R=$a[1].Substring($first,$last-$first+1) }
    } else { Set-SyArity 'string length value | equal a b | range value first last' }
}

function Invoke-SyNativeMath([string]$cmd, [string[]]$a) {
    $n=$a.Count
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
Register-SyNative '+' { param([string[]]$a); Invoke-SyNativeMath '+' $a }
Register-SyNative '-' { param([string[]]$a); Invoke-SyNativeMath '-' $a }
Register-SyNative '*' { param([string[]]$a); Invoke-SyNativeMath '*' $a }
Register-SyNative '/' { param([string[]]$a); Invoke-SyNativeMath '/' $a }
Register-SyNative '%' { param([string[]]$a); Invoke-SyNativeMath '%' $a }
Register-SyNative '<' { param([string[]]$a); Invoke-SyNativeMath '<' $a }
Register-SyNative '<=' { param([string[]]$a); Invoke-SyNativeMath '<=' $a }
Register-SyNative '>' { param([string[]]$a); Invoke-SyNativeMath '>' $a }
Register-SyNative '>=' { param([string[]]$a); Invoke-SyNativeMath '>=' $a }
Register-SyNative '==' { param([string[]]$a); Invoke-SyNativeMath '==' $a }
Register-SyNative '!=' { param([string[]]$a); Invoke-SyNativeMath '!=' $a }
Register-SyNative '!' { param([string[]]$a); Invoke-SyNativeMath '!' $a }

Register-SyNative 'puts' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -eq 1) { [Console]::Out.WriteLine($a[0]) }
    elseif ($n -eq 2 -and $a[0] -ceq '-nonewline') { [Console]::Out.Write($a[1]) }
    else { Set-SyArity 'puts ?-nonewline? value' }
}

function Invoke-SyNativeRead([string]$cmd, [string[]]$a) {
    $n=$a.Count
    if ($n -ne 1) { Set-SyArity "$cmd path"; return }
    # Decode as UTF-8 directly, without BOM-based encoding detection or validation.
    try {
        $bytes=[IO.File]::ReadAllBytes($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($a[0]))
        $text=(New-Object Text.UTF8Encoding($false)).GetString($bytes)
    }
    catch { Set-SyError "cannot read file: $($a[0])"; return }
    if ($text.Length -and $text[0] -eq [char]0xFEFF) { $text=$text.Substring(1) }
    if ($text.IndexOf([char]0) -ge 0) { Set-SyError "NUL in text file: $($a[0])"; return }
    if ($cmd -ceq 'source') { Invoke-SyScript ($text.Replace("`r`n","`n")); Complete-SyReturn } else { $script:Sy.R=$text }
}
Register-SyNative 'source' { param([string[]]$a); Invoke-SyNativeRead 'source' $a }
Register-SyNative 'readfile' { param([string[]]$a); Invoke-SyNativeRead 'readfile' $a }

Register-SyNative 'writefile' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -ne 2) { Set-SyArity 'writefile path text'; return }
    try { [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($a[0]),$a[1],(New-Object Text.UTF8Encoding($false))) }
    catch { Set-SyError "cannot write file: $($a[0])" }
}

Register-SyNative 'pwd' {
    param([string[]]$a)
    $n=$a.Count
    if ($n) { Set-SyArity pwd } else { $script:Sy.R=(Get-Location).ProviderPath }
}

Register-SyNative 'cd' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -ne 1) { Set-SyArity 'cd path'; return }
    try { Set-Location -LiteralPath $a[0] -ErrorAction Stop } catch { Set-SyError "cannot change directory: $($a[0])" }
}

Register-SyNative 'getenv' {
    param([string[]]$a)
    $n=$a.Count
    if ($n -ne 1 -or $a[0] -cnotmatch '^[a-zA-Z_][a-zA-Z0-9_]*$') { Set-SyArity 'getenv name' }
    else { $script:Sy.R=[string][Environment]::GetEnvironmentVariable($a[0]) }
}

Register-SyNative 'exec' {
    param([string[]]$a)
    Invoke-SyProcess $a
}

Register-SyNative 'exit' {
    param([string[]]$a)
    if ($a.Count -gt 1) { Set-SyArity 'exit ?status?'; return }
    $status='0'
    if ($a.Count) { $status=$a[0] }
    Convert-SyInteger $status
    if ($script:Sy.C) { return }
    $status=[int]$script:Sy.R
    if ($status -lt 0 -or $status -gt 255) { Set-SyError 'exit status must be 0..255'; return }
    [Environment]::Exit($status)
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
