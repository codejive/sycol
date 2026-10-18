#!/usr/bin/env bash
set -e
cd -- "${BASH_SOURCE[0]%/*}/.."
source tests/timing.sh
engine=${SYCOL_BASH:-bash}
work=$(mktemp -d "$PWD/.test-tmp/timing-check.XXXXXXXX")
trap 'rm -f -- "$work/current" "$work/baseline" "$work/output" "$work/expected" "$work/error" "$work/current".clock.*; rmdir -- "$work"' EXIT
export SYCOL_TIMING_FILE="$work/current" SYCOL_TIMING_BASELINE="$work/baseline"
export SYCOL_TIMING_EXPECTED="$work/expected" SYCOL_TIMING_OUTPUT="$work/output"
export SYCOL_TIMING_REGRESSION_MS=50 SYCOL_TIMING_REGRESSION_PERCENT=25
cp tests/fixtures/timings-current.tsv "$SYCOL_TIMING_FILE"
cp tests/fixtures/timings-baseline.tsv "$SYCOL_TIMING_BASELINE"
printf '# Expected durations\r\n\r\ntest/slow\t150\r\ntest/tiny\t8\r\n' > "$SYCOL_TIMING_EXPECTED"
report=$(timing_report)
for expected in '1500 ms total; 6 named tests' '1100  absolute' 'matched environment' 'test/slow +100 ms (+100.0%)' 'test/slow 200 ms exceeds expected 150 ms' 'test/tiny 11 ms exceeds expected 8 ms'; do
    [[ $report == *"$expected"* ]] || { printf 'Missing timing output: %s\n' "$expected" >&2; exit 1; }
done
for unexpected in 'test/tiny +' 'test/absolute +' 'test/relative +' 'test/zero +' 'test/equal +'; do
    [[ $report != *"$unexpected"* ]] || { printf 'Unexpected timing output: %s\n' "$unexpected" >&2; exit 1; }
done
[[ $(< "$SYCOL_TIMING_OUTPUT") == "$(< tests/fixtures/timings-current.tsv)" ]]
cp tests/fixtures/timings-current.tsv "$SYCOL_TIMING_FILE"
printf 'meta\tmachine\tother\n' >> "$SYCOL_TIMING_BASELINE"
report=$(timing_report)
[[ $report == *'environment mismatch; comparison skipped'* && $report != *'test/slow +'* ]]
[[ $report == *'exceeds expected'* ]]
status=0
timing_measure test failure "$engine" -c 'printf "visible stderr\n" >&2; exit 7' 2> "$work/error" || status=$?
[[ $status == 7 && $(< "$work/error") == 'visible stderr' ]]
IFS=$'\t' read -r kind name value < "$SYCOL_TIMING_FILE"
[[ $kind == test && $name == failure ]]; timing_uint "$value"
if SYCOL_TIMING_REGRESSION_MS=invalid timing_options 2> "$work/error"; then exit 1; fi
printf '%s\n' 'timing reporting tests passed'
