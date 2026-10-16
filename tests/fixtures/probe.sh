#!/usr/bin/env bash
mode=$1; shift
case $mode in
    args) for arg in "$@"; do printf '<%s>' "$arg"; done; printf '\n';;
    newlines) printf 'line\n\n';;
    carriage) printf 'line\r';;
    fail) printf 'diagnostic\n' >&2; exit 7;;
    capture) printf 'out ; [literal] {x} \\ "\r\n\n'; printf 'err\r\n\n' >&2; exit "$1";;
    empty) exit "$1";;
    large) for ((i=0;i<4096;i++)); do printf '0123456789abcdef0123456789abcdef'; printf 'fedcba9876543210fedcba9876543210' >&2; done;;
    cwd) printf '%s\n' "$PWD";;
esac
