#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
root=$PWD
engine=${SYCOL_BASH:-bash}
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-discovery.XXXXXXXX")
cleanup() {
    rm -f -- "$temp"/lib/native/nested/* "$temp"/lib/sdk/nested/*
    rmdir -- "$temp/lib/native/nested" "$temp/lib/sdk/nested"
    rm -f -- "$temp"/lib/native/* "$temp"/lib/sdk/* "$temp/lib/native/.hidden.sh" "$temp/lib/sdk/.hidden.tcl" "$temp/sycol" "$temp/test.tcl" "$temp/empty.tcl" "$temp/output"
    rmdir -- "$temp/lib/native" "$temp/lib/sdk" "$temp/lib" "$temp"
}
trap cleanup EXIT
mkdir -p "$temp/lib/native/nested" "$temp/lib/sdk/nested"
cp sycol "$temp/sycol"
# No hard-coded core filename, including for native discovery.
cp lib/native/core.sh "$temp/lib/native/builtins.sh"
cp lib/sdk/*.tcl "$temp/lib/sdk/"
cp tests/discovery.tcl "$temp/test.tcl"
: > "$temp/empty.tcl"
# Create reverse filename order to expose reliance on directory enumeration.
cat > "$temp/lib/native/z-last.sh" <<'EOF'
native_last() { R=last; }
native_echo() { quote_list "$@"; }
native_override() { R=overridden; }
sy_register native.order native_last
sy_register native.echo native_echo
sy_register getenv native_override
EOF
cat > "$temp/lib/native/a-first.sh" <<'EOF'
native_first() { R=first; }
sy_register native.order native_first
EOF
printf '%s\n' 'proc sdk.order {} { return last }' > "$temp/lib/sdk/z-last.tcl"
printf '%s\n' 'proc sdk.order {} { return first }' > "$temp/lib/sdk/a-first.tcl"
for file in "$temp/lib/native/.hidden.sh" "$temp/lib/native/ignored.SH" "$temp/lib/native/wrong.ps1" "$temp/lib/native/nested/ignored.sh"; do
    printf '%s\n' 'return 1' > "$file"
done
for file in "$temp/lib/sdk/.hidden.tcl" "$temp/lib/sdk/ignored.TCL" "$temp/lib/sdk/wrong.sh" "$temp/lib/sdk/nested/ignored.tcl"; do
    printf '%s\n' 'error ignored-file-was-loaded' > "$file"
done
# Source the interpreter, then change cwd before starting it.
(
    set +e
    builtin cd -- "$temp" || exit 1
    source ./sycol || exit 1
    dispatch incr n
    [[ $C == 1 && $R == 'unknown command: incr' ]] || exit 1
    embedding_override() { R=embedded; }
    sy_register native.order embedding_override
    dispatch native.order
    [[ $C == 0 && $R == embedded ]] || exit 1
    builtin cd -- "$root" || exit 1
    main "$root/examples/hello.tcl" > "$temp/output"
) || { printf '%s\n' 'embedding lifecycle failed' >&2; exit 1; }
(cd -- "$temp"; "$engine" ./sycol test.tcl)
# A malformed SDK must stop startup before the requested script runs.
printf '%s\n' 'error sdk-broken' > "$temp/lib/sdk/0-broken.tcl"
if "$engine" "$temp/sycol" "$root/examples/hello.tcl" > "$temp/output" 2>&1; then exit 1; fi
[[ $(< "$temp/output") == *'0-broken.tcl: sdk-broken'* ]] || exit 1
[[ $(< "$temp/output") != *'Hello, world!'* ]] || exit 1
rm -- "$temp/lib/sdk/0-broken.tcl"
printf '%s\n' 'return 1' > "$temp/lib/native/0-broken.sh"
if "$engine" "$temp/sycol" "$temp/empty.tcl" > "$temp/output" 2>&1; then exit 1; fi
[[ $(< "$temp/output") == *'cannot load native file:'*'0-broken.sh'* ]] || exit 1
rm -- "$temp/lib/native/0-broken.sh"
# Empty discovery sets are valid: no unmatched glob is sourced.
rm -- "$temp"/lib/sdk/*.tcl
"$engine" "$temp/sycol" "$temp/empty.tcl"
rm -- "$temp"/lib/native/*.sh
"$engine" -c 'source "$1"' _ "$temp/sycol"
# Missing library directories are errors, unlike existing empty directories.
(
    source "$temp/sycol"
    if library_files "$temp/missing" .tcl; then exit 1; fi
    [[ $C == 1 && $R == "cannot read library directory: $temp/missing" ]]
)
printf '%s\n' 'library lifecycle tests passed'
