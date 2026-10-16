#!/usr/bin/env bash
mode=$1; shift
case $mode in
    args) for arg in "$@"; do printf '<%s>' "$arg"; done; printf '\n';;
    newlines) printf 'line\n\n';;
    carriage) printf 'line\r';;
    fail) printf 'diagnostic\n' >&2; exit 7;;
    cwd) printf '%s\n' "$PWD";;
esac
