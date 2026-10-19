#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
root=$PWD
engine=${SYCOL_BASH:-bash}
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-modules.XXXXXXXX")
cleanup() {
    # The exact unique fixture root is verified before recursive cleanup.
    case $temp in "${TMPDIR:-/tmp}/sycol-modules."*) rm -rf -- "$temp";; esac
}
trap cleanup EXIT
mkdir -p "$temp/.sycol/bin" "$temp/.sycol/lib/sub" "$temp/.sycol/lib-sibling" "$temp/.sycol/native/sub" "$temp/user" "$temp/extra-sdk" "$temp/extra-native"
mkdir -p "$temp/.sycol/lib/directory.tcl"
printf '%s\n' 'proc wrong.directory.fallback {} {}' > "$temp/user/directory.tcl"
cp .sycol/bin/sycol "$temp/.sycol/bin/"
cp .sycol/VERSION "$temp/.sycol/"
cp .sycol/native/*.sh "$temp/.sycol/native/"
cp .sycol/lib/*.tcl "$temp/.sycol/lib/"
cp tests/discovery.tcl "$temp/test.tcl"
printf '%s\n' 'proc fileless.path {name} { return "[pwd]/$name" }' >> "$temp/.sycol/lib/core.tcl"
cat > "$temp/.sycol/lib/sample.tcl" <<'EOF'
incr ::tcl_loads
proc replacement {} { return fallback }

EOF
cat > "$temp/.sycol/lib/pure.tcl" <<'EOF'
proc portable {} { return portable }

EOF
cat > "$temp/.sycol/lib/sub/nested.tcl" <<'EOF'
proc nested.native {} { return fallback }

EOF
cat > "$temp/.sycol/lib/space name.tcl" <<'EOF'
proc space.native {} { return fallback }

EOF
cat > "$temp/.sycol/lib/broken.tcl" <<'EOF'
error first-broken

EOF
cat > "$temp/.sycol/lib/bad-native.tcl" <<'EOF'
proc should.not.exist {} {}

EOF
cat > "$temp/.sycol/lib/rogue.tcl" <<'EOF'
error unrelated-sdk-was-loaded

EOF
cat > "$temp/user/files.tcl" <<'EOF'
proc user.files {} { return user }

EOF
cat > "$temp/user/sample.tcl" <<'EOF'
proc user.sample {} { return user }

EOF
cat > "$temp/user/library.tcl" <<'EOF'
proc library {} { return user }

EOF
cat > "$temp/user/extra.tcl" <<'EOF'
proc precedence {} { return user }

EOF
cat > "$temp/user/broken.tcl" <<'EOF'
error wrong-fallback

EOF
cat > "$temp/extra-sdk/extra.tcl" <<'EOF'
proc precedence {} { return sdk }

EOF
cat > "$temp/cwd-only.tcl" <<'EOF'
proc cwd.only {} { return cwd }

EOF
cat > "$temp/scope.tcl" <<'EOF'
set marker after

EOF
cat > "$temp/return.tcl" <<'EOF'
return returned
error unreachable

EOF
cat > "$temp/empty.tcl" <<'EOF'

EOF
cat > "$temp/.sycol/native/sample.sh" <<'EOF'
MODULE_LOADS=$(( ${MODULE_LOADS:-0}+1 ))
module_replacement() { R=native; }
module_loads() { R=$MODULE_LOADS; }
sy_register replacement module_replacement
sy_register native.loads module_loads
EOF
printf '%s\n' 'nested_native() { R=nested; }; sy_register nested.native nested_native' > "$temp/.sycol/native/sub/nested.sh"
printf '%s\n' 'space_native() { R=space; }; sy_register space.native space_native' > "$temp/.sycol/native/space name.sh"
printf '%s\n' 'FAIL_LOADS=$(( ${FAIL_LOADS:-0}+1 )); failed_loads() { R=$FAIL_LOADS; }; sy_register native.failed-loads failed_loads; return 1' > "$temp/.sycol/native/bad-native.sh"
printf '%s\n' 'proc secondary.native {} { return fallback }' > "$temp/extra-sdk/secondary.tcl"
printf '%s\n' 'secondary_native() { R=secondary; }; sy_register secondary.native secondary_native' > "$temp/extra-native/secondary.sh"
printf '%s\n' 'true' > "$temp/extra-native/bad-native.sh"
printf '%s\n' 'proc outsider {} {}' > "$temp/.sycol/lib-sibling/outsider.tcl"
printf '%s\n' 'outside_native() { R=wrong; }; sy_register outsider.native outside_native' > "$temp/.sycol/native/outsider.sh"
printf '%s\n' 'return 1' > "$temp/.sycol/native/unrelated.sh"
(cd -- "$temp"; "$engine" .sycol/bin/sycol test.tcl)
# Embedding captures defaults before cwd changes, and loads no Tcl SDK yet.
(
    set +e
    source "$temp/.sycol/bin/sycol" || exit 1
    [[ ${#PN[@]} == 0 ]] || exit 1
    vget ::sycol_version; [[ $C == 1 ]] || exit 1; C=0
    eval_script 'set n 1; incr n; append n x; lappend items $n; concat $items'
    [[ $C == 0 && $R == 2x && ${#PN[@]} == 0 ]] || exit 1
    load_sdk
    [[ $C == 0 && ${#PN[@]} -gt 0 ]] || exit 1
    eval_script 'incr n 0'
    [[ $C == 1 && $R == 'expected integer: 2x' ]] || exit 1
    C=0
    for promoted in incr append concat lappend; do
        dispatch proc "$promoted" args 'return hidden'
    done
    eval_script 'set n 1; incr n; append n x; lappend items z; concat $items'
    [[ $C == 0 && $R == '2x z' ]] || exit 1
    eval_script 'set n 0; incr n invalid'
    [[ $C == 1 && $R == 'expected integer: invalid' ]] || exit 1
    C=0
    load_sdk; load_sdk
    [[ $C == 0 ]] || exit 1
    replacement() { R=replaced; }
    for promoted in incr append concat lappend; do
        sy_register "$promoted" replacement
        dispatch "$promoted"
        [[ $C == 0 && $R == replaced ]] || exit 1
    done
    builtin cd -- "$root" || exit 1
    main "$temp/empty.tcl"
) || exit 1
# Environment overrides replace defaults and accept multiple directories/spaces.
mkdir -p "$temp/override sdk" "$temp/override native"
cp "$temp/.sycol/lib/core.tcl" "$temp/override sdk/"
cp "$temp/.sycol/native/core.sh" "$temp/override native/"
printf '%s\n' 'proc from.environment {} {return yes}' > "$temp/user/env.tcl"
printf '%s\n' 'source env.tcl; puts [from.environment]' > "$temp/env-main.tcl"
separator=:
case ${OSTYPE-} in msys*|cygwin*) separator=';';; esac
SYCOL_SDK_PATH="$temp/missing${separator}$temp/override sdk" SYCOL_NATIVE_PATH="$temp/missing${separator}$temp/override native" SYCOL_SOURCE_PATH="$temp/user" \
    "$engine" .sycol/bin/sycol "$temp/env-main.tcl" > "$temp/output"
[[ $(< "$temp/output") == yes ]]
printf '%s\n' 'error core-broken' > "$temp/.sycol/lib/core.tcl"
if "$engine" "$temp/.sycol/bin/sycol" "$temp/empty.tcl" > "$temp/output" 2>&1; then exit 1; fi
[[ $(< "$temp/output") == *core-broken* ]]
rm -- "$temp/.sycol/lib/core.tcl"
if "$engine" "$temp/.sycol/bin/sycol" "$temp/empty.tcl" > "$temp/output" 2>&1; then exit 1; fi
[[ $(< "$temp/output") == *'cannot find SDK file: core.tcl'* ]]
rm -- "$temp/.sycol/native/core.sh"
if "$engine" "$temp/.sycol/bin/sycol" "$temp/empty.tcl" > "$temp/output" 2>&1; then exit 1; fi
[[ $(< "$temp/output") == *'cannot find native file: core.sh'* ]]
printf '%s\n' 'library lifecycle tests passed'
