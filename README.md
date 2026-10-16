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
powershell -NoProfile -File sycol.ps1 examples/hello.tcl Alice 'Bob Smith'
pwsh -NoProfile -File sycol.ps1 examples/hello.tcl Alice 'Bob Smith'
```

Targets: **Bash 3.2+** with 64-bit shell arithmetic, and **Windows PowerShell
5.1+ / PowerShell 7+**. There is no REPL, stdin script mode, or `-c` mode.
If local Windows policy prevents running an unsigned script, use your normal
script-signing workflow or add `-ExecutionPolicy Bypass` to that invocation.

With its directory on `PATH`, run `sycol script.tcl [args ...]` directly.
The Bash script is executable and uses its shebang to select Bash.

The distribution is `sycol` **or** `sycol.ps1`, plus the `lib/` directory
next to it:

```text
lib/
  native/
    core.sh
    core.ps1
  sdk/
    control.tcl
    lists.tcl
    strings.tcl
    variables.tcl
```

Each interpreter automatically loads direct native files for its host (`.sh`
or `.ps1`), then loads all direct SDK `.tcl` files before running your script.
Use lowercase ASCII filenames; files load alphabetically, independently of
the current locale. Dot-prefixed files and subdirectories are ignored.
Native files define helpers and register commands; SDK files define procedures.
Neither should invoke commands that require another library file during loading.
Adding a file needs no launcher change. Scripts can also `source` additional
Tcl files to extend the SDK for one application.
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

Each driver runs the shared Tcl suite, process tests, and library discovery
tests in its own host.
Tests return a nonzero process status on failure and use an isolated temporary
directory for generated files. CI covers macOS `/bin/bash` (the Bash 3.2
target), current Linux Bash, Windows PowerShell, and PowerShell on Windows and
Linux. CI configuration is included; running CI requires a hosted repository.

Sycol scripts have the same filesystem and process access as their host shell.
Run trusted scripts.
