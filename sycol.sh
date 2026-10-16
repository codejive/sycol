#!/usr/bin/env bash
# sycol: a string-only Tcl subset. Bash 3.2+, no eval of host source.
# Internal functions return through R (value), C (completion), RC/RL (return).
R= C=0 RC=0 RL=0 F=0 NF=0 DEPTH=0
VK=() VV=() GK=() PN=() PA=() PB=() PARENT=(0) NN=() NH=()

# Native handlers receive literal arguments and set R/C, without stdout results.
sy_register() { NN+=("$1"); NH+=("$2"); }

fail() { R=$1; C=1; }
arity() { fail "wrong # args: $1"; }
integer() {
    local n=$1 sign=1
    case $n in -*) sign=-1; n=${n#-};; +*) n=${n#+};; esac
    case $n in ''|*[!0-9]*) fail "expected integer: $1"; return;; esac
    while [[ ${#n} -gt 1 && ${n:0:1} == 0 ]]; do n=${n:1}; done
    if [[ ${#n} -gt 10 ]]; then fail 'integer overflow'; return; fi
    R=$((sign * 10#$n))
    if ((R < -2147483648 || R > 2147483647)); then fail 'integer overflow'; fi
}
truth() {
    case $1 in true) R=1;; false) R=0;; *) integer "$1"; ((C)) || { if ((R)); then R=1; else R=0; fi; };; esac
}
vkey() {
    local name=$1 frame=$F i
    if [[ $name == ::* ]]; then frame=0; name=${name#::}; fi
    if [[ -z $name ]]; then fail 'empty variable name'; return; fi
    for ((i=0;i<${#GK[@]};i++)); do
        if [[ ${GK[i]} == "$frame:$name" ]]; then frame=0; break; fi
    done
    KEY=$frame:$name
}
vget() {
    local KEY i
    vkey "$1"; ((C)) && return
    for ((i=0;i<${#VK[@]};i++)); do
        if [[ ${VK[i]} == "$KEY" ]]; then R=${VV[i]}; return; fi
    done
    fail "no such variable: $1"
}
vset() {
    local KEY i
    vkey "$1"; ((C)) && return
    for ((i=0;i<${#VK[@]};i++)); do
        if [[ ${VK[i]} == "$KEY" ]]; then VV[i]=$2; R=$2; return; fi
    done
    VK+=("$KEY"); VV+=("$2"); R=$2
}
quote_list() {
    local word ch i out= sep=
    for word in "$@"; do
        out=$out$sep; sep=' '
        if [[ -z $word ]]; then out=$out'{}'; continue; fi
        for ((i=0;i<${#word};i++)); do
            ch=${word:i:1}
            case $ch in
                $'\n') out=$out'\n';; $'\r') out=$out'\r';; $'\t') out=$out'\t';;
                ' '|\\|'{'|'}'|'['|']'|'$'|'"'|';'|'#') out=$out\\$ch;;
                *) out=$out$ch;;
            esac
        done
    done
    R=$out
}
# Parser state S/I/N/M/B is dynamically local to eval_script or parse_list.
# M=1 disables substitutions and script separators (list parsing).
escape_char() {
    I=$((I+1))
    if ((I >= N)); then fail 'trailing backslash'; return; fi
    local ch=${S:I:1}; I=$((I+1))
    case $ch in
        n) R=$'\n';; r) R=$'\r';; t) R=$'\t';;
        $'\n') while ((I<N)) && [[ ${S:I:1} == ' ' || ${S:I:1} == $'\t' ]]; do I=$((I+1)); done; R=' ';;
        *) R=$ch;;
    esac
}
substitute() {
    local ch=${S:I:1} start name
    case $ch in
        \\) escape_char;;
        '$')
            I=$((I+1)); start=$I
            if [[ ${S:I:1} == '{' ]]; then
                I=$((I+1)); start=$I
                while ((I<N)) && [[ ${S:I:1} != '}' ]]; do I=$((I+1)); done
                if ((I==N)); then fail 'missing variable close brace'; return; fi
                name=${S:start:I-start}; I=$((I+1))
            else
                while ((I<N)) && [[ ${S:I:1} == [a-zA-Z0-9_:] ]]; do I=$((I+1)); done
                name=${S:start:I-start}
                if [[ -z $name ]]; then R='$'; return; fi
            fi
            vget "$name";;
        '[')
            eval_script "$S" "$((I+1))" 1
            I=$END;;
        *) R=$ch; I=$((I+1));;
    esac
}
parse_word() {
    local out= ch mode=bare depth=0
    ch=${S:I:1}
    if [[ $ch == '{' ]]; then mode=brace; depth=1; I=$((I+1))
    elif [[ $ch == '"' ]]; then mode=quote; I=$((I+1)); fi
    while ((I<N)); do
        ch=${S:I:1}
        if [[ $mode == brace ]]; then
            I=$((I+1))
            case $ch in
                '{') depth=$((depth+1));;
                '}') depth=$((depth-1)); if ((depth==0)); then break; fi;;
                \\)
                    if ((I<N)); then
                        if [[ ${S:I:1} == $'\n' ]]; then I=$((I-1)); escape_char; out=$out$R; continue; fi
                        out=$out$ch${S:I:1}; I=$((I+1)); continue
                    fi;;
            esac
            out=$out$ch; continue
        fi
        if [[ $mode == quote && $ch == '"' ]]; then I=$((I+1)); mode=closed; break; fi
        if [[ $mode == bare ]]; then
            case $ch in ' '|$'\t'|$'\r'|$'\n') break;; esac
            if [[ ${S:I:2} == $'\\\n' ]]; then break; fi
            if (( ! M )); then
                [[ $ch == ';' ]] && break
                if ((B)) && [[ $ch == ']' ]]; then break; fi
            fi
        fi
        if ((M)) && [[ $ch != \\ ]]; then R=$ch; I=$((I+1)); else substitute; fi
        ((C)) && return
        out=$out$R
    done
    if [[ $mode == brace ]] && ((depth)); then fail 'missing close brace'; return; fi
    if [[ $mode == quote ]]; then fail 'missing close quote'; return; fi
    if [[ $mode != bare ]] && ((I<N)); then
        ch=${S:I:1}
        case $ch in ' '|$'\t'|$'\r'|$'\n') ;; *)
            if ((M)) || [[ $ch != ';' && ( $B == 0 || $ch != ']' ) ]]; then
                fail 'extra characters after close quote or brace'; return
            fi;;
        esac
    fi
    R=$out
}
parse_list() {
    local S=$1 I=0 N=${#1} M=1 B=0 ch
    ITEMS=()
    while ((I<N)); do
        ch=${S:I:1}
        case $ch in ' '|$'\t'|$'\r'|$'\n') I=$((I+1)); continue;; esac
        if [[ ${S:I:2} == $'\\\n' ]]; then escape_char; continue; fi
        parse_word; ((C)) && return
        ITEMS+=("$R")
    done
}
eval_script() {
    local S=$1 I=${2:-0} N=${#1} B=${3:-0} M=0 ch saved
    local -a words=()
    local DEPTH=$((DEPTH+1))
    R=; C=0
    if ((DEPTH>64)); then fail 'evaluation depth exceeded'; END=$I; return; fi
    while ((I<N)); do
        ch=${S:I:1}
        case $ch in
            ' '|$'\t'|$'\r') I=$((I+1)); continue;;
            \\) if [[ ${S:I+1:1} == $'\n' ]]; then saved=$R; escape_char; R=$saved; continue; fi;;
            '#') if ((${#words[@]}==0)); then
                while ((I<N)) && [[ ${S:I:1} != $'\n' ]]; do
                    if [[ ${S:I:2} == $'\\\n' ]]; then I=$((I+2)); else I=$((I+1)); fi
                done
                continue
            fi;;
        esac
        if [[ $ch == ';' || $ch == $'\n' ]] || { ((B)) && [[ $ch == ']' ]]; }; then
            if ((${#words[@]})); then dispatch "${words[@]}"; words=(); fi
            I=$((I+1)); END=$I
            ((C)) && return
            if ((B)) && [[ $ch == ']' ]]; then return; fi
            continue
        fi
        parse_word; END=$I; ((C)) && return
        words+=("$R")
    done
    if ((B)); then fail 'missing close bracket'; END=$I; return; fi
    if ((${#words[@]})); then dispatch "${words[@]}"; fi
    END=$I
}
finish_return() {
    if ((C==2)); then
        RL=$((RL-1))
        if ((RL<=0)); then C=$RC; RC=0; RL=0; if ((C==2)); then RL=1; fi; fi
    fi
}
invoke_proc() {
    local idx=$1; shift
    local old=$F frame i n arg value variadic=0
    local -a formals=() names=() defaults=() optional=() actual=("$@") ITEMS=()
    parse_list "${PA[idx]}"; ((C)) && return; formals=("${ITEMS[@]}")
    for arg in "${formals[@]}"; do
        parse_list "$arg"; ((C)) && return
        n=${#ITEMS[@]}
        if ((n<1 || n>2)) || [[ -z ${ITEMS[0]} ]]; then fail 'invalid formal parameter'; return; fi
        names+=("${ITEMS[0]}"); defaults+=("${ITEMS[1]-}"); optional+=("$((n-1))")
    done
    NF=$((NF+1)); frame=$NF; PARENT[frame]=$old; F=$frame
    for ((i=0;i<${#names[@]};i++)); do
        if [[ ${names[i]} == args ]] && ((i==${#names[@]}-1)); then
            quote_list "${actual[@]:i}"; vset args "$R"; variadic=1; break
        fi
        if ((i<${#actual[@]})); then value=${actual[i]}
        elif ((optional[i])); then value=${defaults[i]}
        else arity 'procedure arguments'; break; fi
        vset "${names[i]}" "$value"
    done
    if ((C==0 && !variadic && ${#actual[@]}>${#names[@]})); then arity 'procedure arguments'; fi
    if ((C==0)); then eval_script "${PB[idx]}"; finish_return; fi
    F=$old
    local -a keepk=() keepv=()
    for ((i=0;i<${#VK[@]};i++)); do
        if [[ ${VK[i]} != "$frame:"* ]]; then keepk+=("${VK[i]}"); keepv+=("${VV[i]}"); fi
    done
    VK=("${keepk[@]}"); VV=("${keepv[@]}"); keepk=()
    for value in "${GK[@]}"; do [[ $value == "$frame:"* ]] || keepk+=("$value"); done
    GK=("${keepk[@]}"); unset 'PARENT[frame]'
}
dispatch() {
    local cmd=$1; shift
    local a b i j value code opts saveRC saveRL name out status path
    local -a ITEMS=() args=("$@")
    R=; C=0
    # Script procedures can override any command.
    for ((i=0;i<${#PN[@]};i++)); do
        if [[ ${PN[i]} == "$cmd" ]]; then invoke_proc "$i" "$@"; return; fi
    done
    for ((i=${#NN[@]}-1;i>=0;i--)); do
        if [[ ${NN[i]} == "$cmd" ]]; then "${NH[i]}" "$@"; return; fi
    done
    case $cmd in
        set) case $# in 1) vget "$1";; 2) vset "$1" "$2";; *) arity 'set name ?value?';; esac;;
        unset)
            if (($#!=1)); then arity 'unset name'; return; fi
            local KEY; vkey "$1"; ((C)) && return
            for ((i=0;i<${#VK[@]};i++)); do
                    if [[ ${VK[i]} == "$KEY" ]]; then
                        VK=("${VK[@]:0:i}" "${VK[@]:i+1}"); VV=("${VV[@]:0:i}" "${VV[@]:i+1}"); R=; return
                    fi
            done
            fail "no such variable: $1";;
        global)
            for name in "$@"; do
                [[ $name == ::* ]] && name=${name#::}
                GK+=("$F:$name")
            done;;
        proc)
            if (($#!=3)); then arity 'proc name arguments body'; return; fi
            parse_list "$2"; ((C)) && return
            for value in "${ITEMS[@]}"; do
                parse_list "$value"; ((C)) && return
                if ((${#ITEMS[@]}<1 || ${#ITEMS[@]}>2)) || [[ -z ${ITEMS[0]} || ${ITEMS[0]} == ::* ]]; then fail 'invalid formal parameter'; return; fi
            done
            for ((i=0;i<${#PN[@]};i++)); do [[ ${PN[i]} == "$1" ]] && break; done
            PN[i]=$1; PA[i]=$2; PB[i]=$3; R=;;
        eval) if (($#==1)); then eval_script "$1"; else arity 'eval script'; fi;;
        uplevel)
            if (($#!=2)); then arity 'uplevel level script'; return; fi
            a=$F
            if [[ $1 == '#0' ]]; then b=0
            else
                integer "$1"; ((C)) && return; j=$R; b=$F
                if ((j<0 || j>128)); then fail 'bad level'; return; fi
                while ((j>0)); do
                    if ((b==0)); then fail 'bad level'; return; fi
                    b=${PARENT[b]}; j=$((j-1))
                done
            fi
            F=$b; eval_script "$2"; F=$a;;
        catch)
            if (($#<1 || $#>3)); then arity 'catch script ?resultVar? ?optionsVar?'; return; fi
            eval_script "$1"; value=$R; code=$C; saveRC=$RC; saveRL=$RL; C=0; RC=0; RL=0
            if (($#>1)); then vset "$2" "$value"; ((C)) && return; fi
            if (($#>2)); then
                if ((code==2)); then opts="-code $saveRC -level $saveRL"; else opts="-code $code -level 0"; fi
                vset "$3" "$opts"; ((C)) && return
            fi
            R=$code;;
        return)
            code=0; a=1
            while (($#>1)); do
                case $1 in
                    -code) integer "$2"; ((C)) && return; code=$R;;
                    -level) integer "$2"; ((C)) && return; a=$R;;
                    *) arity 'return ?-code 0..4? ?-level n? ?value?'; return;;
                esac
                shift 2
            done
            if ((code<0 || code>4 || a<0 || a>128)); then fail 'invalid return options'; return; fi
            R=${1-}; RC=$code; RL=$a; C=2
            if ((a==0)); then C=$code; if ((C==2)); then RC=0; RL=1; fi; fi;;
        break|continue)
            if (($#)); then arity "$cmd"; return; fi
            if [[ $cmd == break ]]; then C=3; else C=4; fi;;
        error) if (($#==1)); then fail "$1"; else arity 'error message'; fi;;
        if)
            if (($#!=2 && $#!=4)) || { (($#==4)) && [[ $3 != else ]]; }; then arity 'if boolean body ?else body?'; return; fi
            truth "$1"; ((C)) && return
            if ((R)); then eval_script "$2"; elif (($#==4)); then eval_script "$4"; else R=; fi;;
        while)
            if (($#!=2)); then arity 'while testScript body'; return; fi
            while :; do
                eval_script "$1"; ((C)) && return
                truth "$R"; ((C)) && return
                if ((R==0)); then R=; return; fi
                eval_script "$2"
                case $C in 3) C=0; R=; return;; 4) C=0;; 0) ;; *) return;; esac
            done;;
        list) quote_list "$@";;
        llength|lindex)
            if { [[ $cmd == llength ]] && (($#!=1)); } || { [[ $cmd == lindex ]] && (($#!=2)); }; then arity "$cmd list ?index?"; return; fi
            parse_list "$1"; ((C)) && return
            if [[ $cmd == llength ]]; then R=${#ITEMS[@]}
            else integer "$2"; ((C)) && return; i=$R; if ((i<0 || i>=${#ITEMS[@]})); then R=; else R=${ITEMS[i]}; fi; fi;;
        string)
            case ${1-}:$# in
                length:2) R=${#2};;
                equal:3) if [[ $2 == "$3" ]]; then R=1; else R=0; fi;;
                range:4)
                    value=$2; integer "$3"; ((C)) && return; a=$R
                    integer "$4"; ((C)) && return; b=$R
                    ((a<0)) && a=0; ((b>=${#value})) && b=$((${#value}-1))
                    if ((b<a)); then R=; else R=${value:a:b-a+1}; fi;;
                *) arity 'string length value | equal a b | range value first last';;
            esac;;
        +|-|'*'|/|%|'<'|'<='|'>'|'>='|'=='|'!='|'!')
            if { [[ $cmd == '!' ]] && (($#!=1)); } || { [[ $cmd != '!' ]] && (($#!=2)); }; then arity "$cmd integers"; return; fi
            integer "$1"; ((C)) && return; a=$R
            if [[ $cmd == '!' ]]; then R=$((!a)); return; fi
            integer "$2"; ((C)) && return; b=$R
            case $cmd in
                +) R=$((a+b));; -) R=$((a-b));; '*') R=$((a*b));;
                /|%) if ((b==0)); then fail 'division by zero'; return; fi
                    if [[ $cmd == / ]]; then R=$((a/b)); else R=$((a%b)); fi;;
                '<') R=$((a<b));; '<=') R=$((a<=b));; '>') R=$((a>b));; '>=') R=$((a>=b));;
                '==') R=$((a==b));; '!=') R=$((a!=b));;
            esac
            if ((R < -2147483648 || R > 2147483647)); then fail 'integer overflow'; fi;;
        puts)
            if (($#==1)); then printf '%s\n' "$1"; R=
            elif (($#==2)) && [[ $1 == -nonewline ]]; then printf '%s' "$2"; R=
            else arity 'puts ?-nonewline? value'; fi;;
        source|readfile)
            if (($#!=1)); then arity "$cmd path"; return; fi
            if [[ ! -f $1 || ! -r $1 ]]; then fail "cannot read file: $1"; return; fi
            value=
            if IFS= read -r -d '' value < "$1"; then fail "NUL in text file: $1"; return; fi
            value=${value#$'\357\273\277'}
            # A leading UTF-8 BOM is permitted in script files only.
            if [[ $cmd == source ]]; then value=${value//$'\r\n'/$'\n'}; eval_script "$value"; finish_return; else R=$value; fi;;
        writefile)
            if (($#!=2)); then arity 'writefile path text'; return; fi
            if ! printf '%s' "$2" > "$1"; then fail "cannot write file: $1"; else R=; fi;;
        pwd) if (($#)); then arity pwd; else R=$PWD; fi;;
        cd) if (($#!=1)); then arity 'cd path'; elif builtin cd -- "$1"; then R=; else fail "cannot change directory: $1"; fi;;
        getenv)
            if (($#!=1)) || [[ ! $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then arity 'getenv name'; else R=${!1}; fi;;
        exec)
            if (($#<1)); then arity 'exec program ?arg ...?'; return; fi
            # type -P avoids Bash functions and builtins. Preserve trailing newlines.
            path=$(type -P -- "$1")
            if [[ -z $path || ! -x $path ]]; then fail "cannot execute: $1"; return; fi
            shift
            out=$("$path" "$@"; status=$?; printf '\034%s' "$status")
            status=${out##*$'\034'}; out=${out%$'\034'*}
            if ((status)); then fail "process exited with status $status"; return; fi
            if [[ $out == *$'\n' ]]; then out=${out%$'\n'}; out=${out%$'\r'}; fi
            R=$out;;
        *) fail "unknown command: $cmd";;
    esac
}
main() {
    if (($#<1)); then printf 'usage: bash sycol.sh script.tcl [args ...]\n' >&2; return 2; fi
    local script=$1 base=${BASH_SOURCE[0]%/*}; shift
    [[ $base == "${BASH_SOURCE[0]}" ]] && base=.
    quote_list "$@"; vset argv "$R"; vset argc "$#"; vset argv0 "$script"; vset sycol_host bash
    dispatch source "$base/lib/core.tcl"
    if ((C==0)); then dispatch source "$script"; fi
    if ((C)); then printf 'sycol: %s (completion %s)\n' "$R" "$C" >&2; return 1; fi
}
# The Bash file is also an embedding API: source it, then call main or eval_script.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; exit $?; fi
