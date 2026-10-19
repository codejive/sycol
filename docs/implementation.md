# Implementation

[Documentation](README.md) · [Development](development.md) · [Tcl compatibility](tcl-compatibility.md)

## Project structure

| Path | Responsibility |
| --- | --- |
| `sycol`, `sycol.bat` | Project-local wrappers locating the adjacent `.sycol/` installation |
| `.sycol/VERSION` | Single source for the runtime/release version |
| `.sycol/bin/sycol` | Bash parser, evaluator, variable frames, procedure/native dispatch, discovery, and file launcher |
| `.sycol/bin/sycol.ps1` | PowerShell implementation of the same language and launch contract |
| `.sycol/bin/sycol.bat` | CMD bridge to adjacent `sycol.ps1`, using Windows PowerShell |
| `.sycol/native/core.sh`, `core.ps1` | Native variable, evaluation, control, list, string, arithmetic, text, and process handlers |
| `.sycol/native/files.sh`, `files.ps1` | Native filesystem operations behind `sy.file` |
| `.sycol/lib/core.tcl` | Loops, list operations, string/variable helpers, and index resolution |
| `.sycol/lib/files.tcl` | Optional filesystem dispatch and lexical path helpers |
| `examples/hello.tcl` | Runnable example |
| `tests/` | Shared Tcl conformance cases, host probes, timing helpers, benchmarks, and archive verification |
| `docs/` | User, command, development, and implementation guides |
| `SPEC.md` | Authoritative language, SDK, compatibility, and extension contracts |
| `RELEASE.md` | Maintainer publishing instructions |
| `.github/workflows/test.yml` | Supported-host CI matrix |
| `.github/workflows/release.yml`, `jreleaser.yml` | Manual release workflow and archive/publishing configuration |

Only the two root wrappers and `.sycol/` are needed to embed the runtime in a
project. The `.sycol/` directory can also be distributed alone with `bin/` on
`PATH`. Documentation, examples, and the specification ship in release archives.

## Evaluation model

The design minimizes duplicated host-language mechanisms: one character
parser, a list mode of that parser, string values, command dispatch, variable
frames, and explicit completion state. There is no AST, bytecode, typed object
representation, object system, infix expression parser, or dependency manager.
Sycol code is never executed by evaluating host shell source.

The parser reads a command, performs substitutions left to right, and dispatches
its decoded words. List mode reuses word parsing with substitutions disabled.
Parsing is incremental, so earlier side effects survive a later syntax error.
There is no whole-file prevalidation or rollback. Disk text is checked for NUL
before its evaluation, but UTF-8 validity is assumed.

Dispatch checks native handlers first, then globally registered Tcl procedures.
Tcl definitions cannot shadow natives. Re-registering a native name replaces
its effective handler. Same-name Tcl definitions are legal but remain hidden.
There is no `unknown` hook, external-command fallback, command deletion,
command renaming, or introspection API.

Each procedure call creates a local variable frame with a parent pointing to
the caller. Unqualified lookup stays in the current frame; leading `::` or a
`global` alias selects the global frame. Parents support explicit `uplevel`,
not automatic variable lookup. Frames and aliases are cleaned on all procedure
exit paths. Procedure definitions themselves are global and do not form closures.

Evaluation returns four pieces of state: result, completion code, pending
return target code, and remaining return level. The language uses codes
`0..4`, independently of Bash statuses or PowerShell exceptions. Procedure and
`source` boundaries consume return levels. `catch` captures that state; loops
handle selected break/continue completions. `exit` terminates the actual host
process and does not participate in this completion protocol.

Evaluation nesting is capped at 64 active script evaluations, including
substitutions, procedure bodies, and control bodies. Input length, loop count,
output size, and running time otherwise depend on host resources. One sourced
interpreter exposes one mutable instance; it is not reentrant or thread-safe.

## Required native commands

Every backend must provide the following native core commands before loading
`core.tcl`. This is the bootstrap contract for a new host or a replacement
native core. The authoritative behavior is in
[SPEC.md section 6](../SPEC.md#6-native-command-contracts); the
[command reference](commands.md) documents arguments, results, and errors.

| Area | Required commands |
| --- | --- |
| Variables and procedures | `set`, `unset`, `global`, `proc` |
| Evaluation and completion | `eval`, `uplevel`, `catch`, `return`, `break`, `continue`, `error` |
| Control flow | `if`, `while` |
| Lists | `list`, `llength`, `lindex` |
| Strings | `string` with `length`, `equal`, and `range` subcommands |
| Integer arithmetic | `+`, `-`, `*`, `/`, `%` |
| Integer comparison and negation | `<`, `<=`, `>`, `>=`, `==`, `!=`, `!` |
| Text output | `puts` |
| Script and text files | `source`, `readfile`, `writefile` |
| Working directory and environment | `pwd`, `cd`, `getenv` |
| Processes | `exec`, `exit` |

Implement the full Sycol contracts, including options, validation, frame
effects, and completion propagation. For example, `exec` requires both plain
execution and `-capture`; `return` requires `-code` and `-level`. Tcl behavior
outside the specified Sycol subset is not required.

The shipped cores also register `incr`, `append`, `concat`, and `lappend`.
These are optional native SDK accelerators: a backend may omit them and use
the portable definitions in `core.tcl`. Other shared SDK procedures likewise
do not require native implementations. In particular, `sy.list.index` is a
shared helper used by native `lindex` for non-integer index notation; that
notation becomes available after SDK loading.

The optional `files.tcl` module requires the native `sy.file` primitive when
loaded. A backend supporting this module must implement all its operations:
`windows`, `expand`, `list`, `type`, `exists`, `isfile`, `isdirectory`, `size`,
`mkdir`, `delete`, `copy`, and `rename`. Their signatures and results are listed
in the [native filesystem primitive reference](#native-filesystem-primitive).
`sy.file` is not required at core bootstrap; public `file` option parsing and
lexical path helpers remain shared Tcl procedures.

## Backend differences

Both backends implement the same language, SDK, argument boundaries, and
completion contract. These implementation choices are host-specific:

| Area | Bash | PowerShell |
| --- | --- | --- |
| Minimum host | Bash 3.2 with signed 64-bit arithmetic | Windows PowerShell 5.1/.NET Framework, or PowerShell 7+/.NET |
| Name tables | Parallel indexed arrays and linear lookup; native lookup searches newest registrations first | Ordinal, case-sensitive hashtables for variables, procedures, aliases, and native handlers |
| Parser strings | Shell strings, indexed/sliced in the active locale | .NET strings, indexed/sliced in UTF-16 code units |
| Arithmetic | Validate decimal text, then use host arithmetic with signed 32-bit operand/result checks | Validate decimal text, use wider .NET arithmetic intermediates, and check the same 32-bit limits |
| Native commands | Registered Bash function names | Registered PowerShell scriptblocks receiving a string array |
| Results | Mutable `R`, `C`, `RC`, `RL` variables | Fields on `$script:Sy`: `.R`, `.C`, `.RC`, `.RL` |
| Plain process execution | Resolve an external executable and invoke with `"$@"`; a sentinel protects captured trailing newlines | .NET process APIs; redirect stdout and inherit stderr |
| Process capture | Private temporary directory and two files; read streams after the child exits, then clean up | Redirect both streams and drain them concurrently using asynchronous .NET readers |
| Windows process arguments | Host executable invocation | CRT-style command-line quoting on Windows, including older .NET without `ArgumentList`; Unix PowerShell uses `ArgumentList` |
| Filesystem | Shell type checks and standard utilities | .NET filesystem APIs, with Unix utilities for types/permissions where needed |
| Cross-filesystem rename | Standard `mv` copy/delete fallback | Try native move, then existing copy/delete helpers for volume changes or cross-device failures |

Bash deliberately avoids associative arrays, namerefs, `mapfile`, and external
parsing tools. Linear table lookup trades speed for old-host support and fewer
mechanisms. PowerShell avoids classes, ternary/null operators, and requiring
`ProcessStartInfo.ArgumentList` on older .NET.

Windows executables with custom argument parsers may interpret CRT-quoted
strings differently. Signal statuses and non-ASCII string indexing also have
[portability limits](tcl-compatibility.md#text-and-host-portability).
Backend choice does not change the platform's path rules: PowerShell on Unix
uses Unix paths.

## Host dependencies

Parsing, procedures, lists, arithmetic, and SDK loading require no subprocess
or external parsing tool. External operations have these dependencies:

| Operation | Dependencies |
| --- | --- |
| Root Bash wrapper | `env`/Bash through its shebang, or an explicitly selected Bash |
| Bash filesystem mutation | Standard `cp`, `mv`, `mkdir`, `rm`, `rmdir`, and `chmod` on `PATH` |
| Bash file size | GNU or BSD `stat` |
| Bash `exec -capture` | `mktemp`, `cat`, `rm`, `rmdir`; temporary space under `${TMPDIR:-/tmp}` |
| PowerShell filesystem on Unix | GNU or BSD `stat` and `chmod` for file types/permission preservation on supported .NET versions |
| `exec` on either backend | The requested external executable and its own dependencies |

Bash copy uses `cp -p` with recursive, non-following-link behavior; PowerShell
preserves supported .NET attributes and Unix permission bits. Ownership, ACLs,
and cross-platform metadata translation are not portable guarantees.
Filesystem handlers turn host failures into catchable errors; host utilities
may additionally write diagnostics to stderr.

## Library discovery

Only `core.tcl` loads automatically. It contains loops, list operations,
string helpers, and variable helpers. Filesystem commands and their lexical
path helpers require `source files.tcl`. Native core commands such as
`source`, `readfile`, `writefile`, `pwd`, and `cd` remain available at bootstrap.
There is no directory scan or automatic command/package loading.

| Environment variable | Mutable Sycol global | Installation default |
| --- | --- | --- |
| `SYCOL_SDK_PATH` | `::sycol_sdk_path` | `.sycol/lib` |
| `SYCOL_NATIVE_PATH` | `::sycol_native_path` | `.sycol/native` |
| `SYCOL_SOURCE_PATH` | `::sycol_source_path` | Empty list |

Environment overrides replace, rather than extend, defaults. Environment
values use `;` on Windows (including Git Bash/MSYS) and `:` on Unix. Empty
entries are ignored; a present empty value supplies no directories. Directory
names use the executing host's path syntax. Globals are proper Sycol lists,
initialized when the interpreter is sourced. Defaults are installation-relative
absolute paths captured before an embedder can change cwd. SDK and native
defaults are independent. Explicit relative directory entries resolve against
the working directory at each load. Scripts can change globals for subsequent
loads; environment changes after initialization do not update them.

```tcl
lappend ::sycol_source_path /opt/my-library
source files.tcl
source utility.tcl
source ./local-script.tcl
```

`source` resolves absolute paths directly. Paths beginning with `./` or `../`
are relative to cwd; Windows PowerShell also accepts `.\` and `..\` and
handles rooted/volume-relative Windows paths directly. Other relative names,
including subdirectories, search SDK directories first, then source directories.
There is no implicit cwd fallback. The entry script passed to the launcher
always resolves directly against cwd, independently of search paths. Other file
commands keep their existing cwd-relative behavior. No source operation changes cwd.

The first existing candidate wins, even if it cannot be read or is a directory;
loading errors never fall through to another candidate. Missing search directories
are skipped. Invalid list globals or invalid paths produce catchable errors.
Source returns the script result, evaluates in the current frame, and consumes
one return boundary, as before.

Paths are normalized lexically to absolute paths, collapsing `.`/`..` and
redundant separators, without resolving symbolic links. SDK membership uses a
directory-component boundary, not a raw filename prefix. Windows PowerShell
compares paths without case sensitivity; Unix and Bash use case-sensitive
comparisons. If SDK roots overlap, the first containing root determines the
module-relative path. Symlink aliases can therefore have different classifications
or backend identities. These trusted-code paths are not a security boundary.

For an SDK file ending in `.tcl`, strip that extension from its path relative
to the containing SDK root and append `.sh` (Bash) or `.ps1` (PowerShell).
Search that relative backend path in native directories, in order. For example,
`sub/tools.tcl` matches `sub/tools.sh` or `sub/tools.ps1`. All hosts share the
same `native/` directory; there are no per-host subdirectories. Explicitly
requested dot-prefixed files/subdirectories are allowed; nothing is enumerated.
Files outside configured SDK roots never trigger backend loading, even when
their basenames match SDK files.

The selected Tcl file is read and checked for NUL before loading its backend;
the backend is installed before Tcl evaluation. Missing backends are allowed.
Existing backends that fail to load stop the source operation. Successfully
loaded backends execute once per normalized absolute filename per interpreter;
failed loads are remembered and fail again without rerunning host code. Windows
PowerShell treats differently cased spellings as one backend identity. Missing
backends are not cached, so later path changes or new files can supply them.
Repeated `source` always reevaluates Tcl. Partial native registrations and Tcl
side effects are not rolled back after errors.

At interpreter sourcing, initialize the paths and load the first `core.sh` or
`core.ps1` on the native path. This backend is mandatory and must provide the
bootstrap contract. Normal startup loads the first `core.tcl` on the SDK path;
it is mandatory and cannot fall back to a user source directory. Overrides
must supply compatible core files; installation defaults are not appended.
`--version` skips Tcl SDK and entry-script loading. Embedders can call `load_sdk`
or `Import-SySdk` to load just `core.tcl` in the current frame.

Native handlers always take precedence over Tcl procedures, regardless of
definition order. Defining a same-name Tcl procedure is legal, but it remains
hidden. Later native registrations replace earlier native handlers. Backends
may implement any subset of an SDK module's commands; the remaining commands
use portable Tcl definitions. The shipped core accelerates `incr`, `append`,
`concat`, and `lappend`, retaining their unchanged portable definitions in
`core.tcl`. There is no retry through Tcl after a native error.

These four commands are available before SDK loading. Sourcing still evaluates
no Tcl and initializes only search-path globals. Same-name Tcl definitions
stay hidden; later native registration replaces the handler. Public contracts
remain stable; internal shared helper calls are not interception hooks. Native
`incr` uses the arithmetic helper directly and native `concat` need not invoke
`append`. Actual command invocations in shared code still use dynamic lookup.

Scalar handlers use existing variable and arithmetic helpers in the current
frame. List handlers decode each input once and use the canonical encoder;
`lappend` writes only after validation succeeds. No parsed values are cached.
Repeated single-element appends still process the growing old string.

SDK and native path ordering is independent: they are not paired by index.
Use compatible distributions across all configured roots. Matching filenames
do not establish version compatibility; there is no version negotiation or
automatic fallback to another backend on failure. Native replacements must
preserve the public command's arguments, results, errors, frame effects, and
completion semantics. Future compiled-in hosts may activate handlers by module
identity instead of loading host files; no Java backend is implemented here.

## Native extensions and embedding

Native extensions are trusted host code. Validate arity, preserve caller
frames, keep argument boundaries, set the result/completion explicitly, and
translate failures into completion `1`. Do not print a result to stdout or
emit PowerShell pipeline objects. Use the real implementation in `.sycol/bin/`
for embedding; root wrappers launch a process rather than exposing the evaluator.

### Bash

```bash
#!/usr/bin/env bash
source /path/to/project/.sycol/bin/sycol
host_echo() {
    if (($# != 1)); then arity 'host.echo value'; return; fi
    R=$1; C=0
}
sy_register host.echo host_echo
main "$@"
exit $?
```

| Host interface | Contract |
| --- | --- |
| `sy_register name function` | Register/replace a native handler taking decoded arguments |
| `R`, `C`, `RC`, `RL` | Result, completion code, pending target code, remaining return level |
| `fail message`, `arity usage` | Set error completion and diagnostic in interpreter state |
| `eval_script "$text"` | Evaluate in the current frame, returning through state |
| `vget "$name"`, `vset "$name" "$value"` | Read/write a variable using current-frame/global-alias rules |
| `quote_list "${values[@]}"` | Encode literal values into a proper list in `R` |
| `load_sdk` | Load only `core.tcl` in the current frame |
| `main "$@"` | Initialize globals and run a script, or answer `--version`; return a launcher status |

Use the embedding shell with `errexit` and `nounset` disabled. Internal shell
statuses are not language completion codes. Do not use `$(eval_script ...)`
to obtain a result: a Bash subshell would lose state. Read `R` and `C` in the
same shell instead. Internal state is not a secret store against Sycol scripts.

### PowerShell

```powershell
. /path/to/project/.sycol/bin/sycol.ps1
Register-SyNative host.echo {
    param([string[]]$Words)
    if ($Words.Count -ne 1) { Set-SyArity 'host.echo value'; return }
    $script:Sy.R=$Words[0]; $script:Sy.C=0
}
exit (Start-Sycol ([string[]]$args))
```

| Host interface | Contract |
| --- | --- |
| `Register-SyNative name scriptblock` | Register/replace a handler whose first parameter is a string array |
| `$script:Sy.R`, `.C`, `.RC`, `.RL` | Equivalent result/completion/return state |
| `Set-SyError message`, `Set-SyArity usage` | Set error completion and diagnostic |
| `Invoke-SyScript $text` | Evaluate in the current frame |
| `Get-SyVariable $name`, `Set-SyVariable $name $value` | Read/write using interpreter variable rules |
| `ConvertTo-SyList $words` | Encode a string array into a proper list in `.R` |
| `Import-SySdk` | Load only `core.tcl` in the current frame |
| `Start-Sycol ([string[]]$args)` | Initialize globals and run a script, or answer `--version`; return a launcher status |

On-demand native files must declare persistent helpers using `function script:Name`.
Handlers must catch host exceptions and call `Set-SyError`. Suppress unrelated
pipeline output; `puts` explicitly writes to the console. Native command name
lookup remains case-sensitive despite PowerShell's usual conventions.

Sourcing either backend loads only native core handlers without launching a script or
initializing script startup globals. Search-path globals are already available. An embedder can evaluate against native handlers
alone or explicitly load the SDK. Non-integer `lindex` notation depends on the
SDK's index helper. `load_sdk`/`Import-SySdk` use the current frame; normal
launcher startup uses global. Account for `exit` terminating the embedding host.

## Completion propagation

Shared control procedures evaluate bodies in the caller with `uplevel 1`.
When they catch an exceptional completion, they must preserve its value,
target code, and level. To cross one added wrapper procedure boundary:

```tcl
return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value
```

For an ordinary error this produces the error after leaving the wrapper;
for a pending return it retains the caller's requested target and level.
Returning just `$value` would silently turn an error/break/return into normal
completion. See `.sycol/lib/core.tcl` for loop and lazy-operator examples.

## Internal command reference

These commands are callable but serve the SDK implementation. Applications
should use public list and `file` commands. They are implementation contracts,
not substitutes for public option parsing or validation.

### Native filesystem primitive

All `sy.file` signatures below use literal arguments. `force` and
`intoDirectory` flags are `0` or `1`; the SDK computes them.

| Signature | Result/behavior |
| --- | --- |
| `sy.file windows` | `1` for Windows path rules, otherwise `0` |
| `sy.file expand path` | Host-normalized path with supported home expansion; no file creation |
| `sy.file list path` | Proper list of immediate entry names |
| `sy.file type path` | Type name for the final entry itself |
| `sy.file exists path` | Existence predicate, `0` or `1`, following links |
| `sy.file isfile path` | Regular-file predicate, `0` or `1`, following links |
| `sy.file isdirectory path` | Directory predicate, `0` or `1`, following links |
| `sy.file size path` | Decimal byte length |
| `sy.file mkdir path` | Create one directory path and parents; return empty |
| `sy.file delete path force` | Delete one entry with the selected force policy; return empty |
| `sy.file copy source target force intoDirectory` | Copy one entry, adding source basename when `intoDirectory` is `1`; return empty |
| `sy.file rename source target force intoDirectory` | Move one entry with the same destination policy; return empty |

Filesystem errors are catchable. Public `file` handles abbreviations, options,
multi-path iteration, and cross-platform path helper dispatch.

### Shared helpers

The `windows` parameter below is `0` or `1`, explicitly selecting path rules.
`names`, `paths`, and returned component collections are encoded lists.

| Signature | Result/behavior |
| --- | --- |
| `sy.list.index index length` | Resolve decimal/end/index arithmetic to an integer using `length - 1` for `end`. Insertion callers pass actual length plus one. Does not clamp to bounds. |
| `sy.path.parts path windows` | Two-element list `root names`: recognized root and list of remaining components |
| `sy.path.type path windows` | Lexical `absolute`, `relative`, or `volumerelative` classification |
| `sy.path.render root names` | Compose a path from root and components, using `/` separators |
| `sy.path.join paths windows` | Join a list of paths with rooted/home-component reset rules |
| `sy.path.dropfirst names` | Return the component list without its first element |
| `sy.path.component operation path windows` | For `dirname`/`tail`, return the selected parent/final component, including bare-home handling |
| `sy.path.extension operation path windows` | For `extension`/`rootname`, return the extension or original path minus its extension |

The test-only `test.time name script` helper is documented in
[testing and development](development.md#timing-reports); it is not shipped
as a normal interpreter command.
