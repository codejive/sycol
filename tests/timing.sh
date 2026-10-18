#!/usr/bin/env bash
# Test-only timing support. TSV values cannot contain tabs or newlines.
timing_ms() {
    local timing_seconds=${1%.*} timing_fraction=${1#*.}
    timing_fraction=${timing_fraction}000
    timing_value=$((10#$timing_seconds * 1000 + 10#${timing_fraction:0:3}))
}
timing_record() {
    case $2$3 in *$'\t'*|*$'\r'*|*$'\n'*) printf '%s\n' 'Timing values cannot contain tabs or newlines' >&2; return 1;; esac
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$SYCOL_TIMING_FILE"
}
timing_measure() {
    local timing_kind=$1 timing_name=$2 timing_status=0 timing_elapsed
    local timing_depth=$(( ${timing_depth:-0} + 1 ))
    local TIMEFORMAT='%3R' LC_NUMERIC=C
    local timing_scratch="$SYCOL_TIMING_FILE.clock.$$.$timing_depth"
    shift 2
    # Keep command stderr visible, and execute in this shell to preserve state.
    { time "$@" 2>&3; } 3>&2 2> "$timing_scratch" || timing_status=$?
    IFS= read -r timing_elapsed < "$timing_scratch"
    timing_elapsed=${timing_elapsed/,/.}
    timing_ms "$timing_elapsed"
    timing_record "$timing_kind" "$timing_name" "$timing_value"
    return "$timing_status"
}
timing_uint() { case $1 in ''|*[!0-9]*|??????????*) return 1;; esac; }
timing_options() {
    timing_absolute=${SYCOL_TIMING_REGRESSION_MS:-100}
    timing_relative=${SYCOL_TIMING_REGRESSION_PERCENT:-25}
    timing_uint "$timing_absolute" && timing_uint "$timing_relative" || { printf '%s\n' 'Invalid timing regression thresholds' >&2; return 1; }
    timing_absolute=$((10#$timing_absolute)); timing_relative=$((10#$timing_relative))
    timing_expected_names=(); timing_expected_values=()
    local timing_key timing_limit timing_extra
    if [[ -n ${SYCOL_TIMING_EXPECTED:-} ]]; then
        [[ -f $SYCOL_TIMING_EXPECTED && -r $SYCOL_TIMING_EXPECTED ]] || { printf '%s\n' 'Cannot read expected timings' >&2; return 1; }
        while IFS=$'\t' read -r timing_key timing_limit timing_extra || [[ -n $timing_key ]]; do
            timing_key=${timing_key%$'\r'}; timing_limit=${timing_limit%$'\r'}
            [[ -z $timing_key || $timing_key == \#* ]] && continue
            timing_uint "$timing_limit" && [[ -z $timing_extra ]] || { printf '%s\n' 'Invalid expected timing row (use key TAB integer milliseconds)' >&2; return 1; }
            timing_expected_names+=("$timing_key"); timing_expected_values+=("$((10#$timing_limit))")
        done < "$SYCOL_TIMING_EXPECTED"
    fi
    [[ -z ${SYCOL_TIMING_BASELINE:-} || ( -f $SYCOL_TIMING_BASELINE && -r $SYCOL_TIMING_BASELINE ) ]] || { printf '%s\n' 'Cannot read timing baseline' >&2; return 1; }
}
timing_init() {
    timing_options || return
    mkdir -p .test-tmp
    SYCOL_TIMING_FILE=$(mktemp "$PWD/.test-tmp/timings.XXXXXXXX")
    export SYCOL_TIMING_FILE
    timing_record meta format sycol-timing-v1
    timing_record meta host bash
    timing_record meta runtime "$("$engine" -c 'printf "%s" "$BASH_VERSION"')"
    timing_record meta executable "$(command -v "$engine")"
    timing_record meta machine "$(uname -n)"
    timing_record meta os "$(uname -s -r)"
    timing_record meta architecture "$(uname -m)"
    timing_record meta locale "${LC_ALL:-${LANG:-unset}}"
    timing_record meta clock bash-time-ms
    timing_measure phase startup "$engine" .sycol/bin/sycol tests/fixtures/startup.tcl
}
timing_metadata() {
    local timing_kind timing_name timing_value
    while IFS=$'\t' read -r timing_kind timing_name timing_value; do
        timing_value=${timing_value%$'\r'}
        [[ $timing_kind != meta ]] || printf '%s\t%s\n' "$timing_name" "$timing_value"
    done < "$1"
}
timing_report() {
    local timing_kind timing_name timing_value timing_key timing_i timing_old timing_delta timing_percent
    local timing_count=0 timing_matched=0 timing_total=0
    local -a timing_names=() timing_values=() timing_baseline_names=() timing_baseline_values=()
    timing_options || return
    if [[ -n ${SYCOL_TIMING_BASELINE:-} ]]; then
        if [[ $(timing_metadata "$SYCOL_TIMING_FILE") == "$(timing_metadata "$SYCOL_TIMING_BASELINE")" ]]; then
            timing_matched=1
            while IFS=$'\t' read -r timing_kind timing_name timing_value; do
                timing_value=${timing_value%$'\r'}
                [[ $timing_kind != meta ]] || continue
                timing_uint "$timing_value" || { printf '%s\n' 'Invalid baseline timing' >&2; return 1; }
                timing_baseline_names+=("$timing_kind/$timing_name"); timing_baseline_values+=("$((10#$timing_value))")
            done < "$SYCOL_TIMING_BASELINE"
        fi
    fi
    while IFS=$'\t' read -r timing_kind timing_name timing_value; do
        case $timing_kind in
            test) timing_count=$((timing_count+1)); timing_names+=("$timing_name"); timing_values+=("$timing_value");;
            suite) timing_total=$timing_value;;
        esac
    done < "$SYCOL_TIMING_FILE"
    printf '\nTiming: %s ms total; %s named tests\n' "$timing_total" "$timing_count"
    printf 'Startup/module loading and suite groups (ms):\n'
    while IFS=$'\t' read -r timing_kind timing_name timing_value; do
        case $timing_kind in phase|group) printf '  %8s  %s/%s\n' "$timing_value" "$timing_kind" "$timing_name";; esac
    done < "$SYCOL_TIMING_FILE"
    printf 'Slowest named tests (ms):\n'
    # Only standard sort is needed; no additional language/runtime dependency.
    for ((timing_i=0;timing_i<${#timing_names[@]};timing_i++)); do
        printf '%s\t%s\n' "${timing_values[timing_i]}" "${timing_names[timing_i]}"
    done | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | {
        timing_i=0
        while IFS=$'\t' read -r timing_value timing_name; do
            if ((timing_i<10)); then printf '  %8s  %s\n' "$timing_value" "$timing_name"; fi
            timing_i=$((timing_i+1))
        done
    }
    if [[ -z ${SYCOL_TIMING_BASELINE:-} ]]; then printf 'Baseline: not configured\n'
    elif ((timing_matched)); then printf 'Baseline: matched environment\n'
    else printf 'Baseline: environment mismatch; comparison skipped\n'; fi
    while IFS=$'\t' read -r timing_kind timing_name timing_value; do
        case $timing_kind in test|phase|group|suite) ;; *) continue;; esac
        timing_key=$timing_kind/$timing_name
        for ((timing_i=0;timing_i<${#timing_expected_names[@]};timing_i++)); do
            if [[ $timing_key == "${timing_expected_names[timing_i]}" ]] && ((timing_value>timing_expected_values[timing_i])); then
                printf 'TIMING warning: %s %s ms exceeds expected %s ms\n' "$timing_key" "$timing_value" "${timing_expected_values[timing_i]}"
            fi
        done
        for ((timing_i=0;timing_i<${#timing_baseline_names[@]};timing_i++)); do
            [[ $timing_key == "${timing_baseline_names[timing_i]}" ]] || continue
            timing_old=${timing_baseline_values[timing_i]}; timing_delta=$((timing_value-timing_old))
            if ((timing_old>0 && timing_delta>timing_absolute && timing_delta*100>timing_old*timing_relative)); then
                timing_percent=$((timing_delta*1000/timing_old))
                printf 'TIMING warning: %s +%s ms (+%s.%s%%)\n' "$timing_key" "$timing_delta" "$((timing_percent/10))" "$((timing_percent%10))"
            fi
        done
    done < "$SYCOL_TIMING_FILE"
    local timing_output=${SYCOL_TIMING_OUTPUT:-$PWD/.test-tmp/timings-bash.tsv}
    # Compare before copying, so a previous output can also serve as baseline.
    cp -- "$SYCOL_TIMING_FILE" "$timing_output" || return
    rm -f -- "$SYCOL_TIMING_FILE" "$SYCOL_TIMING_FILE".clock.*
    printf 'Timing results: %s\n' "$timing_output"
}
