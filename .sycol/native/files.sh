# Literal host filesystem operations; Tcl option parsing lives in sdk/files.tcl.
sy_file_path() {
    R=$1
    case $R in
        '~'|'~/'*)
            if [[ -z $HOME ]]; then fail 'cannot resolve home directory'; return; fi
            R=$HOME${R:1};;
        '~'*) fail 'named-user home paths are not supported'; return;;
    esac
    while [[ $R == */ && $R != / ]]; do R=${R%/}; done
    [[ -z $R || $R == /* ]] || R=./$R
}
sy_file_type() {
    if [[ -L $1 ]]; then R=link
    elif [[ -f $1 ]]; then R=file
    elif [[ -d $1 ]]; then R=directory
    elif [[ -c $1 ]]; then R=characterSpecial
    elif [[ -b $1 ]]; then R=blockSpecial
    elif [[ -p $1 ]]; then R=fifo
    elif [[ -S $1 ]]; then R=socket
    else fail "cannot stat path: $1"; fi
}
sy_file_absolute() {
    # Resolve ancestor aliases without dereferencing a final symbolic link.
    # The sentinel preserves filenames and directories ending in LF.
    if [[ -d $1 && ! -L $1 ]]; then
        R=$(builtin cd -P -- "$1" && printf '%s.' "$PWD")
    else
        R=$(builtin cd -P -- "${1%/*}" && printf '%s/%s.' "$PWD" "${1##*/}")
    fi
    if (($?)); then fail "cannot resolve path: $1"; else R=${R%.}; fi
}
sy_file_writable() {
    local child
    [[ -L $1 ]] && return
    if [[ -d $1 ]]; then
        command chmod u+rwx "$1" 2>/dev/null
        for child in "$1"/* "$1"/.[!.]* "$1"/..?*; do
            [[ -e $child || -L $child ]] && sy_file_writable "$child"
        done
    else command chmod u+w "$1" 2>/dev/null; fi
}
sy_cmd_file() {
    local op=${1-} path entry target force directory kind source_abs target_abs source_prefix size
    local -a entries=() options=()
    (($#)) && shift
    case $op:$# in
        windows:0) R=0;;
        expand:1) sy_file_path "$1";;
        mkdir:1)
            sy_file_path "$1"; ((C)) && return; path=$R
            if [[ -n $path ]] && command mkdir -p "$path"; then R=; else fail "cannot mkdir path: $1"; fi;;
        size:1)
            sy_file_path "$1"; ((C)) && return; path=$R
            if size=$(command stat -L -c %s "$path" 2>/dev/null) || size=$(command stat -L -f %z "$path" 2>/dev/null); then
                if [[ $size =~ ^[0-9]+$ ]]; then R=$size; else fail "cannot size path: $1"; fi
            else fail "cannot size path: $1"; fi;;
        list:1)
            # Preserve the existing file list extension, including literal paths.
            path=$1
            if [[ ! -d $path || ! -r $path || ! -x $path ]]; then fail "cannot list directory: $path"; return; fi
            for entry in "$path"/* "$path"/.[!.]* "$path"/..?*; do
                [[ -e $entry || -L $entry ]] && entries+=("${entry##*/}")
            done
            quote_list "${entries[@]}";;
        type:1|exists:1|isfile:1|isdirectory:1)
            sy_file_path "$1"
            if ((C)); then
                if [[ $op != type ]]; then C=0; R=0; fi
                return
            fi
            path=$R
            case $op in
                exists) if [[ -e $path ]]; then R=1; else R=0; fi;;
                isfile) if [[ -f $path ]]; then R=1; else R=0; fi;;
                isdirectory) if [[ -d $path ]]; then R=1; else R=0; fi;;
                type) sy_file_type "$path"; if ((C)); then fail "cannot stat path: $1"; fi;;
            esac;;
        delete:2)
            sy_file_path "$1"; ((C)) && return; path=$R; force=$2
            if [[ ! -e $path && ! -L $path ]]; then R=; return; fi
            sy_file_absolute "$path"; ((C)) && return; path=$R
            if [[ $path == / ]]; then fail "cannot delete path: $1"; return; fi
            if [[ -d $path && ! -L $path && $force != 1 ]]; then
                if command rmdir "$path"; then R=; else fail "cannot delete path: $1"; fi
            else
                options=(-f)
                if [[ $force == 1 && -d $path && ! -L $path ]]; then
                    sy_file_writable "$path"
                    # Windows cannot remove the process cwd. Move outside the
                    # tree before removal, as Tcl does when necessary.
                    case $PWD/ in "$path/"*) builtin cd -P -- "${path%/*}/";; esac
                    options+=(-r)
                fi
                if command rm "${options[@]}" "$path"; then R=; else fail "cannot delete path: $1"; fi
            fi;;
        copy:4|rename:4)
            sy_file_path "$1"; ((C)) && return; path=$R
            sy_file_path "$2"; ((C)) && return; target=$R; force=$3; directory=$4
            if [[ -z $path || -z $target ]]; then fail "cannot $op path: $1"; return; fi
            sy_file_type "$path"
            if ((C)); then fail "cannot $op path: $1"; return; fi
            kind=$R
            if [[ $directory == 1 ]]; then target=$target/${path##*/}; fi
            sy_file_absolute "$path"; ((C)) && { fail "cannot $op path: $1"; return; }; source_abs=$R
            sy_file_absolute "$target"; ((C)) && { fail "cannot $op path: $1"; return; }; target_abs=$R
            if [[ -e $target || -L $target ]]; then
                if [[ $force != 1 ]]; then fail "$op target exists: ${target#./}"; return; fi
                if [[ $source_abs == "$target_abs" || $path -ef $target ]]; then
                    if [[ $op == rename ]]; then R=; else fail 'cannot copy a file onto itself'; fi
                    return
                fi
                # Tcl does not merge existing directory trees, even empty ones.
                if [[ $kind == directory || ( -d $target && ! -L $target ) ]]; then
                    if [[ $op != rename || $kind != directory || ! -d $target || -L $target ]]; then fail "cannot $op path: $1"; return; fi
                fi
            fi
            if [[ $kind == directory ]]; then
                source_prefix=${source_abs%/}/
                case $target_abs/ in "$source_prefix"*) fail "cannot $op path: $1"; return;; esac
            fi
            if [[ $op == rename ]]; then
                if [[ -d $target && ! -L $target ]]; then
                    if ! command rmdir "$target"; then fail "cannot rename path: $1"; return; fi
                elif [[ -L $target ]]; then
                    if ! command rm -f "$target"; then fail "cannot rename path: $1"; return; fi
                elif [[ -e $target && $force == 1 ]]; then
                    command chmod u+w "$target" 2>/dev/null
                fi
                # Standard mv already falls back to copy/delete across filesystems.
                if command mv -f "$path" "$target"; then R=; else fail "cannot rename path: $1"; fi
                return
            fi
            # cp follows destination links unless they are explicitly unlinked.
            if [[ -L $target ]]; then
                if ! command rm -f "$target"; then fail "cannot copy path: $1"; return; fi
            elif [[ -e $target && $force == 1 ]]; then command chmod u+w "$target" 2>/dev/null; fi
            options=(-R -P -p)
            [[ $force == 1 ]] && options+=(-f)
            if command cp "${options[@]}" "$path" "$target"; then R=; else fail "cannot copy path: $1"; fi;;
        *) arity 'sy.file windows | expand path | list path | type path | exists path | isfile path | isdirectory path | size path | mkdir path | delete path force | copy/rename source target force intoDirectory';;
    esac
}
sy_register sy.file sy_cmd_file
