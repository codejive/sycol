# Running scripts

[Documentation](README.md) · [Language basics](language.md) · [Command reference](commands.md)

## Requirements and installation

Use Bash 3.2+ with signed 64-bit shell arithmetic, Windows PowerShell 5.1+,
or PowerShell 7+. A Tcl installation, compiler, package download, and external
language runtime are unnecessary. Some filesystem and process operations use
[standard host utilities](implementation.md#host-dependencies).

For a project-local installation, copy `sycol`, `sycol.bat`, and the entire
`.sycol/` directory together. The runtime contains its version file, launchers,
native modules, and shared SDK; copying only a launcher is insufficient.
The root wrappers find `.sycol/` beside themselves.

Alternatively, keep `.sycol/` anywhere and add its `bin/` directory to `PATH`.
In Bash, `sycol` selects the executable; in PowerShell on Windows it selects
`sycol.ps1`; in CMD it selects `sycol.bat`. On other platforms, PowerShell
users can explicitly invoke `sycol.ps1` on `PATH`.

TGZ release archives preserve executable bits. ZIP records them too, but some
extractors ignore them. If needed on Unix, run
`chmod +x sycol .sycol/bin/sycol`. See the [release guide](../RELEASE.md)
for archive contents and checksums.

## Invocation

The interface is `sycol SCRIPT [ARG ...]` or `sycol --version`. Scripts must
be files: no REPL, stdin script mode, or `-c` option is available.

From the project root:

```sh
./sycol examples/hello.tcl Alice 'Bob Smith'
# Explicitly select a Bash installation:
/bin/bash ./sycol examples/hello.tcl Alice 'Bob Smith'
```

```powershell
& ./.sycol/bin/sycol.ps1 examples/hello.tcl Alice 'Bob Smith'
# Select an engine in a new process:
powershell -NoProfile -File .sycol/bin/sycol.ps1 examples/hello.tcl Alice
pwsh -NoProfile -File .sycol/bin/sycol.ps1 examples/hello.tcl Alice
```

```bat
sycol examples/hello.tcl Alice "Bob Smith"
```

The wrappers preserve the working directory and interpreter exit status.
Script paths, `source`, and all other relative file paths resolve from that
directory, not from the launcher or currently sourced file. Use an absolute
launcher path to invoke Sycol from another directory.

If Windows policy prevents unsigned scripts, use your normal script-signing
workflow or launch with
`powershell -NoProfile -ExecutionPolicy Bypass -File .sycol/bin/sycol.ps1 SCRIPT`.
Both batch launchers use Windows PowerShell with `-NoProfile` and a
process-scoped `-ExecutionPolicy Bypass` automatically.

## Script arguments and results

Startup defines these ordinary, mutable global variables:

| Variable | Value |
| --- | --- |
| `argv0` | Script filename exactly as passed to the launcher |
| `argc` | Decimal count of arguments after the filename |
| `argv` | Proper list of those arguments, preserving spaces and empty values |
| `sycol_host` | `bash` or `powershell` |
| `sycol_version` | Release version read from `.sycol/VERSION` |

For example, with `examples/hello.tcl Alice 'Bob Smith'`, `argc` is `2` and
`[lindex $argv 1]` is `Bob Smith`. From a procedure use `$::argv`, or declare
`global argv` before using `$argv`.

The final script result is not printed; use `puts`. Successful completion
exits `0`. An uncaught error or unresolved return, break, or continue exits
`1` and prints `sycol: VALUE (completion CODE)` to stderr. A normal top-level
`return` ends the script successfully through its `source` boundary. An
explicit `exit ?status?` terminates immediately, with status `0..255` (default
`0`), including inside `catch`.

Missing the script argument prints usage to stderr and exits `2`. The first
argument otherwise names a file, except for the sole option `--version`.
Arguments after a script filename are always literal script arguments.

## Version queries

Use `./sycol --version`, `sycol.bat --version`, or
`& ./.sycol/bin/sycol.ps1 --version`. Each prints only the release version and
a newline, then exits `0`, without loading the SDK or an entry script. Extra
arguments after `--version` are a usage error (exit `2`). To run a file named
`--version`, supply a path such as `./--version`.

Inside a script or procedure, `puts $::sycol_version` prints the same version.
Keep `.sycol/VERSION` with every installation. A missing, unreadable, empty,
or invalid file makes startup and version queries fail with status `1`.
The release version is separate from the version of [SPEC.md](../SPEC.md).

## Windows argument quoting

Direct `.ps1` invocation from PowerShell preserves string arguments, including
empty strings and embedded quotes, without going through CMD. Prefer it when
arguments contain complex punctuation.

CMD parses arguments before Sycol receives them. Quote spaces and
metacharacters, use `""` for an empty argument, and disable delayed expansion
when passing literal `!`. Windows PowerShell's command-line parser additionally
requires `\"` for a literal quote and doubled trailing backslashes before a
closing quote. For example, at an interactive CMD prompt with delayed expansion off:

```bat
sycol scripts/build.tcl "" "two words" "say \"hello\"" "C:\some path\\" "a&b"
```

CMD expands `%NAME%` before launching. Inside a calling batch file, literal
percent signs need `%%`. The wrappers disable delayed expansion internally
and do not use `CALL` to re-expand arguments; they cannot recover text already
expanded by the caller.

Combining literal quotes and CMD metacharacters in one argument requires
escaping for every batch parsing pass. `\"` alone does not protect an `&`
inside those literal quotes. Use the `.ps1` entry point directly from
PowerShell for these arguments.

## Source files and libraries

Save all `.tcl` source as UTF-8. A leading UTF-8 BOM is accepted; `source`
normalizes CRLF to LF. Encoding is assumed rather than validated; malformed
UTF-8 and other encodings are unsupported, and NUL in text files is an error.

Sycol automatically loads direct native files for its host, then direct SDK
`.tcl` files before your entry script. Use lowercase ASCII library filenames;
files load alphabetically, independently of locale. Dot-prefixed files and
subdirectories are ignored. SDK files should define procedures; native files
should define helpers and register handlers. Neither should execute commands
requiring another library during loading. Add application procedures in
separate files and load them with `source`; see
[library discovery](implementation.md#library-discovery).

Scripts have the filesystem and process access of their host shell. Run
trusted scripts.
