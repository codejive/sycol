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
printf '' > "$temp/empty.tcl"
printf '\357\273\277' > "$temp/bom-empty.tcl"
printf '%s\r\n\n\n' "$text" > "$temp/trailing.tcl"
printf 'set ::encoding_side_effect changed\000error hidden' > "$temp/nul.tcl"
printf '%s\000' "$text" > "$temp/nul-end.tcl"
printf 'return [string length {%s}]\n' "$text" > "$temp/locale.tcl"
"$engine" .sycol/bin/sycol tests/encoding.tcl "$temp" "$text"
