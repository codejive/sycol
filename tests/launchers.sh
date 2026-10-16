#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
root=$PWD
engine=${SYCOL_BASH:-bash}
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-launchers.XXXXXXXX")
cleanup() {
    rm -f -- "$temp/expected" "$temp/actual"
    rm -f -- "$temp/install with spaces/.sycol/bin/sycol" "$temp/install with spaces/.sycol/native/"* "$temp/install with spaces/.sycol/sdk/"* "$temp/install with spaces/sycol"
    rmdir -- "$temp/install with spaces/.sycol/bin" "$temp/install with spaces/.sycol/native" "$temp/install with spaces/.sycol/sdk" "$temp/install with spaces/.sycol" "$temp/install with spaces" "$temp"
}
trap cleanup EXIT
mkdir -p "$temp/install with spaces/.sycol/bin" "$temp/install with spaces/.sycol/native" "$temp/install with spaces/.sycol/sdk"
cp sycol "$temp/install with spaces/sycol"
cp .sycol/bin/sycol "$temp/install with spaces/.sycol/bin/sycol"
cp .sycol/native/* "$temp/install with spaces/.sycol/native/"
cp .sycol/sdk/* "$temp/install with spaces/.sycol/sdk/"
# Source the implementation to encode the expected list, not the root launcher.
source ./.sycol/bin/sycol
arguments=('' 'two words' 'say "hello"' 'tail\' 'a&b|c<d>e(f)^g!h' '$literal;[brackets]' '100%')
quote_list "${arguments[@]}"
printf '%s\n' "${#arguments[@]}" "$root/tests/fixtures/argv.tcl" "$R" > "$temp/expected"
builtin cd -- "$temp"
for launcher in "$temp/install with spaces/sycol" "$root/.sycol/bin/sycol"; do
    "$engine" "$launcher" "$root/tests/fixtures/argv.tcl" "${arguments[@]}" > "$temp/actual"
    cmp "$temp/expected" "$temp/actual"
    if "$engine" "$launcher" > "$temp/actual" 2>&1; then exit 1; else [[ $? == 2 ]]; fi
    if "$engine" "$launcher" missing.tcl > "$temp/actual" 2>&1; then exit 1; else [[ $? == 1 ]]; fi
done
# Exercise shebang execution and command lookup for both PATH entry points.
for directory in "$temp/install with spaces" "$root/.sycol/bin"; do
    PATH="$directory:$PATH" sycol "$root/tests/fixtures/argv.tcl" "${arguments[@]}" > "$temp/actual"
    cmp "$temp/expected" "$temp/actual"
done
printf '%s\n' 'launcher argument and exit status tests passed'
