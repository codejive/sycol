# Testing and development

[Documentation](README.md) · [Implementation](implementation.md) · [Release guide](../RELEASE.md)

## Run the tests

From the repository root:

```sh
bash tests/run.sh
# Select a particular Bash executable, including for child interpreters:
SYCOL_BASH=/bin/bash /bin/bash tests/run.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -File tests/run.ps1
```

The drivers locate the repository relative to themselves and change to its
root. From another directory, pass an absolute path to the driver. Each driver
runs the shared Tcl suite and its host-specific probes, uses isolated temporary
fixtures, cleans generated files, and returns a nonzero process status on
failure. The tests use host utilities beyond the interpreter's runtime
dependencies; inspect the drivers when preparing a minimal test environment.

Run both drivers on available hosts. Running only the shared `.tcl` files
skips setup and host checks; use the drivers for complete verification.

## Test layout and coverage

| Files | Checks |
| --- | --- |
| `tests/all.tcl` | Shared test harness; syntax, substitution, scope, procedures, return levels, arithmetic, control flow, I/O, globals, and errors |
| `tests/parser.tcl`, `lists.tcl`, `files.tcl`, `paths.tcl` | Additional parser, list, filesystem, and path cases sourced by `all.tcl` |
| `tests/exec.tcl`, `fixtures/probe.sh`, `fixtures/probe.ps1` | Literal process arguments, stdout trimming, inherited stderr, nonzero exits, capture records, exact line endings, concurrent large streams, and cwd |
| `tests/files-move.tcl` | Move operations, replacement, failure retention, and cross-filesystem behavior when fixture roots permit it |
| `tests/native.tcl` | Registered native handler behavior |
| `tests/sdk-replacements.tcl`, `sdk-replacements.sh`, `sdk-replacements.ps1` | Native/fallback SDK parity and test-side subset selection |
| `tests/discovery.tcl`, `discovery.sh`, `discovery.ps1` | Copied-installation search paths, optional loading, native precedence, repeated source, overrides, embedding, and startup failures |
| `tests/encoding.tcl`, `encoding.sh`, `encoding.ps1` | UTF-8/BOM, source line endings, and NUL handling |
| `tests/launchers.sh`, `launchers.ps1` | Entry points, versions, PATH lookup, arguments, exit propagation, and Windows batch/CMD quoting |
| `tests/timing.tcl`, `timing-check.sh`, `timing-check.ps1`, `fixtures/timings-*.tsv` | Timing helper semantics, report formatting, configuration, comparisons, and warnings |
| `tests/release.sh` | Separate archive manifest, contents, version, and executable-permission verification; see the release guide |

Symbolic-link tests depend on host link-creation permission. Cross-filesystem
tests require fixture roots on different devices. Drivers report unavailable
fixtures; a same-filesystem move run does not prove cross-filesystem coverage.

## Add or change behavior

Read [SPEC.md](../SPEC.md) before implementation. It defines language behavior,
compatibility boundaries, and extension contracts. Check Tcl's name, syntax,
options, and behavior before adding a command. Follow Tcl when the additional
cost is negligible; explain material costs and a low-cost aligned alternative
before implementing a departure.

Prefer shared procedures in `.sycol/lib/`; add native code only for evaluator
mechanisms or required host facilities. Measured equivalent native SDK
replacements may retain shared definitions as portable fallbacks; the shipped
core does this for `incr`, `append`, `concat`, and `lappend`.
Keep Bash and PowerShell equivalent
in results, completion codes, argument boundaries, and errors. Preserve
Bash 3.2+ and Windows PowerShell 5.1+ support: avoid newer-host-only features.

For bugs, reproduce the issue, check the intended contract, add a failing
regression test, and make the smallest coherent fix. For new behavior, update
the specification and relevant usage examples, then add meaningful tests.
Use shared Tcl tests unless a host-specific probe is needed. Use Conventional
Commits, for example `docs: expand the command reference`.

The shared harness has signature
`test name body expected ?expectedCode?` (default code `0`). It evaluates the
body, compares both result and completion, records pass/fail counts, and
prints a diagnostic. Add tests in the appropriate shared file:

```tcl
test list-tail { lindex {a b c} end } c
test divide-zero { / 1 0 } {division by zero} 1
```

Keep names unique so timing keys identify a single body. Existing test groups
provide filesystem fixtures and external-process probes; reuse them rather
than depending on arbitrary local paths or executables.

After behavioral changes, run `bash tests/run.sh` and available PowerShell
drivers. Report which runtimes ran, failures, and unavailable runtimes. A newer
local runtime does not establish minimum-version coverage. Documentation-only
changes need content/link checks rather than interpreter tests.

## Native SDK differential checks

The test embedding launchers `tests/timed.sh` and `tests/timed.ps1` accept
`SYCOL_TEST_SDK_NATIVE=fallback`, `scalars`, or `lists` to remove respectively
all four replacements, only the list pair, or only the scalar pair before SDK
loading. Leave it unset for all replacements. This is test-side host inspection,
not a production setting. Run full drivers with `fallback` to exercise the
actual unchanged Tcl definitions; a same-name `proc` cannot disable natives.
`tests/sdk-replacements.tcl` runs the same contracts in every selection.
Discovery checks no Tcl procedures exist at bootstrap, availability before and
after explicit loading, and later handler replacement.

## CI

[The test workflow](../.github/workflows/test.yml) configures:

| Runner | Runtime |
| --- | --- |
| Linux | Current runner `/bin/bash` |
| macOS | `/bin/bash`, targeting Bash 3.2 |
| Windows | Separate Windows PowerShell and PowerShell 7 jobs |
| Linux | PowerShell 7 |

The workflow also checks direct/PATH Bash invocation and can be called by the
release workflow. These are configured checks; a local run does not establish
that hosted CI passed. CI execution requires a hosted repository.

## Timing reports

Every driver run prints total suite time, the count of timed named tests,
the ten slowest named tests, native/SDK loading measurements, and timings for
shared, filesystem-move, native-extension, process, discovery, encoding, and
launcher groups.

| Measurement | Included work |
| --- | --- |
| `test/NAME` | Named body, including expected-error paths; excludes assertion/reporting overhead |
| `phase/NAME` | Startup or module-loading phase, as named in the report |
| `phase/startup` | Fresh process executing an empty script, including interpreter initialization and SDK loading |
| `group/NAME` | Whole test group; child-process startup where applicable |
| `suite/total` | Driver setup, groups, and cleanup; excludes the separate startup probe, timing-report self-checks, and final report rendering |

Module timings exclude process creation. Host-only probes are measured as
groups. Measurements overlap and must not be added together. The named-test
count includes recorded helper-conformance bodies, not every host assertion.

Reports are UTF-8, LF-terminated TSV files. They are saved after failures too,
including partial measurements and the failing exit status.

| Environment variable | Meaning/default |
| --- | --- |
| `SYCOL_TIMING_OUTPUT` | Output file; default `.test-tmp/timings-bash.tsv` or `.test-tmp/timings-powershell.tsv`. A custom parent directory must exist. |
| `SYCOL_TIMING_BASELINE` | Optional previous result file to compare with the current run |
| `SYCOL_TIMING_REGRESSION_MS` | Absolute regression threshold, default `100` ms |
| `SYCOL_TIMING_REGRESSION_PERCENT` | Relative regression threshold, default `25` percent |
| `SYCOL_TIMING_EXPECTED` | Optional file of per-measurement expected maximum durations |

Configuration paths resolve from the repository root. Regression thresholds
and configured duration values are nonnegative integers with at most nine
digits. Warnings are informational and never change test exit status; invalid
configuration or unreadable configuration files are errors.

Bash uses built-in `time` and is not guaranteed monotonic. PowerShell uses
`Diagnostics.Stopwatch`. Reports use whole milliseconds, so very short bodies
may round to zero. No additional language dependency is needed.

The test launchers `tests/timed.sh` and `tests/timed.ps1` register
`test.time name script`. This internal helper evaluates once in the current
frame, records duration even for nonzero completion, and preserves result,
completion, pending return code, and return level. Normal Sycol has no timing
command. `SYCOL_TIMING_FILE` is driver-internal plumbing, not an output-setting
alternative for users.

### Compare with a baseline

```sh
cp .test-tmp/timings-bash.tsv .test-tmp/baseline-bash.tsv
SYCOL_TIMING_BASELINE=.test-tmp/baseline-bash.tsv bash tests/run.sh
```

```powershell
Copy-Item .test-tmp/timings-powershell.tsv .test-tmp/baseline-powershell.tsv
$env:SYCOL_TIMING_BASELINE = '.test-tmp/baseline-powershell.tsv'
pwsh -NoProfile -File tests/run.ps1
```

Baselines must match host, runtime version and executable, machine, OS,
architecture, locale, clock, and symbolic-link fixture availability. Mismatches
are reported and comparison is skipped. Keep separate baselines for Windows
PowerShell and PowerShell 7.

A default regression warning requires an increase strictly greater than
**both 100 ms and 25%**. Zero baseline durations have no meaningful percentage
and are skipped, as are missing baseline measurements.

### Set expected maximum durations

`SYCOL_TIMING_EXPECTED` selects a UTF-8 file containing exact measurement keys,
a literal tab, and maximum durations in integer milliseconds:

```text
# The separator on each data line is a literal tab.
test/exec-capture	10000
group/discovery	5000
```

Copy keys from the result file: `test/NAME`, `phase/NAME`, `group/NAME`, or
`suite/total`. Blank lines and `#` comments are accepted. A duration exceeding
its configured maximum produces an informational warning.

### TSV format

Every record contains three fields, without embedded tabs or newlines:

| Record | Fields |
| --- | --- |
| `meta KEY VALUE` | Format `sycol-timing-v1` and comparison environment |
| `test NAME MILLISECONDS` | Named test duration |
| `phase NAME MILLISECONDS` | Phase duration |
| `group NAME MILLISECONDS` | Group duration |
| `suite total MILLISECONDS` | Total suite duration |
| `status exit CODE` | Suite exit status |

Spaces above illustrate field boundaries; actual separators are tabs.
Baselines are read as data, never executed as shell source. Test-side reporting
helpers do not become interpreter runtime dependencies.

## Optional benchmarks

```sh
bash tests/benchmark.sh
# Compare another interpreter installation:
bash tests/benchmark.sh /path/to/other/.sycol/bin/sycol
```

```powershell
powershell -NoProfile -File tests/benchmark.ps1
pwsh -NoProfile -File tests/benchmark.ps1 -Runtime C:/other/.sycol/bin/sycol.ps1
```

These measure file reading, SDK loading, file/path operations, startup,
parsing, and list encoding. Results depend on host and locale. Benchmarks are
optional measurements, not pass/fail performance tests.

For publishing, archive verification, and release recovery, use the separate
[release guide](../RELEASE.md).
