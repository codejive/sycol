#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
root=$PWD
engine=${SYCOL_BASH:-bash}
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-launchers.XXXXXXXX")
cleanup() {
    rm -f -- "$temp/expected" "$temp/actual" "$temp/version.tcl" "$temp/install with spaces/.sycol/VERSION"
    rm -f -- "$temp/install with spaces/.sycol/bin/sycol" "$temp/install with spaces/.sycol/native/"* "$temp/install with spaces/.sycol/sdk/"* "$temp/install with spaces/sycol"
    rmdir -- "$temp/install with spaces/.sycol/bin" "$temp/install with spaces/.sycol/native" "$temp/install with spaces/.sycol/sdk" "$temp/install with spaces/.sycol" "$temp/install with spaces" "$temp"
}
trap cleanup EXIT
mkdir -p "$temp/install with spaces/.sycol/bin" "$temp/install with spaces/.sycol/native" "$temp/install with spaces/.sycol/sdk"
cp sycol "$temp/install with spaces/sycol"
cp .sycol/bin/sycol "$temp/install with spaces/.sycol/bin/sycol"
cp .sycol/VERSION "$temp/install with spaces/.sycol/VERSION"
cp .sycol/native/* "$temp/install with spaces/.sycol/native/"
cp .sycol/sdk/* "$temp/install with spaces/.sycol/sdk/"
# Source the implementation to encode the expected list, not the root launcher.
source ./.sycol/bin/sycol
arguments=('' 'two words' 'say "hello"' 'tail\' 'a&b|c<d>e(f)^g!h' '$literal;[brackets]' '100%' '--version')
quote_list "${arguments[@]}"
printf '%s\n' "${#arguments[@]}" "$root/tests/fixtures/argv.tcl" "$R" > "$temp/expected"
builtin cd -- "$temp"
for launcher in "$temp/install with spaces/sycol" "$root/.sycol/bin/sycol"; do
    "$engine" "$launcher" "$root/tests/fixtures/argv.tcl" "${arguments[@]}" > "$temp/actual"
    cmp "$temp/expected" "$temp/actual"
    if "$engine" "$launcher" > "$temp/actual" 2>&1; then exit 1; else [[ $? == 2 ]]; fi
    if "$engine" "$launcher" missing.tcl > "$temp/actual" 2>&1; then exit 1; else [[ $? == 1 ]]; fi
done
# exit terminates through catch, procedures, and source, without diagnostics.
for body in 'exit' 'proc stop {} { exit 37 }; catch {stop}; error unreachable' 'exit 255'; do
    printf '%s\n' "$body" > "$temp/version.tcl"
    expected=0
    [[ $body == *37* ]] && expected=37
    [[ $body == *255* ]] && expected=255
    for launcher in "$temp/install with spaces/sycol" "$root/.sycol/bin/sycol"; do
        status=0
        "$engine" "$launcher" "$temp/version.tcl" > "$temp/actual" 2>&1 || status=$?
        [[ $status == "$expected" && ! -s $temp/actual ]]
    done
done
# A copied distribution owns its release version, independent of cwd or SDK.
printf '%s\n' '9.8.7-test+build' > "$temp/install with spaces/.sycol/VERSION"
printf '%s\n' 'puts $::sycol_version' > "$temp/version.tcl"
printf '%s\n' '9.8.7-test+build' > "$temp/expected"
for query in --version "$temp/version.tcl"; do
    "$engine" "$temp/install with spaces/sycol" "$query" > "$temp/actual"
    cmp "$temp/expected" "$temp/actual"
done
if "$engine" "$temp/install with spaces/sycol" --version extra > "$temp/actual" 2>&1; then exit 1; else [[ $? == 2 ]]; fi
# Version queries do not evaluate SDK files.
printf '%s\n' 'error version-must-not-load-sdk' > "$temp/install with spaces/.sycol/sdk/0-broken.tcl"
"$engine" "$temp/install with spaces/sycol" --version > "$temp/actual"
cmp "$temp/expected" "$temp/actual"
for value in '' 'invalid version'; do
    printf '%s\n' "$value" > "$temp/install with spaces/.sycol/VERSION"
    if "$engine" "$temp/install with spaces/sycol" --version > "$temp/actual" 2>&1; then exit 1; else [[ $? == 1 ]]; fi
    [[ $(< "$temp/actual") == 'sycol: invalid version file (completion 1)' ]]
done
rm -- "$temp/install with spaces/.sycol/VERSION"
if "$engine" "$temp/install with spaces/sycol" --version > "$temp/actual" 2>&1; then exit 1; else [[ $? == 1 ]]; fi
[[ $(< "$temp/actual") == 'sycol: cannot read version file (completion 1)' ]]
cp "$root/.sycol/VERSION" "$temp/install with spaces/.sycol/VERSION"
rm -- "$temp/install with spaces/.sycol/sdk/0-broken.tcl"
quote_list "${arguments[@]}"
printf '%s\n' "${#arguments[@]}" "$root/tests/fixtures/argv.tcl" "$R" > "$temp/expected"
# Exercise shebang execution and command lookup for both PATH entry points.
for directory in "$temp/install with spaces" "$root/.sycol/bin"; do
    PATH="$directory:$PATH" sycol "$root/tests/fixtures/argv.tcl" "${arguments[@]}" > "$temp/actual"
    cmp "$temp/expected" "$temp/actual"
done
printf '%s\n' 'launcher argument and exit status tests passed'
