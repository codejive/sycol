# Built-in native handlers. Loaded by discovery; no Sycol code runs here.

sy_cmd_set() {
    case $# in 1) vget "$1";; 2) vset "$1" "$2";; *) arity 'set name ?value?';; esac
}
sy_register 'set' sy_cmd_set

sy_cmd_unset() {
    local i KEY
    if (($#!=1)); then arity 'unset name'; return; fi
    vkey "$1"; ((C)) && return
    for ((i=0;i<${#VK[@]};i++)); do
        if [[ ${VK[i]} == "$KEY" ]]; then
            VK=("${VK[@]:0:i}" "${VK[@]:i+1}"); VV=("${VV[@]:0:i}" "${VV[@]:i+1}"); R=; return
        fi
    done
    fail "no such variable: $1"
}
sy_register 'unset' sy_cmd_unset

sy_cmd_global() {
    local name
    for name in "$@"; do
        [[ $name == ::* ]] && name=${name#::}
        GK+=("$F:$name")
    done
}
sy_register 'global' sy_cmd_global

sy_cmd_proc() {
    local i value
    local -a ITEMS=()
    if (($#!=3)); then arity 'proc name arguments body'; return; fi
    parse_list "$2"; ((C)) && return
    for value in "${ITEMS[@]}"; do
        parse_list "$value"; ((C)) && return
        if ((${#ITEMS[@]}<1 || ${#ITEMS[@]}>2)) || [[ -z ${ITEMS[0]} || ${ITEMS[0]} == ::* ]]; then fail 'invalid formal parameter'; return; fi
    done
    for ((i=0;i<${#PN[@]};i++)); do [[ ${PN[i]} == "$1" ]] && break; done
    PN[i]=$1; PA[i]=$2; PB[i]=$3; R=
}
sy_register 'proc' sy_cmd_proc

sy_cmd_eval() {
    if (($#==1)); then eval_script "$1"; else arity 'eval script'; fi
}
sy_register 'eval' sy_cmd_eval

sy_cmd_uplevel() {
    local a b j
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
    F=$b; eval_script "$2"; F=$a
}
sy_register 'uplevel' sy_cmd_uplevel

sy_cmd_catch() {
    local code opts saveRC saveRL value
    if (($#<1 || $#>3)); then arity 'catch script ?resultVar? ?optionsVar?'; return; fi
    eval_script "$1"; value=$R; code=$C; saveRC=$RC; saveRL=$RL; C=0; RC=0; RL=0
    if (($#>1)); then vset "$2" "$value"; ((C)) && return; fi
    if (($#>2)); then
        if ((code==2)); then opts="-code $saveRC -level $saveRL"; else opts="-code $code -level 0"; fi
        vset "$3" "$opts"; ((C)) && return
    fi
    R=$code
}
sy_register 'catch' sy_cmd_catch

sy_cmd_return() {
    local a code
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
    if ((a==0)); then C=$code; if ((C==2)); then RC=0; RL=1; fi; fi
}
sy_register 'return' sy_cmd_return

sy_cmd_flow() {
    local cmd=$1; shift
    if (($#)); then arity "$cmd"; return; fi
    if [[ $cmd == break ]]; then C=3; else C=4; fi
}
sy_cmd_break() { sy_cmd_flow 'break' "$@"; }
sy_register 'break' sy_cmd_break
sy_cmd_continue() { sy_cmd_flow 'continue' "$@"; }
sy_register 'continue' sy_cmd_continue

sy_cmd_error() {
    if (($#==1)); then fail "$1"; else arity 'error message'; fi
}
sy_register 'error' sy_cmd_error

sy_cmd_if() {
    if (($#!=2 && $#!=4)) || { (($#==4)) && [[ $3 != else ]]; }; then arity 'if boolean body ?else body?'; return; fi
    truth "$1"; ((C)) && return
    if ((R)); then eval_script "$2"; elif (($#==4)); then eval_script "$4"; else R=; fi
}
sy_register 'if' sy_cmd_if

sy_cmd_while() {
    if (($#!=2)); then arity 'while testScript body'; return; fi
    while :; do
        eval_script "$1"; ((C)) && return
        truth "$R"; ((C)) && return
        if ((R==0)); then R=; return; fi
        eval_script "$2"
        case $C in 3) C=0; R=; return;; 4) C=0;; 0) ;; *) return;; esac
    done
}
sy_register 'while' sy_cmd_while

sy_cmd_list() {
    quote_list "$@"
}
sy_register 'list' sy_cmd_list

sy_cmd_list_index() {
    local cmd=$1; shift
    local i
    local -a ITEMS=()
    if { [[ $cmd == llength ]] && (($#!=1)); } || { [[ $cmd == lindex ]] && (($#!=2)); }; then arity "$cmd list ?index?"; return; fi
    parse_list "$1"; ((C)) && return
    if [[ $cmd == llength ]]; then R=${#ITEMS[@]}
    else integer "$2"; ((C)) && return; i=$R; if ((i<0 || i>=${#ITEMS[@]})); then R=; else R=${ITEMS[i]}; fi; fi
}
sy_cmd_llength() { sy_cmd_list_index 'llength' "$@"; }
sy_register 'llength' sy_cmd_llength
sy_cmd_lindex() { sy_cmd_list_index 'lindex' "$@"; }
sy_register 'lindex' sy_cmd_lindex

sy_cmd_string() {
    local a b value
    case ${1-}:$# in
        length:2) R=${#2};;
        equal:3) if [[ $2 == "$3" ]]; then R=1; else R=0; fi;;
        range:4)
            value=$2; integer "$3"; ((C)) && return; a=$R
            integer "$4"; ((C)) && return; b=$R
            ((a<0)) && a=0; ((b>=${#value})) && b=$((${#value}-1))
            if ((b<a)); then R=; else R=${value:a:b-a+1}; fi;;
        *) arity 'string length value | equal a b | range value first last';;
    esac
}
sy_register 'string' sy_cmd_string

sy_cmd_math() {
    local cmd=$1; shift
    local a b
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
    if ((R < -2147483648 || R > 2147483647)); then fail 'integer overflow'; fi
}
sy_cmd_add() { sy_cmd_math '+' "$@"; }
sy_register '+' sy_cmd_add
sy_cmd_subtract() { sy_cmd_math '-' "$@"; }
sy_register '-' sy_cmd_subtract
sy_cmd_multiply() { sy_cmd_math '*' "$@"; }
sy_register '*' sy_cmd_multiply
sy_cmd_divide() { sy_cmd_math '/' "$@"; }
sy_register '/' sy_cmd_divide
sy_cmd_remainder() { sy_cmd_math '%' "$@"; }
sy_register '%' sy_cmd_remainder
sy_cmd_lt() { sy_cmd_math '<' "$@"; }
sy_register '<' sy_cmd_lt
sy_cmd_le() { sy_cmd_math '<=' "$@"; }
sy_register '<=' sy_cmd_le
sy_cmd_gt() { sy_cmd_math '>' "$@"; }
sy_register '>' sy_cmd_gt
sy_cmd_ge() { sy_cmd_math '>=' "$@"; }
sy_register '>=' sy_cmd_ge
sy_cmd_equal() { sy_cmd_math '==' "$@"; }
sy_register '==' sy_cmd_equal
sy_cmd_unequal() { sy_cmd_math '!=' "$@"; }
sy_register '!=' sy_cmd_unequal
sy_cmd_not() { sy_cmd_math '!' "$@"; }
sy_register '!' sy_cmd_not

sy_cmd_puts() {
    if (($#==1)); then printf '%s\n' "$1"; R=
    elif (($#==2)) && [[ $1 == -nonewline ]]; then printf '%s' "$2"; R=
    else arity 'puts ?-nonewline? value'; fi
}
sy_register 'puts' sy_cmd_puts

sy_read_text() {
    # Byte operations here must not change the locale used by sourced code.
    local LC_ALL=C value
    if [[ ! -f $1 || ! -r $1 ]]; then fail "cannot read file: $1"; return; fi
    value=
    if IFS= read -r -d '' value < "$1"; then fail "NUL in text file: $1"; return; fi
    # Accept a leading UTF-8 BOM for both source and readfile.
    # Prefix removal with ${value#pattern} tries successively longer prefixes
    # even when the BOM is absent. Test three bytes and slice only on a match.
    if [[ ${value:0:3} == $'\357\273\277' ]]; then value=${value:3}; fi
    R=$value
}
sy_cmd_read() {
    local cmd=$1; shift
    if (($#!=1)); then arity "$cmd path"; return; fi
    sy_read_text "$1"; ((C)) && return
    if [[ $cmd == source ]]; then R=${R//$'\r\n'/$'\n'}; eval_script "$R"; finish_return; fi
}
sy_cmd_source() { sy_cmd_read 'source' "$@"; }
sy_register 'source' sy_cmd_source
sy_cmd_readfile() { sy_cmd_read 'readfile' "$@"; }
sy_register 'readfile' sy_cmd_readfile

sy_cmd_writefile() {
    if (($#!=2)); then arity 'writefile path text'; return; fi
    if ! printf '%s' "$2" > "$1"; then fail "cannot write file: $1"; else R=; fi
}
sy_register 'writefile' sy_cmd_writefile

sy_cmd_pwd() {
    if (($#)); then arity pwd; else R=$PWD; fi
}
sy_register 'pwd' sy_cmd_pwd

sy_cmd_cd() {
    if (($#!=1)); then arity 'cd path'; elif builtin cd -- "$1"; then R=; else fail "cannot change directory: $1"; fi
}
sy_register 'cd' sy_cmd_cd

sy_cmd_getenv() {
    if (($#!=1)) || [[ ! $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then arity 'getenv name'; else R=${!1}; fi
}
sy_register 'getenv' sy_cmd_getenv

sy_cmd_exec() {
    local out path status
    if (($#<1)); then arity 'exec program ?arg ...?'; return; fi
    # type -P avoids Bash functions and builtins. Preserve trailing newlines.
    path=$(type -P -- "$1")
    if [[ -z $path || ! -x $path ]]; then fail "cannot execute: $1"; return; fi
    shift
    out=$("$path" "$@"; status=$?; printf '\034%s' "$status")
    status=${out##*$'\034'}; out=${out%$'\034'*}
    if ((status)); then fail "process exited with status $status"; return; fi
    if [[ $out == *$'\n' ]]; then out=${out%$'\n'}; out=${out%$'\r'}; fi
    R=$out
}
sy_register 'exec' sy_cmd_exec

sy_cmd_exit() {
    if (($#>1)); then arity 'exit ?status?'; return; fi
    integer "${1-0}"; ((C)) && return
    if ((R<0 || R>255)); then fail 'exit status must be 0..255'; return; fi
    exit "$R"
}
sy_register 'exit' sy_cmd_exit
