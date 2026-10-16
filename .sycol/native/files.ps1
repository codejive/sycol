# Resolve through PowerShell's cwd, which need not be the process cwd.
function Get-SyFilePath([string]$Path, [bool]$ExpandHome=$true) {
    if (!$Path.Length) { throw 'empty file path' }
    if ($ExpandHome -and $Path.StartsWith('~')) {
        if ($Path.Length -gt 1 -and $Path[1] -ne '/' -and $Path[1] -ne '\') { throw 'named-user home paths are not supported' }
        $homePath=[Environment]::GetEnvironmentVariable('HOME')
        if (!$homePath) { $homePath=[Environment]::GetEnvironmentVariable('USERPROFILE') }
        if (!$homePath) { $homePath=[Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) }
        if (!$homePath) { throw 'cannot resolve home directory' }
        $Path=$homePath+$Path.Substring(1)
    }
    $full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $root=[IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) { $full=$full.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) }
    return $full
}
# On Unix, older supported .NET versions have no public Unix mode API.
# Use standard stat/chmod utilities without a shell or PowerShell argv conversion.
function Invoke-SyFileUtility([string]$Program, [string[]]$Arguments) {
    $process=New-Object Diagnostics.Process
    try {
        $info=$process.StartInfo; $info.FileName=$Program; $info.UseShellExecute=$false
        $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
        foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
        if (!$process.Start()) { throw 'cannot start filesystem utility' }
        $output=$process.StandardOutput.ReadToEnd(); $null=$process.StandardError.ReadToEnd(); $process.WaitForExit()
        if ($process.ExitCode) { throw 'filesystem utility failed' }
        return $output.Trim()
    } finally { $process.Dispose() }
}
function Get-SyUnixMode([string]$Path) {
    try { return [Convert]::ToInt32((Invoke-SyFileUtility stat @('-L','-c','%f',$Path)),16) }
    catch { return [Convert]::ToInt32((Invoke-SyFileUtility stat @('-L','-f','%p',$Path)),8) }
}
function Get-SyFileType([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 'link' }
    if ($item -is [IO.DirectoryInfo]) { return 'directory' }
    if ($env:OS -ne 'Windows_NT') {
        switch ((Get-SyUnixMode $Path) -band 61440) {
            4096 { return 'fifo' }
            8192 { return 'characterSpecial' }
            24576 { return 'blockSpecial' }
            32768 { return 'file' }
            49152 { return 'socket' }
            default { throw 'unsupported file type' }
        }
    }
    if ($item -is [IO.FileInfo]) { return 'file' }
    throw 'unsupported file type'
}
function Get-SyOptionalFileType([string]$Path) {
    try { return Get-SyFileType $Path } catch [System.Management.Automation.ItemNotFoundException] { return '' }
}
function Remove-SyFile([string]$Path, [bool]$Recursive, [bool]$Force) {
    $kind=Get-SyFileType $Path
    if ($kind -eq 'directory') {
        if ($Force) {
            try {
                if ($env:OS -eq 'Windows_NT') {
                    $attributes=[IO.File]::GetAttributes($Path)
                    [IO.File]::SetAttributes($Path,($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
                } else { $null=Invoke-SyFileUtility chmod @('u+rwx',$Path) }
            } catch { } # Best effort; the actual operation still reports failures.
        }
        if ($Recursive) {
            foreach ($child in [IO.Directory]::GetFileSystemEntries($Path)) { Remove-SyFile $child $true $Force }
        }
        [IO.Directory]::Delete($Path)
    } elseif ($kind -eq 'link') {
        $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($Path) }
        else { [IO.File]::Delete($Path) }
    } else {
        # Tcl removes read-only files even without -force.
        if ($env:OS -eq 'Windows_NT') {
            $attributes=[IO.File]::GetAttributes($Path)
            [IO.File]::SetAttributes($Path,($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
        }
        [IO.File]::Delete($Path)
    }
}
function Get-SyCopyTree([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $tree=@{ Path=$Path; Kind=(Get-SyFileType $Path); Children=@();
        Write=$item.LastWriteTimeUtc; Access=$item.LastAccessTimeUtc; Attributes=$item.Attributes; Mode=0 }
    if ($env:OS -ne 'Windows_NT' -and $tree.Kind -ne 'link') { $tree.Mode=Get-SyUnixMode $Path }
    if ($tree.Kind -eq 'directory') {
        foreach ($child in [IO.Directory]::GetFileSystemEntries($Path)) { $tree.Children+=Get-SyCopyTree $child }
    }
    return $tree
}
function Copy-SyFile([string]$Path, [string]$Target, $Tree=$null, [bool]$Overwrite=$false) {
    # Snapshot before creating directories to keep traversal finite through aliases.
    if ($null -eq $Tree) { $Tree=Get-SyCopyTree $Path }
    $kind=$Tree.Kind
    if ($kind -eq 'link') {
        $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.LinkType -ne 'SymbolicLink' -and $item.LinkType -ne 'Junction') { throw 'unsupported link type' }
        $null=New-Item -ItemType $item.LinkType -Path $Target -Target $item.Target -ErrorAction Stop
        return
    }
    if ($kind -eq 'directory') {
        $null=[IO.Directory]::CreateDirectory($Target)
        foreach ($child in $Tree.Children) {
            Copy-SyFile $child.Path (Join-Path $Target ([IO.Path]::GetFileName($child.Path))) $child
        }
        [IO.Directory]::SetLastWriteTimeUtc($Target,$Tree.Write)
        [IO.Directory]::SetLastAccessTimeUtc($Target,$Tree.Access)
    } elseif ($kind -eq 'file') {
        [IO.File]::Copy($Path,$Target,$Overwrite)
        [IO.File]::SetLastWriteTimeUtc($Target,$Tree.Write)
        [IO.File]::SetLastAccessTimeUtc($Target,$Tree.Access)
    } else { throw 'copying special files is not supported' }
    [IO.File]::SetAttributes($Target,$Tree.Attributes)
    if ($env:OS -ne 'Windows_NT') {
        $mode=[Convert]::ToString(($Tree.Mode -band 4095),8)
        $null=Invoke-SyFileUtility chmod @($mode,$Target)
    }
}
# Resolve parent links for comparisons without dereferencing a final link.
function Resolve-SyDirectoryPath([string]$Path, [int]$Links=0) {
    if ($Links -gt 40) { throw 'too many directory links' }
    if ($Path -eq [IO.Path]::GetPathRoot($Path)) { return $Path }
    $parent=[IO.Path]::GetDirectoryName($Path)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target=[string]@($item.Target)[0]
        if (!$target) { throw 'cannot resolve directory link' }
        if (![IO.Path]::IsPathRooted($target)) { $target=Join-Path $parent $target }
        return Resolve-SyDirectoryPath ([IO.Path]::GetFullPath($target)) ($Links+1)
    }
    return Join-Path (Resolve-SyDirectoryPath $parent $Links) ([IO.Path]::GetFileName($Path))
}
function Resolve-SyEntryPath([string]$Path, [string]$Kind) {
    if ($Kind -eq 'directory') { return Resolve-SyDirectoryPath $Path }
    return Join-Path (Resolve-SyDirectoryPath ([IO.Path]::GetDirectoryName($Path))) ([IO.Path]::GetFileName($Path))
}
function Move-SyFile([string]$Path, [string]$Target, [string]$Kind, [bool]$Replace) {
    if ($env:OS -eq 'Windows_NT' -and ![string]::Equals([IO.Path]::GetPathRoot($Path),[IO.Path]::GetPathRoot($Target),[StringComparison]::OrdinalIgnoreCase)) {
        Copy-SyFile $Path $Target $null $Replace
        Remove-SyFile $Path $true $true
        return
    }
    try {
        if ($Kind -eq 'directory' -or ($Kind -eq 'link' -and [IO.Directory]::Exists($Path))) { [IO.Directory]::Move($Path,$Target) }
        elseif ($Replace) { [IO.File]::Replace($Path,$Target,[NullString]::Value) }
        else { [IO.File]::Move($Path,$Target) }
        return
    } catch {
        $failure=$_.Exception
        while ($failure.InnerException) { $failure=$failure.InnerException }
        $code=$failure.HResult -band 65535
        # Windows ERROR_NOT_SAME_DEVICE / Unix EXDEV. Do not turn unrelated
        # rename failures into a destructive copy/delete operation.
        if ($code -ne 17 -and $code -ne 18) { throw }
    }
    Copy-SyFile $Path $Target $null $Replace
    Remove-SyFile $Path $true $true
}
Register-SyNative 'sy.file' {
    param([string[]]$a)
    $op=$a[0]
    if ($op -ceq 'windows' -and $a.Count -eq 1) { $script:Sy.R=[string][int]([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT); return }
    $single=@('list','type','exists','isfile','isdirectory','size','mkdir','expand')
    if (!($single -ccontains $op -and $a.Count -eq 2) -and
        !($op -ceq 'delete' -and $a.Count -eq 3) -and !(($op -ceq 'copy' -or $op -ceq 'rename') -and $a.Count -eq 5)) {
        Set-SyArity 'sy.file windows | expand path | list path | type path | exists path | isfile path | isdirectory path | size path | mkdir path | delete path force | copy/rename source target force intoDirectory'; return
    }
    try {
        if ($op -ceq 'delete' -and !$a[1].Length) { $script:Sy.R=''; return }
        if (@('exists','isfile','isdirectory') -ccontains $op -and !$a[1].Length) { $script:Sy.R='0'; return }
        $path=Get-SyFilePath $a[1] ($op -cne 'list')
        if ($op -ceq 'expand') { $script:Sy.R=$path; return }
        if ($op -ceq 'mkdir') { $null=[IO.Directory]::CreateDirectory($path); $script:Sy.R=''; return }
        if ($op -ceq 'size') {
            if ($env:OS -eq 'Windows_NT') {
                if ([IO.Directory]::Exists($path)) { $script:Sy.R='0' }
                else { $script:Sy.R=([IO.FileInfo](Resolve-SyDirectoryPath $path)).Length.ToString([Globalization.CultureInfo]::InvariantCulture) }
            } else {
                try { $script:Sy.R=Invoke-SyFileUtility stat @('-L','-c','%s',$path) }
                catch { $script:Sy.R=Invoke-SyFileUtility stat @('-L','-f','%z',$path) }
            }
            return
        }
        if ($op -ceq 'exists') {
            $actual=Resolve-SyDirectoryPath $path
            $script:Sy.R=[string][int]([IO.File]::Exists($actual) -or [IO.Directory]::Exists($actual)); return
        }
        if ($op -ceq 'isfile') {
            if ($env:OS -eq 'Windows_NT') { $script:Sy.R=[string][int][IO.File]::Exists((Resolve-SyDirectoryPath $path)) }
            else { $script:Sy.R=[string][int](((Get-SyUnixMode $path) -band 61440) -eq 32768) }
            return
        }
        if ($op -ceq 'type') { $script:Sy.R=Get-SyFileType $path; return }
        if ($op -ceq 'isdirectory') { $script:Sy.R=[string][int][IO.Directory]::Exists((Resolve-SyDirectoryPath $path)); return }
        if ($op -ceq 'list') {
            $names=@([IO.Directory]::GetFileSystemEntries($path) | ForEach-Object { [IO.Path]::GetFileName($_) })
            ConvertTo-SyList $names; return
        }
        $comparison=[StringComparison]::Ordinal
        if ($env:OS -eq 'Windows_NT') { $comparison=[StringComparison]::OrdinalIgnoreCase }
        if ($op -ceq 'delete') {
            $kind=Get-SyOptionalFileType $path
            if (!$kind) { $script:Sy.R=''; return }
            if ($path.Equals([IO.Path]::GetPathRoot($path),$comparison)) { throw 'cannot remove a filesystem root' }
            if ($a[2] -ceq '1' -and $kind -eq 'directory') {
                $prefix=$path+[IO.Path]::DirectorySeparatorChar
                $cwd=(Get-Location).ProviderPath
                if ($cwd.Equals($path,$comparison) -or $cwd.StartsWith($prefix,$comparison)) { Set-Location -LiteralPath ([IO.Path]::GetDirectoryName($path)) -ErrorAction Stop }
                $cwd=[Environment]::CurrentDirectory
                if ($cwd.Equals($path,$comparison) -or $cwd.StartsWith($prefix,$comparison)) { [Environment]::CurrentDirectory=[IO.Path]::GetDirectoryName($path) }
            }
            Remove-SyFile $path ($a[2] -ceq '1') ($a[2] -ceq '1')
        } else {
            $target=Get-SyFilePath $a[2]
            if ($a[4] -ceq '1') { $target=Join-Path $target ([IO.Path]::GetFileName($path)) }
            if (![IO.Directory]::Exists([IO.Path]::GetDirectoryName($target))) { throw 'missing target parent' }
            $kind=Get-SyFileType $path
            $sourcePhysical=Resolve-SyEntryPath $path $kind
            $targetPhysical=Resolve-SyEntryPath $target ''
            $existing=Get-SyOptionalFileType $target
            $overwrite=$false
            if ($existing) {
                if ($a[3] -cne '1') {
                    $display=$a[2]
                    if ($a[4] -ceq '1') { $display=$display.TrimEnd('/','\')+'/'+[IO.Path]::GetFileName($path) }
                    Set-SyError "$op target exists: $display"; return
                }
                if ($sourcePhysical.Equals($targetPhysical,$comparison)) {
                    if ($op -ceq 'rename') { $script:Sy.R='' } else { Set-SyError 'cannot copy a file onto itself' }
                    return
                }
                if ($kind -eq 'directory' -or $existing -eq 'directory') {
                    if ($op -cne 'rename' -or $kind -ne 'directory' -or $existing -ne 'directory') { throw 'cannot merge directory trees or replace a directory with a file' }
                    if ([IO.Directory]::GetFileSystemEntries($target).Count) { throw 'destination directory is not empty' }
                }
                elseif ($existing -eq 'link' -or $kind -eq 'link') { }
                else {
                    # The OS copy detects aliases; never unlink regular targets first.
                    [IO.File]::SetAttributes($target,[IO.FileAttributes]::Normal)
                    $overwrite=$true
                }
            }
            $prefix=$sourcePhysical.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
            if ($kind -eq 'directory' -and ($targetPhysical.Equals($sourcePhysical,$comparison) -or $targetPhysical.StartsWith($prefix,$comparison))) { throw 'destination is inside source' }
            if ($existing -and ($existing -eq 'link' -or $kind -eq 'link' -or $existing -eq 'directory')) { Remove-SyFile $target $false $true }
            if ($op -ceq 'rename') { Move-SyFile $path $target $kind $overwrite }
            else { Copy-SyFile $path $target $null $overwrite }
        }
        $script:Sy.R=''
    } catch {
        if (@('exists','isfile','isdirectory') -ccontains $op) { $script:Sy.R='0'; $script:Sy.C=0 }
        elseif ($_.Exception.Message -eq 'named-user home paths are not supported' -or $_.Exception.Message -eq 'cannot resolve home directory') { Set-SyError $_.Exception.Message }
        elseif ($op -ceq 'type') { Set-SyError "cannot stat path: $($a[1])" }
        elseif ($op -ceq 'list') { Set-SyError "cannot list directory: $($a[1])" }
        else { Set-SyError "cannot $op path: $($a[1])" }
    }
}
