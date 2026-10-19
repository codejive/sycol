#!/usr/bin/env bash
# Embedding launcher used only by the tests; normal Sycol has no timer command.
source tests/timing.sh
timing_measure phase "$1/native-load" source .sycol/bin/sycol
timing_test() {
    if (($#!=2)); then arity 'test.time name script'; return; fi
    timing_measure test "$1" eval_script "$2"
}
timing_source() {
    if [[ $# == 1 && ( $1 == "$SYCOL_HOME/../lib/"* || $1 == "${SYCOL_HOME%/*}/lib/"* || $1 == files.tcl ) ]]; then
        timing_measure phase "$timing_script/sdk/${1##*/}" sy_cmd_source "$@"
    else sy_cmd_source "$@"; fi
}
timing_script=$1
sy_register test.time timing_test
sy_register source timing_source
main "$@"
exit $?
