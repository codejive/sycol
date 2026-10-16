#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
root=$PWD
engine=${SYCOL_BASH:-bash}
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-tests.XXXXXXXX")
trap 'rm -f -- "$temp/round trip.txt"; rmdir -- "$temp"' EXIT
"$engine" ./sycol tests/all.tcl "$temp" 'argument with spaces; $literal [brackets]'
# Build the probe prefix as a Sycol list using the interpreter's own encoder.
source ./sycol
host_echo() { if (($#!=1)); then arity 'host.echo value'; return; fi; R=$1; C=0; }
sy_register host.echo host_echo
dispatch source tests/native.tcl
if ((C)); then printf '%s\n' "$R" >&2; exit 1; fi
quote_list "$(command -v "$engine")" "$root/tests/fixtures/probe.sh"
probe=$R
"$engine" ./sycol tests/exec.tcl "$probe" "$temp"
"$engine" tests/discovery.sh
