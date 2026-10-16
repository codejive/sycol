# Sycol specification, version 0.1

## 1. Purpose and constraints

Sycol is a small Tcl-like interpreter for file-based shell scripts. The two
reference implementations are ordinary Bash and PowerShell scripts. They must
agree on the language, completion semantics, native command contracts, shared
SDK, and test results. Picol is an inspiration for scope and simplicity; Sycol
is an independent implementation and is not a drop-in Tcl or Picol runtime.

The design minimizes *duplicated host-language mechanisms*, rather than
minifying source. It has one character parser, a list mode of that parser,
string values, a command dispatcher, variable frames, and explicit completion
state. There is no AST, bytecode, object system, typed object representation,
expression grammar, or dependency manager. Host arithmetic is used only after
strict decimal validation. Host shell source evaluation is never used to
execute Sycol code.

Runtime targets are Bash 3.2+ with signed 64-bit arithmetic, Windows PowerShell
5.1 on .NET Framework, and PowerShell 7+ on .NET. Bash uses indexed arrays,
not associative arrays, namerefs, `mapfile`, or external parsing utilities.
PowerShell avoids classes, ternary expressions, null operators, and requiring
`ProcessStartInfo.ArgumentList`, which older .NET does not provide.

The files shipped together are:

| File | Responsibility |
| --- | --- |
| `sycol`, `sycol.bat` | Project-local launchers |
| `.sycol/bin/sycol` | Executable Bash parser, evaluator, native registry, file launcher |
| `.sycol/bin/sycol.ps1` | PowerShell implementation of the same contract |
| `.sycol/bin/sycol.bat` | CMD launcher for the adjacent PowerShell implementation |
| `.sycol/VERSION` | Single source for the Sycol project/release version |
| `.sycol/native/core.sh`, `.sycol/native/core.ps1` | Registered built-in native handlers |
| `.sycol/sdk/*.tcl` | Shared SDK procedures, grouped by responsibility |
| `tests/all.tcl` | Shared language and SDK conformance tests |
| `tests/exec.tcl` | Shared process tests using small host probes |
| `tests/run.sh`, `tests/run.ps1` | Temporary directories, host invocation, cleanup |

No subprocess is needed for parsing, procedures, lists, arithmetic, or SDK
loading. `exec` necessarily starts a child process. Tests may use host tools;
these are not interpreter runtime dependencies.

## 2. Invocation and lifecycle

```
sycol SCRIPT [ARG ...]
sycol --version
powershell -NoProfile -File .sycol/bin/sycol.ps1 SCRIPT [ARG ...]
pwsh -NoProfile -File .sycol/bin/sycol.ps1 SCRIPT [ARG ...]
sycol.bat SCRIPT [ARG ...]
```

The Bash file `sycol` is executable and starts with `#!/usr/bin/env bash`.
Use `./sycol` from its directory, or `sycol` when its directory is on `PATH`.
Explicit `bash /path/to/sycol` invocation is also supported. Keep `.sycol/`
beside the root wrappers. The root Bash wrapper uses `exec` and forwards
`"$@"`; both root wrappers locate the implementation relative to themselves
without changing the working directory. Embedding must source the actual
implementation in `.sycol/bin/`, not a root wrapper.

The `.sycol/` directory is also a standalone distribution: add `.sycol/bin/`
to `PATH` for Bash, PowerShell, or CMD invocation. PowerShell on Windows selects
the `.ps1` entry point; CMD selects `.bat`. On other platforms, PowerShell users
can explicitly invoke `sycol.ps1` on `PATH`. Both batch entry points use Windows
PowerShell, with `-NoProfile -ExecutionPolicy Bypass` scoped to that process,
and preserve its exit status. The root batch wrapper transfers control to the
inner batch file without `CALL`; both disable delayed expansion internally.

Argument boundaries are preserved after the invoking shell and Windows
command-line parsing. CMD callers must quote metacharacters, supply empty
arguments as `""`, escape literal quotes as `\"`, and double trailing
backslashes before a closing quote for the Windows PowerShell parser.
CMD percent expansion and caller-side delayed expansion still apply; wrappers
cannot recover text already expanded by the caller. Literal quotes combined
with CMD metacharacters require escaping for each batch parsing pass; arbitrary
string forwarding through `.bat` is not guaranteed. Direct PowerShell `.ps1`
invocation bypasses CMD and preserves its string arguments, including empty
strings and embedded quotes.

The sole launcher option is `--version`: as the only argument, it prints the
release version followed by a newline and exits 0 without loading the SDK or a
script. Extra arguments after this option print usage to stderr and exit 2.
Otherwise the first argument is a filename; use `./--version` for a script
literally named `--version`. Arguments after a script filename remain literal.
Missing the first argument prints usage to stderr and exits 2. Sourcing the interpreter
registers native handlers from `.sycol/native/`. Startup initializes global
variables, sources the SDK files in `.sycol/sdk/`, then sources the requested
script in the global frame. Library paths resolve relative to the interpreter
file, even if an embedded caller changes the working directory before startup.
Failure to discover or load a library, or to load the requested script, is fatal.
The final script value is not printed automatically. `puts` produces output.

| Global variable | Initial value |
| --- | --- |
| `argv0` | Script filename as passed to the launcher |
| `argc` | Number of remaining arguments, in decimal |
| `argv` | Proper list of remaining arguments, preserving word boundaries |
| `sycol_host` | `bash` or `powershell` |
| `sycol_version` | Release version read from the installation's `.sycol/VERSION` |

Maintain the project/release version by editing `.sycol/VERSION` (initially
`0.1.0`), including it in every distribution. It contains a single ASCII token
starting with a digit and using only letters, digits, `.`, `+`, and `-`, with
an optional LF or CRLF terminator. Both query interfaces read that same file
relative to the interpreter, independently of the working directory. A missing,
unreadable, empty, or invalid version file fails startup or `--version` with
exit 1 and a diagnostic on stderr. The release version is separate from this
document's specification version. The manual GitHub Actions release process
writes the requested stable `MAJOR.MINOR.PATCH` version to this file, tests it,
and publishes ZIP/TGZ distributions and tag `vVERSION` from the versioned
commit. This release-input policy does not narrow the runtime's accepted
version-file format. See [RELEASE.md](RELEASE.md) for the maintainer procedure.
Tcl code can read `$::sycol_version` from any
procedure; like other startup globals, it is an ordinary mutable variable.
Embedding by sourcing alone does not initialize it; `main`/`Start-Sycol` does.

Successful completion exits 0. An uncaught error or unresolved return, break,
or continue exits 1 with `sycol: VALUE (completion CODE)` on stderr. A normal
top-level `return` ends the script successfully through the `source` boundary.
`exit ?status?` immediately terminates the host process, defaulting to 0.
The status must be a decimal integer in 0..255 for portable shell behavior.
Invalid arguments are catchable errors. A valid `exit` is not a completion code:
it cannot be intercepted by `catch`, procedures, or `source`, and prints no
diagnostic. Embedded applications must account for it terminating their host.
There is no REPL, stdin script mode, or `-c` mode.

All relative file paths, including nested `source` paths, resolve against the
current working directory. Sourcing a file does not change that directory.

## 3. Values and parsing

Every value is a string. Lists are strings with a reversible encoding, not a
second value type. Names and string equality are case-sensitive. An empty
script and an empty procedure body return the empty string.

A script is a sequence of commands. Spaces, tabs, and CR separate words; LF
and semicolon separate commands when outside braces, quotes, and nested command
substitutions. Each command's first word is its name; remaining words are
literal argument strings after substitution. Empty commands are ignored.
The result of a script is the last executed command's result.

* A word beginning with `{` ends at its matching `}`. Braces nest. No variable
  or command substitution occurs. Backslashes are retained, and a backslash
  shields the following brace from nesting. Backslash-LF folding is the one
  substitution that still occurs here.
* A word beginning with `"` ends at the next unescaped `"`. Whitespace and
  command separators are ordinary characters inside it. Substitutions apply.
* Other words extend to an unquoted word or command separator. Substitutions
  apply; braces and quotes encountered *after* the first character are literal.
* A closing word brace or quote must be followed by a separator, the closing
  bracket of an enclosing substitution, or end of script. `{a}b` and `"a"b`
  are errors. Bare words may concatenate literal text with substitutions.
* `$name` reads a variable, consuming ASCII letters, digits, underscores, and
  colons. `${name}` reads an arbitrary nonempty name through the next `}`.
  A bare `$` without a name is literal. Missing variables are errors.
* `[script]` evaluates a nested script in the same variable frame and inserts
  its result. Braces and quotes shield `]` appropriately. An unmatched bracket,
  brace, quote, variable brace, or final backslash is an error.
* Outside braces, `\n`, `\r`, and `\t` become LF, CR, and tab. Backslash before
  any other character removes the backslash and quotes that character.
* Backslash-LF followed by zero or more spaces/tabs folds to one space. Between
  bare words it acts as a separator; inside quotes or braces it stays within
  the word. Files sourced from disk normalize CRLF to LF before parsing.
* `#` begins a comment only where the first word of a command would start.
  Comments continue to LF; a backslash-LF continues the comment onto the next
  physical line. Elsewhere `#` is literal.

Substitutions are left-to-right and execute once. They never cause implicit
word splitting, globbing, second substitution, or shell evaluation. For example:

```tcl
set text {a b; error nope}
set copy $text             ;# One value, no execution of its contents.
set words [list $text {}]  ;# Two elements, including the empty string.
```

Parsing and evaluation are incremental: earlier commands can run before a later
syntax error is found. There is no whole-file syntax prevalidation or rollback;
NUL checks happen before evaluation.

## 4. Frames, procedures, and dispatch

The interpreter owns a global variable frame, a table of script procedures,
and a registry of native handlers. A procedure call allocates a local frame
whose parent is the calling frame. Locals are destroyed on every exit path.
Procedures themselves are globally registered, including definitions made
inside another procedure. There are no closures or namespaces.

An unqualified variable name refers only to the current frame. It does not
search calling frames or fall back to globals. Prefix `::` selects the global
frame; `global` installs a local alias. Only a leading `::` is special:
internal colons are ordinary name characters. An empty variable name is an
error. Braced variable names and `set` permit names containing spaces.

`proc name arguments body` defines or replaces a procedure. `arguments` is a
list whose elements are either a one-element parameter name or a two-element
`{name default}` list. Parameter names must be nonempty and must not begin
with `::`. A final parameter named `args` collects all remaining arguments as
a proper list, including zero arguments. Missing required or excess arguments
are errors. Defaults are literal strings and are not evaluated.

Dispatch checks script procedures, then registered native handlers. Built-in
primitives use the same registry as native extensions. Script definitions may
override built-ins and SDK procedures. There is no implicit `unknown` handler
or OS command fallback.
There is no command deletion, command-renaming operation, or introspection subsystem.

## 5. Completion semantics

Every evaluation returns a value and a completion code:

| Code | Meaning |
| --- | --- |
| 0 | Normal completion |
| 1 | Error; value is an error message |
| 2 | Return in progress; also carries target code and remaining level |
| 3 | Break |
| 4 | Continue |

Nonzero completions immediately stop the current script, including during
substitution. Evaluation propagates them until a command explicitly handles
them. `catch` handles all five. `while` consumes break and continue from its
body; it returns the empty string when it terminates. `if`, `eval`, and
`uplevel` propagate completions without adding return boundaries.

`return ?-code n? ?-level n? ?value?` defaults to target code 0, level 1, and an
empty value. Codes must be numeric 0..4 and levels 0..128. Each procedure or
`source` boundary decrements a pending return's level. At zero, the target
completion becomes effective. Target code 2 creates a fresh ordinary return
after that boundary. Level zero makes the requested completion effective
immediately. There are no symbolic codes or `return -options` option.

`catch script ?resultVar? ?optionsVar?` evaluates in the current frame, stores
its result if requested, and returns its numeric completion code normally.
Options are a four-element list, always `-code CODE -level LEVEL`. For code 2,
these describe the pending return; otherwise they contain the actual code and
level zero. An invalid output variable name can itself make `catch` fail.

SDK control procedures that evaluate caller scripts must preserve this metadata.
After catching into `value` and `options`, propagate through one extra procedure
boundary with:

```tcl
return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value
```

This is why `foreach` and `for` can live in Tcl while still propagating a return
from their caller's body correctly. The native state consists of result, code,
pending return code, and pending level; host exceptions or Bash exit statuses
are not used as language completion codes.

Evaluation nesting is limited to 64 simultaneously active script evaluations.
This includes substitutions, procedure bodies, `eval`, and control bodies.
Exceeding it is a catchable error. Input length, loop count, output size, and
time are otherwise unbounded subject to host resources. This is a trusted-script
runtime, not a security sandbox.

## 6. Native command contracts

These commands constitute the irreducible host layer in this version. All
listed argument counts are checked; extra arguments are errors. Commands that
do not return a meaningful value return the empty string.

| Command | Behavior |
| --- | --- |
| `set name ?value?` | Read or write a variable; returns its value |
| `unset name` | Remove an existing variable; missing variable is an error |
| `global ?name ...?` | Alias names to global variables; does not create their values |
| `proc name arguments body` | Define or replace a script procedure |
| `eval script` | Evaluate exactly one script string in the current frame |
| `uplevel level script` | Evaluate in an ancestor frame; nonnegative decimal level, or `#0` for global |
| `catch script ?resultVar? ?optionsVar?` | Capture completion, as above |
| `return ?-code n? ?-level n? ?value?` | Request completion through boundaries |
| `break`, `continue` | Produce code 3 or 4 |
| `error message` | Produce code 1 with that message |
| `if boolean body ?else body?` | Evaluate one selected body in the same frame |
| `while testScript body` | Reevaluate a script condition before every iteration |
| `list ?value ...?` | Encode values into a reversible list |
| `llength list` | Parse and count list elements |
| `lindex list index` | Nonnegative decimal index; negative/out-of-range returns empty |
| `string length value` | Return string length in host character units |
| `string equal a b` | Exact case-sensitive equality; return 0 or 1 |
| `string range value first last` | Inclusive decimal bounds, clamped to the string; empty if disjoint |
| `+`, `-`, `*`, `/`, `%` | Exactly two signed decimal integer operands |
| `<`, `<=`, `>`, `>=`, `==`, `!=` | Two integer operands; return 0 or 1 |
| `! integer` | Numeric logical negation; return 0 or 1 |
| `puts ?-nonewline? value` | Write literal text to stdout, optionally without a newline |
| `source path` | Read and evaluate a script in the current frame; adds a return boundary |
| `readfile path` | Read an entire UTF-8 text file without evaluating it |
| `writefile path text` | Overwrite/create a UTF-8 text file; add no newline or BOM |
| `pwd` | Return the current working directory in host path format |
| `cd path` | Change the host's working directory |
| `getenv name` | Read a process environment variable; absent is empty |
| `exec ?-capture? ?--? program ?arg ...?` | Execute one external program, detailed below |
| `exit ?status?` | Immediately terminate the process with status 0..255; default 0 |
| `sy.file operation arguments...` | Host filesystem primitive used by the shared `file` procedure, detailed below |

### Conditions and arithmetic

`if` takes an already computed boolean value; `while` takes a script that
produces one. `for` also takes a script condition. Booleans accepted by control
commands are case-sensitive `true`, `false`, or signed decimal integers (zero
false, otherwise true). Numeric `!` accepts only integers.

```tcl
if [< $n 10] { puts small } else { puts large }
while {< $n 10} { incr n }
```

There is **no `expr`**, floating point, infix operator, implicit expression
evaluation, or special expression quoting. `if {< $n 10} ...` is invalid because
that argument is a script string rather than a boolean value. `elseif` and
optional Tcl words such as `then` and `do` are not implemented; nest `if` in an
`else` body when needed.

Integer operands and results are signed 32-bit, -2147483648..2147483647. Leading
zeros always mean decimal. Whitespace, hex, exponent notation, variable names,
and host arithmetic syntax are rejected. Both input and result overflow are
catchable errors. Division truncates toward zero, and remainder has the
dividend's sign. Zero divisors fail. Operations are binary; use `[- 0 $n]` to
negate. String comparisons use `eq`/`ne` or `string equal`, not numeric `==`.

### Lists

List parsing uses the word parser with variable and command substitution
disabled. Braces, quotes, escapes, and whitespace delimit elements; semicolon
and brackets are literal characters. A list containing malformed quoting is
an error. `list` encodes empty values as `{}`, otherwise backslash-escapes
whitespace and script-special characters. `lindex` returns decoded values.
Canonical encoding is identical on both hosts. General Tcl scripts may use
other equivalent encodings; compare decoded elements when representation is
not relevant.

There is no `{*}` word expansion. Use `apply command argumentList` from the SDK.
Never construct executable scripts by concatenating unquoted untrusted strings;
use `list`/`concat` to retain argument boundaries.

### Text I/O and external commands

File commands handle whole text files, close handles before returning, and use
UTF-8. Authors must save all `.tcl` source files as UTF-8, including the entry
script, SDK files, and files loaded by `source` (regardless of their
extension). This is an authoring requirement: the runtime does not validate or
enforce UTF-8 encoding. Behavior for malformed UTF-8 or other encodings is
unspecified and may differ between hosts. A leading UTF-8 BOM is accepted and
removed when reading. NUL in text files is an error. Source additionally
normalizes CRLF to LF; `readfile` retains line endings. Parent directories are
not created by `writefile`. I/O failures
are catchable language errors.

`exec ?-capture? ?--? program ?arg ...?` resolves an external executable using
its explicit path or host PATH. Only an initial `-capture` is an option; an
optional `--` after it (or as the first argument) ends option recognition.
All words after the program are literal arguments, including `-capture`, `--`,
and Tcl redirection syntax. Use `--` to invoke a program named `-capture` or `--`.
Shell aliases, functions, and built-ins are not commands for this purpose.
Each Sycol word becomes one OS argument, including empty strings. There is no
implicit shell, interpolation, globbing, pipeline, redirection, background job,
or expansion of `$HOME`. Environment, stdin, and current working directory
are inherited. Without `-capture`, stderr is also inherited and stdout is
captured as text. On success,
one final LF, including an immediately preceding CR if present, is removed.
Other trailing newlines and a lone trailing CR are retained.

Without `-capture`, a nonzero exit is an error `process exited with status N`;
captured stdout is discarded and stderr has already been streamed. Failure to launch is an error
`cannot execute: PROGRAM`.

`-capture` is a Sycol extension, not a full Tcl option. It returns a proper
three-element list: `status stdout stderr`. A nonzero child exit status returns
normally rather than raising a language error. Both streams retain all trailing
LF and CR characters, including CRLF; stderr is captured rather than streamed.
The status is the host-reported decimal process status. Signal termination has
no portable metadata: Bash normally reports `128 + signal`; PowerShell reports
the platform process exit code. No ordering between the two streams is exposed.
Wrong arguments, executable lookup/start failures, and capture I/O failures
remain errors. Capture I/O failures report `cannot capture process output`.
As with plain `exec`, Bash executable-loader failures after successful lookup
can appear as child statuses (typically 126 or 127), with host diagnostics.
The existing UTF-8-without-NUL text domain applies to both output streams.

Bash capture uses a private temporary directory under `${TMPDIR:-/tmp}` and
requires standard `mktemp`, `cat`, `rm`, and `rmdir` utilities on PATH. It reads
both files after the child exits and removes them before returning. PowerShell
drains both redirected streams concurrently using .NET asynchronous readers.
Neither mode exposes a timeout or a process handle. Programs that require
a terminal should be launched through a custom native extension.

Windows PowerShell passes arguments using .NET process APIs, not its native
pipeline argument conversion. On older .NET, the interpreter quotes the
Windows command line using the CRT convention, preserving empty arguments,
embedded quotes, and final backslashes. Programs with custom Windows command
line parsers may interpret those strings differently. Unix PowerShell uses
`ArgumentList`. Bash invokes the resolved executable with `"$@"`.

Examples (assuming those executables are installed):

```tcl
puts [exec git status --short]
set filename {file with spaces.txt}
puts [exec git log -1 -- $filename]
set result [exec -capture -- git status --short]
puts "status: [lindex $result 0]"
puts -nonewline [lindex $result 1]
puts -nonewline [lindex $result 2]
# An OS shell is available only when explicitly requested:
puts [exec bash -c {printf '%s\n' "$HOME"}]
```

Environment names for `getenv` must match `[A-Za-z_][A-Za-z0-9_]*`. Environment
lookup inherits the host's case sensitivity. Sycol variable assignment does not
export environment variables.

## 7. Shared Tcl SDK

The launcher loads the SDK from all direct `.tcl` files in `.sycol/sdk/` before
the requested script. The shipped files are `control.tcl`, `files.tcl`, `lists.tcl`, `paths.tcl`,
`strings.tcl`, and `variables.tcl`. Applications extend it by defining
procedures or sourcing additional files. No host dispatcher change is needed
to add a Tcl procedure.

| Procedure | Contract |
| --- | --- |
| `incr name ?amount?` | Update an existing caller variable by an integer amount (default 1); return new value |
| `append name ?value ...?` | Concatenate to a caller variable, creating it if absent; return value |
| `lappend name ?value ...?` | Append list elements to a caller variable, creating it if absent; validate existing list |
| `concat ?list ...?` | Flatten one list level and return a canonical list |
| `join list ?separator?` | Join decoded elements, default separator one space |
| `foreach name list body` | Set one caller variable per element and evaluate body there; handle break/continue |
| `for initial test step body` | Evaluate initial once, test before every iteration, step after body/continue, in caller frame |
| `eq a b`, `ne a b` | String equality/inequality returning 0 or 1 |
| `and leftScript rightScript` | Lazy logical conjunction in caller frame, returning 0 or 1 |
| `or leftScript rightScript` | Lazy logical disjunction in caller frame, returning 0 or 1 |
| `apply command arguments` | Invoke one named command with elements of a list as its arguments, in caller frame |
| `file list ?path?` | List immediate entry names, including hidden entries; default `.`; exclude `.` and `..`; order unspecified |
| `file type path` | Return Tcl's file type name: `file`, `directory`, `link`, `characterSpecial`, `blockSpecial`, `fifo`, or `socket`; missing paths are errors |
| `file delete ?-force? ?--? ?path ...?` | Delete entries in order; missing paths succeed; nonempty directories require `-force`; read-only files can be removed without `-force` |
| `file copy ?-force? ?--? source ?source ...? target` | Recursively copy entries, preserving supported attributes; existing directory targets receive sources under their basenames; replacement requires `-force` |
| `file rename ?-force? ?--? source ?source ...? target` | Move entries in order; directory targets receive sources under their basenames; existing entries require `-force`; cross-filesystem moves use copy/delete when needed |
| `file mkdir ?path ...?` | Create directories and missing parents; existing directories succeed; stop at the first error |
| `file exists path`, `file isfile path`, `file isdirectory path` | Return 0 or 1, following links; missing or inaccessible paths return 0 |
| `file size path` | Return byte length as a decimal string, following links; missing paths fail |
| `file join name ?name ...?` | Join path components using Tcl's host path rules and `/` separators; a rooted or leading-home component resets earlier components |
| `file pathtype path` | Classify a path lexically as `absolute`, `relative`, or `volumerelative` using the host's path rules |
| `file dirname path`, `file tail path` | Return the parent or final component using host path rules, ignoring trailing separators |
| `file extension path`, `file rootname path` | Return the final extension (including its dot), or the original path with that extension removed |

### Filesystem operations

Paths have no wildcard, environment expansion, or implicit shell evaluation.
For filesystem operations, `~` and `~/...` expand to the current user's home,
using HOME, then USERPROFILE where applicable, or the host's home-directory API.
Named-user `~user` lookup is not supported: it would require additional account
lookup mechanisms across the supported hosts. Pass an explicit path instead.
The `file list` extension is unchanged: it takes a literal directory path,
returns names as a proper list, includes hidden entries, follows a link to the
directory, and returns an empty list for an empty directory.

Copy, rename, and delete accept only `-force` and `--`, preceding paths. Repeated `-force`
is allowed. Use `--` before a path beginning with `-`. Unknown options and wrong
argument counts are errors. `-recursive` and `-attributes` are not supported;
recursion and metadata preservation follow Tcl's defaults instead. Deleting
zero paths or an empty path succeeds. An empty source or target for copy is an
error. Tcl-compatible subcommand abbreviations start with `co`, `de`, `ty`,
`mk`, `exi`, `isf`, `isd`, `j`, `di`, `ta`, `ext`, `ro`, `si`, `ren`, and `p` for the
supported operations. Ambiguous prefixes such as `c`, `d`, and `t` fail.
`file pathtype` does not access the filesystem or require the path to exist.
Empty paths are relative; leading `~` (including `~user`) is absolute without
performing home lookup. On Unix, leading `/` is absolute. On Windows, drive-rooted
paths such as `C:/data` and UNC paths containing server and share are absolute;
`C:data`, `C:`, and paths rooted on the current drive such as `/data` or `\data`
are `volumerelative`. Other paths are relative.
`file type` examines the entry itself, including dangling links. Trailing
directory separators are ignored when identifying the final entry.

Delete and copy operate on the final link itself, including links encountered
inside recursive trees, rather than traversing its target. Copying symbolic
links requires host link-creation support and permissions; unsupported link
types or creation failures are errors. If the copy target is an existing
directory (including a link to a directory), each source is copied inside it
under its basename. Otherwise exactly one source is required and the target
is its new path. Target parents must already exist. Existing entries require
`-force`; directory trees are never merged, even when the existing destination
tree is empty. A directory cannot replace a file or link, and a file or link
cannot replace a directory. `-force` can replace a final symbolic link without
changing its referent. Paths are processed in argument order, stopping on the
first error without rolling back earlier changes. Missing delete paths are
ignored, with or without `-force`. Force deletion attempts to adjust permissions
and move cwd outside the deleted tree when necessary.

Copying a file onto itself or a directory into its descendant fails. Tcl's
same-file handling varies by host; Sycol consistently rejects it. Operations
are not transactional: failures may leave a partially copied or deleted tree.

Copy preserves modification/access timestamps and native file attributes by
default. Bash uses `cp -p` (including Unix permissions); PowerShell preserves
.NET file attributes and Unix permission bits where applicable. Metadata outside the host's native
support, ACLs, ownership, and cross-platform permission translation are not
portable guarantees. Native filesystems are supported; Tcl virtual filesystems
and portable copying of special filesystem objects are outside this subset.
Use a native extension for operations requiring those facilities.

Rename first attempts a native move. Across filesystems it falls back to copying
and then deleting the source, matching Tcl's approach. The source is removed
only after the copy completes successfully. Such a move is not atomic: a copy
failure may leave a partial destination, and a source-deletion failure leaves
both copies and reports an error. `-force` can replace an empty destination
directory with a directory, but cannot merge a nonempty destination tree or
replace a directory with a file (or vice versa). A forced rename onto the same
entry succeeds without changing it. Argument order and stop-on-error behavior
are the same as copy. Windows volume changes are handled by the existing
copy/delete helpers; Bash uses the standard `mv` utility's fallback. Native
cross-device errors on the same path root also enable the PowerShell fallback.

Predicates follow links: a dangling link has type `link` but `exists`, `isfile`,
and `isdirectory` return 0. `mkdir` accepts literal arguments, not option
switches; zero arguments succeeds, but an empty pathname is an error. File
size is measured in bytes, independently of text encoding or Sycol string
length. Size results can exceed the arithmetic core's signed 32-bit range;
such values remain valid strings. Directory sizes are host-dependent (0 on
Windows PowerShell); use size primarily for regular files.

Path helpers live in the shared `paths.tcl` SDK and do not access the filesystem,
except that dirname/tail expand a bare home name such as `~`, as Tcl 8.6 does.
They do not resolve `.` or `..` or symbolic links. Unix recognizes `/`; Windows
also recognizes backslashes, drive-relative paths such as `C:foo`, drive roots,
and UNC share roots. Joins collapse repeated separators and discard trailing
separators except roots and bare home prefixes; other dot components remain.
Tail prefixes a literal leading tilde with `./` to distinguish it from a home
name. Extension/rootname operate on the original path: dotfiles have an
extension, and a trailing separator means there is no extension. Rootname
preserves the original separators. Other than bare-home dirname/tail handling,
these helpers need not refer to an existing entry.

The native primitive accepts `sy.file windows`, `sy.file expand path`,
`sy.file list path`, `sy.file type path`, `sy.file exists path`,
`sy.file isfile path`, `sy.file isdirectory path`, `sy.file mkdir path`,
`sy.file size path`, `sy.file delete path force`, and
`sy.file copy|rename source target force intoDirectory`; flag values are `0`
or `1`. Applications should use the SDK `file` interface. Bash filesystem
mutation requires the standard `cp`, `mv`, `mkdir`, `rm`, `rmdir`, and `chmod`
utilities on PATH; size uses GNU or BSD `stat`. Listing and type checks use shell built-ins. PowerShell uses filesystem APIs;
on Unix it also uses standard `stat` (GNU or BSD syntax) and `chmod` utilities
to support file types and permission preservation on older supported .NET versions.
Host I/O failures become catchable errors; host tools may also write diagnostics
to stderr. Native filesystem handlers ship in `native/files.sh` and
`native/files.ps1` alongside the existing core handlers.

These existing operations follow Tcl's `file` API within the limits above;
other Tcl file subcommands are not implemented. `file list` remains a Sycol
extension without introducing Tcl's globbing interface.

### Control procedures

`foreach` and `for` return empty on normal termination. Loop variables persist
in the caller. `foreach` supports one variable and one list, not Tcl's multiple
parallel lists. `for` consumes break from body or step; continue from body runs
the step. Other exceptional completions propagate, including those from its
initialization, test, or step. `and`/`or` skip their right script when possible
and propagate exceptional completions. These are script operators, not eager
value operators.

`apply` here is deliberately a named-command/list invocation helper; it is
**not Tcl's lambda-based `apply`**. `eval` likewise accepts exactly one script,
not multiple strings to concatenate. These explicit differences keep the core
and safe invocation interface small.

Add application procedures naturally:

```tcl
# app/sdk.tcl
proc twice {n} { * 2 $n }
proc git-status {} { exec git status --short }

# app/main.tcl
source app/sdk.tcl
puts [twice 21]
puts [git-status]
```

## 8. Native extension and embedding interface

Native extensions are trusted host code. They receive already decoded strings
and set the interpreter's result/completion explicitly. They must validate
arity, preserve caller frames, avoid unrequested stdout output, and translate
host failures into code 1. The interpreter sources all direct `.sh` files
(Bash) or dot-sources all direct `.ps1` files (PowerShell) in `.sycol/native/`
when the interpreter itself is sourced. The shipped `core.sh` and `core.ps1`
have no special filename treatment. Additional native files should only define
helpers and register handlers, without invoking Sycol commands during loading.
A custom launcher can also register handlers after sourcing the interpreter
and before calling `main` or `Start-Sycol`.

Both native and SDK discovery ignore subdirectories, filenames beginning with
`.`, and files with another extension. Extensions are matched case-sensitively.
Files load alphabetically with locale-independent sorting: C-locale glob order
on Bash and ordinal string order on PowerShell. Use lowercase ASCII library
filenames for identical ordering across hosts; non-ASCII filename ordering is
not portable. Neither loader maintains a hard-coded list of filenames.
Missing or unreadable library directories fail initialization; an existing
empty directory contributes no definitions. A distribution still needs its
shipped built-ins and SDK procedures to provide the specified language.
Library load failures stop loading and identify the failing file, without
rolling back definitions already installed. Native Bash files must return
success after registration; PowerShell loading treats host errors as fatal.

SDK files should only define procedures. Their bodies may refer to procedures
defined in other files, since those names resolve when called. Files must not
depend on another library file having already loaded. Repeated definitions
follow the usual replacement rules; later native registrations replace earlier
ones, and script procedures take precedence over every native handler.
There is no recursive discovery, configurable module search path, or automatic
loading of host files from the user's working directory.

Bash:

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

`R` is the value, `C` is the completion, `RC`/`RL` carry pending return code and
level. `eval_script "$text"` evaluates in the current frame. `vget`/`vset`
access variables; `quote_list` encodes literal arguments into `R`. No result
is obtained using `$(eval_script ...)`, since a Bash subshell would lose state.
Native handlers are Bash function names supplied by trusted host code. Use
the interpreter in a shell with `errexit` and `nounset` disabled; internal
shell statuses are not language completion codes. Do not put host secrets
into internal state unless Sycol scripts are allowed to access them.

PowerShell:

```powershell
. /path/to/project/.sycol/bin/sycol.ps1
Register-SyNative host.echo {
    param([string[]]$Words)
    if ($Words.Count -ne 1) { Set-SyArity 'host.echo value'; return }
    $script:Sy.R=$Words[0]; $script:Sy.C=0
}
exit (Start-Sycol ([string[]]$args))
```

`$script:Sy.R`, `.C`, `.RC`, `.RL` are the equivalent state.
`Invoke-SyScript`, `Get-SyVariable`, `Set-SyVariable`, and `ConvertTo-SyList`
are the corresponding helpers. A handler receives a string array as its first
parameter and must not emit pipeline objects; `puts` uses console output
explicitly. Catch host exceptions and call `Set-SyError` yourself.

Both files can be sourced without launching a script. An embedded caller may
use the evaluator with native handlers but without the SDK, or explicitly load
the SDK with `load_sdk` (Bash) or `Import-SySdk` (PowerShell). These helpers load
in the current frame; normal launcher startup uses the global frame.
They expose one mutable interpreter instance per sourcing, not a reentrant,
thread-safe API. Native extension lookup is case-sensitive. Re-registering a
native name replaces its effective handler; a script procedure still wins.

## 9. Compatibility boundaries and non-goals

The portable text domain is valid UTF-8 without NUL. Values, filenames, source,
and process output must meet it. Binary I/O is unsupported. ASCII indexing is
identical across implementations; non-ASCII string length/range follows host
units (Bash locale characters or bytes, PowerShell UTF-16 code units). Programs
requiring portable non-ASCII indexing must provide an extension. Text values
are otherwise passed without intentional case conversion or normalization.

There are no Tcl arrays, dictionaries, namespaces, packages, regex/glob APIs,
channels, sockets, event loop, coroutines, traces, byte arrays, Unicode escape
sequences, integer bignums, floats, command introspection, or Tcl `info` commands.
Detailed Tcl error dictionaries and stack traces are not implemented. Error
messages identify the failure but need not carry source line numbers. Host
permission or executable-loader messages may additionally appear on stderr.

Full Tcl compatibility, untrusted-code sandboxing, shell pipeline syntax,
interactive job control, and competitive Tcl performance are outside version
0.1. Bash's linear indexed-table lookup deliberately trades speed for support
on old installations and fewer mechanisms.

## 10. Verification and evolution

The shared suite exercises quoting, nested substitution, malformed syntax,
list round trips, decimal boundaries, scope cleanup, recursive procedures,
return levels, loop propagation, lazy conditions, SDK commands, file loading,
file writing, arguments, and errors. Each Tcl test captures the result and
completion and checks them against an expected value. Failure counts cause a
language error and therefore a failing process status. Separate process tests
verify exact argument boundaries, newline trimming, inherited stderr, failed
exit status, capture records and preserved line endings, simultaneous large
stdout/stderr output, and current working directory using small host-specific probes.

Discovery tests copy an installation into a unique temporary directory and
verify ordering, extension filtering, argument boundaries, overrides, embedding,
empty discovery, and startup failures. Drivers clean their generated files and
empty directories, and propagate test failures. CI selects `/bin/bash` on
macOS to exercise the 3.2 target and runs Windows PowerShell 5.1 separately
from PowerShell 7. CI also checks PowerShell on Unix. Local availability of a
newer Bash does not establish that the 3.2 matrix has passed.

Any language or SDK extension must update this spec, add shared Tcl tests,
and work on both hosts. Prefer a Tcl procedure whenever the existing native
contracts suffice. Add a native primitive only for a required host facility,
an evaluator mechanism, or an operation impossible in the current subset.
Keep optional application commands in separate sourced Tcl files or trusted
native launchers.

The parsing and completion design draws on the official
[Tcl language syntax](https://www.tcl-lang.org/man/tcl8.6/TclCmd/Tcl.htm),
[Tcl return semantics](https://www.tcl-lang.org/man/tcl8.6/TclCmd/return.htm),
and the [Bash indexed-array interface](https://www.gnu.org/software/bash/manual/html_node/Arrays.html).
The explicit differences in this specification take precedence over Tcl behavior.
