#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
root=$PWD
engine=${SYCOL_BASH:-bash}
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-tests.XXXXXXXX")
trap 'rm -rf -- "$temp/filesystem"; rm -f -- "$temp/round trip.txt"; rmdir -- "$temp"' EXIT
mkdir -p "$root/.test-tmp"
cross=$(mktemp -d "$root/.test-tmp/sycol-cross.XXXXXXXX")
case $cross in "$root/.test-tmp/"*) ;; *) exit 1;; esac
trap 'rm -rf -- "$temp/filesystem" "$temp/move-source" "$cross"; rm -f -- "$temp/round trip.txt"; rmdir -- "$temp"' EXIT
mkdir -p "$temp/filesystem/source/nested" "$temp/filesystem/empty"
printf payload > "$temp/filesystem/source/a ; [literal].txt"
printf hidden > "$temp/filesystem/source/.hidden"
touch -t 202001020304.05 "$temp/filesystem/source/.hidden"
printf child > "$temp/filesystem/source/nested/child"
printf old > "$temp/filesystem/readonly-target"
printf old > "$temp/filesystem/readonly-file"
chmod a-w "$temp/filesystem/readonly-target" "$temp/filesystem/readonly-file"
links=0
if ln -s source "$temp/filesystem/link" && ln -s missing "$temp/filesystem/dangling" && ln -s source/.hidden "$temp/filesystem/file-link"; then links=1
else printf '%s\n' 'Symbolic link tests unavailable: host does not permit link creation'; fi
"$engine" ./.sycol/bin/sycol tests/all.tcl "$temp" 'argument with spaces; $literal [brackets]' "$links"
if [[ "$temp/filesystem/source/.hidden" -nt "$temp/filesystem/attributes-copy" || "$temp/filesystem/attributes-copy" -nt "$temp/filesystem/source/.hidden" ]]; then
    printf '%s\n' 'copy did not preserve modification time' >&2; exit 1
fi
if [[ "$temp/filesystem/source" -nt "$temp/filesystem/attributes-dir" || "$temp/filesystem/attributes-dir" -nt "$temp/filesystem/source" ]]; then
    printf '%s\n' 'copy did not preserve directory modification time' >&2; exit 1
fi
from_device=$(stat -c %d "$temp" 2>/dev/null || stat -f %d "$temp")
to_device=$(stat -c %d "$cross" 2>/dev/null || stat -f %d "$cross")
if [[ $from_device != "$to_device" ]]; then printf '%s\n' 'Testing rename across filesystems'
else printf '%s\n' 'Cross-filesystem rename unavailable: fixture roots share a filesystem'; fi
"$engine" ./.sycol/bin/sycol tests/files-move.tcl "$temp" "$cross"
# Build the probe prefix as a Sycol list using the interpreter's own encoder.
source ./.sycol/bin/sycol
host_echo() { if (($#!=1)); then arity 'host.echo value'; return; fi; R=$1; C=0; }
sy_register host.echo host_echo
dispatch source tests/native.tcl
if ((C)); then printf '%s\n' "$R" >&2; exit 1; fi
quote_list "$(command -v "$engine")" "$root/tests/fixtures/probe.sh"
probe=$R
"$engine" ./.sycol/bin/sycol tests/exec.tcl "$probe" "$temp"
"$engine" tests/discovery.sh
"$engine" tests/encoding.sh
"$engine" tests/launchers.sh
