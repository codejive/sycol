#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
engine=${SYCOL_BASH:-bash}
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-encoding.XXXXXXXX")
trap 'rm -f -- "$temp"/*.tcl; rmdir -- "$temp"' EXIT
# UTF-8 scalar boundaries, including two-, three-, and four-byte characters.
text=$'\302\200\337\277\340\240\200\355\237\277\356\200\200\357\277\277\360\220\200\200\364\217\277\277'
printf 'return {%s}\r\n' "$text" > "$temp/plain.tcl"
printf '\357\273\277return {%s}\r\n' "$text" > "$temp/bom.tcl"
"$engine" .sycol/bin/sycol tests/encoding.tcl "$temp" "$text"
