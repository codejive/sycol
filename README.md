# sycol

Somewhere along the way, "just write a shell script" got badly out of hand.

Sycol is a tiny, string-only Tcl-like interpreter written in Bash. Then,
because apparently nobody confiscated the keyboard, we wrote it again in
PowerShell. That's a shell interpreter running a script interpreter whose SDK
is itself written in scripts. The call is coming from inside the shell.

Both implementations load the **same Tcl SDK** and run the same Tcl conformance
suite, because even this nonsense deserves tests. No Tcl installation, external
language runtime, compiler, package download, or infix expression parser is
needed. Just your existing shell, doing a job it was absolutely not expecting
when it came to work this morning.

```tcl
proc square {n} { * $n $n }
foreach n {1 2 3} { puts [square $n] }

set total 0
for {set i 0} {< $i 5} {incr i} { incr total $i }
puts "total: $total"
puts [exec git --version]
```

Run a file (paths are relative to the current working directory):

```sh
./sycol examples/hello.tcl Alice 'Bob Smith'
```

```powershell
& ./.sycol/bin/sycol.ps1 examples/hello.tcl Alice 'Bob Smith'
```

From CMD:

```bat
sycol examples/hello.tcl Alice "Bob Smith"
```

Targets: **Bash 3.2+** with 64-bit shell arithmetic, and **Windows PowerShell
5.1+ / PowerShell 7+**. There is no REPL, stdin script mode, or `-c` mode.
If local Windows policy prevents running an unsigned script, use your normal
script-signing workflow or launch it with
`powershell -NoProfile -ExecutionPolicy Bypass -File .sycol/bin/sycol.ps1 ...`.

Add `.sycol/bin/` to `PATH` to run `sycol script.tcl [args ...]` directly.
Bash selects the executable `sycol`, PowerShell on Windows selects `sycol.ps1`,
and CMD selects `sycol.bat`. PowerShell users can specify `sycol.ps1` explicitly
to bypass CMD argument parsing. The root `sycol` and `sycol.bat` wrappers
provide project-local invocation without changing `PATH`.

Query the Sycol release with `./sycol --version`, `sycol.bat --version`, or
`& ./.sycol/bin/sycol.ps1 --version`. Each prints just the version and a newline.
Inside a Tcl script or procedure, use `puts $::sycol_version`.
The single `.sycol/VERSION` file, initially `0.1.0`, stores the runtime version;
keep it with the distribution when copying Sycol into another project.
Maintainers publish releases through the manually triggered GitHub Actions
workflow, supplying an explicit version. See [the release process](RELEASE.md).

Copy the two root wrappers and the entire `.sycol/` directory into your project:

```text
sycol
sycol.bat
.sycol/
  VERSION
  bin/
    sycol
    sycol.ps1
    sycol.bat
  native/
    core.sh
    core.ps1
  sdk/
    control.tcl
    lists.tcl
    strings.tcl
    variables.tcl
```

Launchers find the runtime relative to themselves and preserve the working
directory and exit status. The batch launcher uses Windows PowerShell with
`-NoProfile -ExecutionPolicy Bypass` for that process.

CMD still applies its own syntax before a launcher receives arguments. Quote
spaces and metacharacters, use `""` for an empty argument, and disable delayed
expansion when passing literal `!`. Windows PowerShell's command-line parser
also requires `\"` for a literal quote and doubled trailing backslashes before
a closing quote. For example, from an interactive CMD prompt with delayed
expansion off:

```bat
sycol scripts/build.tcl "" "two words" "say \"hello\"" "C:\some path\\" "a&b"
```

CMD expands `%NAME%` before launching; inside a calling batch file, literal
percent signs need `%%`. The wrappers do not use `CALL` or re-expand arguments
with delayed expansion. Combining literal quotes with CMD metacharacters in
one argument requires escaping for each batch parsing pass; `\"` alone does
not protect an `&` inside those literal quotes. For such arguments, invoke the
`.ps1` entry point directly from PowerShell.

Each interpreter automatically loads direct native files for its host (`.sh`
or `.ps1`), then loads all direct SDK `.tcl` files before running your script.
Use lowercase ASCII filenames; files load alphabetically, independently of
the current locale. Dot-prefixed files and subdirectories are ignored.
Native files define helpers and register commands; SDK files define procedures.
Neither should invoke commands that require another library file during loading.
Adding a file needs no launcher change. Scripts can also `source` additional
Tcl files to extend the SDK for one application.
Save all `.tcl` source files as UTF-8 (an optional UTF-8 BOM is accepted).
The runtime assumes UTF-8 without validating it; other encodings are unsupported.
See [the complete language and SDK specification](SPEC.md), including native
extension examples, supported syntax, and deliberate Tcl differences.

Run the tests from any directory:

```sh
bash tests/run.sh
# To select a particular Bash version:
SYCOL_BASH=/bin/bash /bin/bash tests/run.sh
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -File tests/run.ps1
```

Each driver runs the shared Tcl suite, process tests, library discovery, and
launcher tests in its own host. On Windows these include both batch entry
points and CMD quoting, PATH lookup, and exit status propagation.
Tests return a nonzero process status on failure and use an isolated temporary
directory for generated files. CI covers macOS `/bin/bash` (the Bash 3.2
target), current Linux Bash, Windows PowerShell, and PowerShell on Windows and
Linux. CI configuration is included; running CI requires a hosted repository.

For optional timings (file reading, startup, parsing, and list encoding), run
`bash tests/benchmark.sh` or `powershell` / `pwsh -NoProfile -File tests/benchmark.ps1`.
To compare another installation, pass its interpreter file as the first Bash
argument or PowerShell's `-Runtime` argument. Timings depend on the host and
locale; the benchmarks are not pass/fail performance tests.

Sycol scripts have the same filesystem and process access as their host shell.
Run trusted scripts.
