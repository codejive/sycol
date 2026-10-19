#!/usr/bin/env bash
# Optional, non-gating timings. Pass another interpreter file for comparisons.
cd -- "${BASH_SOURCE[0]%/*}/.." || exit 1
runtime=${1:-.sycol/bin/sycol}
engine=${SYCOL_BASH:-bash}
source "$runtime" || exit 1
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-benchmark.XXXXXXXX") || exit 1
trap 'rm -f -- "$temp/data.txt"; rmdir -- "$temp"' EXIT
printf -v text '%*s' 16384 ''; text=${text// /x}
printf '%s%s%s%s' "$text" "$text" "$text" "$text" > "$temp/data.txt"
TIMEFORMAT='%3R'
measure() {
    local label=$1 repeats=$2 iteration elapsed; shift 2
    elapsed=$({ time {
        for ((iteration=0;iteration<repeats;iteration++)); do
            "$@" > /dev/null || { printf 'benchmark host command failed\n' >&2; exit 1; }
            if ((C)); then printf 'benchmark failed: %s\n' "$R" >&2; exit 1; fi
        done
    }; } 2>&1) || { printf '%s\n' "$elapsed" >&2; exit 1; }
    printf '%-28s %s s / %s runs\n' "$label" "$elapsed" "$repeats"
}
printf 'Bash %s; locale %s; runtime %s\n' "$BASH_VERSION" "${LC_ALL:-${LANG:-unset}}" "$runtime"
measure 'readfile 64 KiB' 5 sy_cmd_readfile "$temp/data.txt"
measure 'load SDK' 5 load_sdk
# measure captures timing in a subshell, so its SDK definitions do not persist.
load_sdk
if ((C)); then printf 'benchmark failed: %s\n' "$R" >&2; exit 1; fi
dispatch source files.tcl
measure 'file exists (SDK)' 5 eval_script 'file exists .sycol/VERSION'
measure 'file invalid prefix (SDK)' 5 eval_script 'catch {file c a b}'
measure 'pathtype long path (SDK)' 5 eval_script 'file pathtype relative/long-temporary-directory/another-segment/filesystem'
measure 'file join long path (SDK)' 3 eval_script 'file join C:/sycol-benchmark/long-temporary-directory/another-segment/filesystem child'
measure 'Windows path split (SDK)' 3 eval_script 'sy.path.parts {C:\sycol-benchmark\long-temporary-directory\another-segment\filesystem} 1'
measure 'startup + hello example' 5 "$engine" "$runtime" examples/hello.tcl
measure 'parse bare 16 KiB' 3 eval_script "set value $text"
measure 'parse quoted 16 KiB' 3 eval_script "set value \"$text\""
measure 'parse braced 16 KiB' 3 eval_script "set value {$text}"
measure 'parse comment 16 KiB' 3 eval_script "#$text"
measure 'parse list 16 KiB' 3 parse_list "$text"
measure 'encode list 16 KiB' 3 quote_list "$text"
