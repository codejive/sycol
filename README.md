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

## Run

Targets: **Bash 3.2+** with 64-bit shell arithmetic, and **Windows PowerShell
5.1+ / PowerShell 7+**. Save scripts as UTF-8. Run a file from the project root:

| Shell | Command |
| --- | --- |
| Bash | `./sycol examples/hello.tcl Alice Bob` |
| CMD/Pwsh | `.\sycol examples/hello.tcl Alice Bob` |

Entry-script paths resolve from the current working directory. Only `core.tcl`
loads automatically; use `source files.tcl` for filesystem/path commands and
`source dict.tcl` for [dictionaries](docs/commands.md#dictionaries). There is no REPL, stdin
script mode, or `-c` mode. Add `.sycol/bin/` to `PATH` for direct invocation,
or copy the two root wrappers and the entire `.sycol/` directory into your
project. See [running scripts](docs/running.md) for installation, version
queries, Windows execution policy, and argument quoting.

## Documentation

Start with the [documentation guide](docs/README.md), or go directly to:

- [Language basics](docs/language.md): Tcl syntax, values, procedures, and errors.
- [Command reference](docs/commands.md): every supported command, parameters, and results.
- [Testing and development](docs/development.md): tests, timings, benchmarks, and contributions.
- [Implementation](docs/implementation.md): project structure, backends, embedding, and extensions.
- [Tcl compatibility](docs/tcl-compatibility.md): supported subset and deliberate differences.

The [specification](SPEC.md) defines the formal contract;
the [release guide](RELEASE.md) documents publishing.
