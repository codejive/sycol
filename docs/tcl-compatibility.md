# Tcl compatibility

[Documentation](README.md) · [Language basics](language.md) · [Command reference](commands.md)

Sycol is an independent, string-only Tcl-like interpreter, inspired in scope
by Picol. It is not a drop-in Tcl or Picol runtime. [SPEC.md](../SPEC.md)
defines the supported contract and takes precedence over full Tcl behavior.
This page identifies the main boundaries when reading or porting Tcl code.

## Shared foundations

The language retains command-and-word syntax, braced literal words, quoted
words, `$` variable substitution, nested `[script]` substitution, procedures,
lists, explicit completion codes, and procedure/source return boundaries.
Substituted values keep their word boundaries. There is no implicit shell
evaluation, word splitting, or wildcard expansion.

Familiar names such as `set`, `proc`, `list`, `catch`, and `file` expose only
the forms in the [command reference](commands.md). Do not assume that other
Tcl options or similarly named facilities are present.

## Expressions and control flow

| Tcl usage/facility | Sycol contract |
| --- | --- |
| `expr` and infix expressions | No expression parser. Use operator commands such as `[+ $a $b]` and `[< $a $b]`. |
| Expression-taking `if` | Takes an already computed boolean: `if [< $n 10] {...}`. A braced comparison script is not a boolean. |
| Expression-taking loop tests | `while`/`for` evaluate a condition script repeatedly: `while {< $n 10} {...}`. |
| `elseif`, `then`, optional control words | Unsupported; nest `if` in an `else` body. |
| Boolean spellings | Only lowercase `true`/`false` or signed decimal 32-bit integers. Numeric `!` accepts integers only. |
| General numeric types | Signed decimal 32-bit operands/results only; no floats, bignums, hex, exponent notation, or octal interpretation of leading zeros. |
| Division/remainder | Division truncates toward zero; remainder has the dividend's sign. |
| Lazy logic in expressions | `and leftScript rightScript` and `or leftScript rightScript` are commands evaluating caller scripts lazily. |
| Parallel/multi-variable `foreach` | Exactly one variable, one list, and one body. |

Use `eq`, `ne`, or `string equal` for string comparisons. Numeric `==` and
`!=` reject non-integer operands. The arithmetic/logic command interface is
part of Sycol's design rather than an incomplete `expr` parser.

## Reduced or different command forms

| Area | Sycol contract |
| --- | --- |
| `apply` | Named-command/list invocation: `apply command argumentList`, not Tcl's lambda-based `apply`. |
| `eval` | Exactly one script argument; does not concatenate several arguments. |
| `uplevel` | Explicit level and exactly one script; nonnegative decimal levels or `#0`. |
| `unset` | Exactly one existing variable; no options. |
| `incr` | Variable must already exist. |
| `lindex` | Exactly one list and one index; no zero/multiple-index or nested-index-list forms. |
| List indices | Decimal integers, `end`, `end+N`, `end-N`, and one decimal addition/subtraction. No general expressions. |
| `string` | Only `length`, `equal`, `range`; full subcommand spelling, no options. `range` accepts decimal bounds, without `end`. |
| `concat` | Parses lists, flattens one level, and returns canonical list encoding. Do not rely on preserving the original whitespace/spelling. |
| `{*}` word expansion | Unsupported; use `apply command argumentList`. |
| `return` | Numeric `-code 0..4`, `-level 0..128`, optional value; no symbolic codes or `-options`. |
| `catch` options | A four-element list `-code CODE -level LEVEL`, not a detailed Tcl options dictionary. |
| Error information | Message and completion, without Tcl error dictionaries, error stack, or guaranteed source line numbers. |
| `puts` | stdout only, optional `-nonewline`; no channel argument. |
| Text files | Whole-file `readfile`/`writefile` and script `source`; no channel API. |
| Environment | `getenv name`; no Tcl `env` array or assignment-based export. |
| Launcher | Files only; no REPL, stdin evaluation, or `-c` mode. |

Only a leading `::` selects global variables. Internal colons are literal
name characters, not namespaces. Unqualified lookup stays in the current
frame. Procedures are global definitions without closures. Script procedures
can replace other Tcl procedures, but native handlers always win. This differs
from Tcl command replacement; same-name Tcl definitions remain hidden. There
is no package autoloading: Sycol-specific paths extend `source` lookup.
The shipped `incr`, `append`, `concat`, and `lappend` are native replacements
with portable Tcl fallbacks, available before SDK loading. Same-name Tcl
definitions remain hidden. Native replacements preserve public behavior, not
incidental internal calls such as `incr` invoking `+` or `concat` invoking
`append`; those helper calls are not extension hooks.
There is no command renaming/deletion,
introspection, or `unknown` dispatch hook.

## Process and filesystem boundaries

`exec` starts one external executable. Tcl pipeline/redirection/background
syntax, channel redirection, and implicit shell processing are unsupported;
symbols such as `|` and `>` are literal arguments. An OS shell must be invoked
explicitly if needed. The child inherits environment, stdin, and cwd.

Plain `exec` captures stdout, removes one final LF (and adjacent preceding CR),
inherits stderr, and fails on nonzero exit. The Sycol-only `-capture` option
returns `status stdout stderr`, preserving all trailing newlines and returning
normally on a nonzero child exit. See [process details](commands.md#external-processes).

Supported `file` forms follow Tcl's naming, path rules, recursive copy default,
and metadata-preservation approach within the documented host limits. Other
Tcl file subcommands are absent. `file list` is a Sycol extension returning
literal directory entry names; there is no globbing API. `-recursive` and
`-attributes` options are not supported.

Filesystem paths are literal, with supported current-user `~` expansion for
filesystem operations. Named-user `~user` lookup is unsupported; pass an
explicit path. `file pathtype` still classifies a leading tilde lexically as
absolute. Copying a file onto itself is consistently rejected, where Tcl
behavior can vary by host. Native filesystems are supported; virtual filesystems
and portable copying of special objects are outside the subset.
Full [copy, rename, delete, and path contracts](commands.md#filesystem-and-paths)
include link handling, failure behavior, and non-atomic cross-filesystem moves.

## Text and host portability

The portable domain is valid UTF-8 without NUL, covering source, values,
filenames, and process output. Binary I/O is unsupported. Save source as UTF-8;
the runtime assumes that encoding and does not validate malformed UTF-8.
A leading UTF-8 BOM is accepted. `source` normalizes CRLF to LF, whereas
`readfile` and capture-mode process output preserve line endings.

Only `\n`, `\r`, and `\t` have special backslash meanings outside braces;
other escaped characters lose their backslash. Numeric/Unicode escapes are
unsupported. Braced words retain backslashes except for backslash-LF folding.

ASCII length/range agree between backends. For non-ASCII text, Bash uses
locale characters or bytes and PowerShell uses UTF-16 code units. Supply an
extension if portable non-ASCII indexing is required. Values otherwise pass
without intentional case conversion or Unicode normalization.

Path rules, environment-name case sensitivity, directory byte sizes, link
support/permissions, available native metadata, and process signal statuses
remain host-specific. Bash normally reports signal termination as
`128 + signal`; PowerShell exposes the platform exit code. Windows executables
with custom command-line parsers may interpret arguments differently from
the CRT conventions used by the PowerShell backend.

## Facilities outside the subset

Sycol has no Tcl arrays, dictionaries, namespaces, packages, regex/glob APIs,
channels, sockets, event loop, coroutines, traces, byte arrays, Unicode escape
sequences, command introspection, or `info` commands. Native extensions can
provide application-specific host facilities; shared Tcl procedures should be
preferred whenever existing commands suffice.

Full Tcl compatibility, untrusted-code sandboxing, shell pipeline syntax,
interactive job control, and competitive Tcl performance are non-goals.
Evaluation nesting is limited to 64 active script evaluations; there is no
general timeout or resource-isolation mechanism.
