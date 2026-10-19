# Command reference

[Documentation](README.md) · [Language basics](language.md) · [Tcl compatibility](tcl-compatibility.md)

This reference covers every application command in a normal installation,
including automatic `core.tcl` and optional `files.tcl` and `dict.tcl` modules
(loaded with `source files.tcl` and `source dict.tcl`).
Native commands and shared Tcl procedures have the same calling syntax.
Internal `sy.*` helpers are listed in
the [implementation guide](implementation.md#internal-command-reference).

In signatures, literals are bold and parameter placeholders are italic.
`?argument?` is optional and `...` permits repetition; these markers are not
typed literally. `name`/`varName` means a variable name, not its substituted
value. `script`/`body` means text to evaluate, usually grouped
with braces. An empty result is the empty string. Unsupported options,
subcommands, or argument counts are errors. Errors and other exceptional
completions propagate unless the command explicitly handles them.

- [Variables and procedures](#variables-and-procedures)
- [Evaluation and completions](#evaluation-and-completions)
- [Conditions and loops](#conditions-and-loops)
- [Arithmetic and comparison](#arithmetic-and-comparison)
- [Strings](#strings)
- [Lists](#lists)
- [Dictionaries](#dictionaries)
- [Text I/O and environment](#text-io-and-environment)
- [External processes](#external-processes)
- [Filesystem and paths](#filesystem-and-paths)

## Variables and procedures

### **set** _name_ ?_value_?

- *name*: Variable to read or write.
- *value*: Optional replacement value; omit it to read the variable.

With `value`, create/replace the variable; otherwise read it. Return its value.
Reading a missing variable fails.

### **unset** _name_

- *name*: Existing variable to remove.

Remove one existing variable; return empty. Missing variables fail. No options or
multiple-name form.

### **global** ?_name_ ...?

- *name ...*: Zero or more variable names to alias to the global frame.

Alias each name in the current frame to the corresponding global; return empty. Does
not create a value. A leading `::` is accepted.

### **proc** _name_ _parameters_ _body_

- *name*: Command name to define or replace.
- *parameters*: List of parameter names or `{name default}` pairs; a final `args` collects remaining arguments.
- *body*: Script evaluated when the procedure is called.

Define/replace a globally registered command; return empty. `parameters` is a list of
names or `{name default}` pairs. A final `args` parameter collects remaining
arguments as a list. This replaces other Tcl procedures, but a registered native
handler with the same name always wins; the Tcl definition remains hidden.

### **incr** _name_ ?_amount_?

- *name*: Existing caller variable to update.
- *amount*: Optional integer increment; defaults to `1`.

Add an integer amount (default `1`) to an existing caller variable; return its new
value. Missing variables and invalid/overflowing arithmetic fail.
Operands and the result are validated before writing; failures leave the
existing value unchanged. Signed and leading-zero integers are decimal.

### **append** _name_ ?_value_ ...?

- *name*: Caller variable to update, creating it if absent.
- *value ...*: Zero or more strings to append without separators.

Concatenate values without a separator to a caller variable, creating it if absent;
return the new value. With no values, read/create the variable.

`set`, `unset`, `global`, and `proc` are native; `incr` and `append` have native
implementations with retained SDK fallbacks. Variable names must be nonempty.
Unqualified names refer only to the current frame; leading `::` selects the
global frame. See
[scope and parameters](language.md#variables-and-procedures).

```tcl
set count 2
puts [incr count 3]            ;# 5
append report {count: } $count
puts $report                  ;# count: 5
proc square {n} { * $n $n }
puts [square 4]                ;# 16
```

## Evaluation and completions

### **eval** _script_

- *script*: One script to evaluate in the current frame.

Evaluate exactly one script in the current frame; return its result. Adds no return
boundary.

### **uplevel** _level_ _script_

- *level*: Ancestor frame: `0` for current, `1` for caller, or `#0` for global. Decimal levels must be in `0..128` and identify an existing ancestor.
- *script*: One script to evaluate in the selected frame.

Evaluate in an ancestor frame; return its result. `0` means current, `1` caller;
nonnegative decimal levels up to `128` must identify an existing ancestor. `#0`
selects global. Adds no return boundary.

### **apply** _command_ _arguments_

- *command*: Name of the command to invoke.
- *arguments*: List whose elements become the command's arguments.

Invoke one named command using the decoded elements of list `arguments`, in the
caller frame; return its result. An empty list passes no arguments. This SDK
procedure does not accept Tcl lambdas.

### **catch** _script_ ?_resultVar_? ?_optionsVar_?

- *script*: Script to evaluate in the current frame.
- *resultVar*: Optional variable receiving the script's value or error message.
- *optionsVar*: Optional variable receiving completion metadata; provide `resultVar` first.

Evaluate in the current frame and return the numeric completion code normally.
Optionally assign the script's value and completion metadata to current-frame
variables. Invalid output variable names can make `catch` itself fail.

### **return** ?**-code** _n_? ?**-level** _n_? ?_value_?

- `-code` *n*: Optional numeric target completion code, `0..4`; defaults to `0`.
- `-level` *n*: Optional number of procedure/source boundaries, `0..128`; defaults to `1`.
- *value*: Optional completion value; defaults to empty.

Request a completion through procedure/source boundaries; value defaults to empty,
target code to `0`, level to `1`. Details below.

### **error** _message_

- *message*: Error message to use as the completion value.

Complete with code `1` and value `message`; no normal result.

### **break**

Complete with code `3` and empty value; no normal result. A loop body uses this to
terminate the loop.

### **continue**

Complete with code `4` and empty value; no normal result. A loop body uses this to
skip its remaining commands.

### **exit** ?_status_?

- *status*: Optional decimal process exit status, `0..255`; defaults to `0`.

Terminate the host process immediately; no return value. Status is a decimal integer
`0..255`, default `0`. Invalid arguments are catchable errors; valid exits cannot be
caught.

All except `apply` are native commands. Completion codes are `0` normal, `1`
error, `2` pending return, `3` break, and `4` continue. Nonzero codes stop the
current script, including during substitutions.

`catch` writes options as a four-element list: `-code CODE -level LEVEL`.
For a pending return, these are its target code and remaining level;
otherwise they are the actual completion code and level `0`.

```tcl
set code [catch {error failed} value options]
puts $code                    ;# 1
puts $value                   ;# failed
puts $options                 ;# -code 1 -level 0
```

`return` accepts numeric codes `0..4` and levels `0..128`; symbolic codes and
`-options` are unsupported. Every procedure or `source` boundary consumes one
level. When it reaches zero the requested code becomes effective. Target code
`2` starts a fresh ordinary return at that boundary. Level `0` makes the
requested completion effective immediately. An ordinary `return value` ends
the containing procedure or sourced file normally with `value`.

For a wrapper that catches and rethrows a caller script's completion across
one extra procedure boundary, see [completion propagation](implementation.md#completion-propagation).
Evaluation nesting is limited to `64` simultaneously active script evaluations.

## Conditions and loops

### **if** _boolean_ _body_ ?**else** _body_?

- *boolean*: Already computed boolean value.
- *body*: Script to evaluate when the boolean is true.
- `else` *body*: Optional alternative script to evaluate when false.

Evaluate only the selected body in the current frame; return its result, or empty for
false without `else`. `boolean` is a value already computed by the caller.

### **while** _testScript_ _body_

- *testScript*: Script reevaluated before each iteration to produce a boolean.
- *body*: Script to run while the test is true.

Evaluate the test before each iteration in the current frame. Handle break/continue
from the body; return empty on normal termination. Exceptional completions from the
test propagate.

### **foreach** _name_ _list_ _body_

- *name*: Caller variable receiving each element.
- *list*: List of values to iterate over.
- *body*: Script evaluated in the caller frame for each element.

Assign each decoded list element to one caller variable, evaluating the body there.
Handle body break/continue; return empty. Variable retains its last assignment; an
empty list makes no assignment.

### **for** _initial_ _test_ _step_ _body_

- *initial*: Initialization script, evaluated once.
- *test*: Script evaluated before each iteration to produce a boolean.
- *step*: Script evaluated after the body, including after a body `continue`.
- *body*: Loop body evaluated in the caller frame.

In caller frame, run `initial` once, test before each iteration, body, then step.
Return empty on normal termination. Body continue runs step; break in body or step
terminates the loop. Other exceptional completions propagate.

### **and** _leftScript_ _rightScript_

- *leftScript*: First script to evaluate for a boolean result.
- *rightScript*: Second script, evaluated only if the first result is true.

Evaluate left in caller frame; if true, evaluate right. Return `1` if both results
are true, otherwise `0`. Skip right when left is false.

### **or** _leftScript_ _rightScript_

- *leftScript*: First script to evaluate for a boolean result.
- *rightScript*: Second script, evaluated only if the first result is false.

Evaluate left in caller frame; if false, evaluate right. Return `1` if either result
is true, otherwise `0`. Skip right when left is true.

`if` and `while` are native; the others are SDK procedures. Accepted booleans
are case-sensitive `true`, `false`, or signed decimal 32-bit integers: zero
is false, otherwise true. Neither `if` nor any loop parses infix expressions.
`if` has no `elseif`/`then`, and `foreach` supports exactly one variable and
one list. Loop variables persist after the loop.

```tcl
set total 0
for {set i 0} {< $i 5} {incr i} { incr total $i }
if [and {> $total 0} {< $total 20}] { puts $total }  ;# 10
```

## Arithmetic and comparison

All operators in this section are native commands. Operands are signed decimal
32-bit integers (`-2147483648..2147483647`), with an optional leading sign.
Leading zeros are decimal. Whitespace, hexadecimal, exponent notation, floats,
and out-of-range operands/results fail. Operators are binary except `!`.

### **+** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

Sum

### **-** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

Difference; negate with `- 0 value`

### **\*** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

Product

### **/** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

Quotient, truncated toward zero; zero divisor fails

### **%** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

Remainder with the dividend's sign; zero divisor fails

### **<** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

`1` if a is less than b, else `0`

### **<=** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

`1` if a is less than or equal to b, else `0`

### **>** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

`1` if a is greater than b, else `0`

### **>=** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

`1` if a is greater than or equal to b, else `0`

### **==** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

`1` if integers are equal, else `0`

### **!=** _a_ _b_

- *a, b*: Signed decimal 32-bit integer operands.

`1` if integers differ, else `0`

### **!** _integer_

- *integer*: Signed decimal 32-bit integer to negate logically.

`1` if zero, else `0`; does not accept `true`/`false`

Use command substitution to consume a result: `puts [* 6 7]`. For strings,
use the following commands rather than numeric `==`/`!=`.

## Strings

### **string** **length** _value_

- *value*: String whose length is measured.

Return length in host character units.

### **string** **equal** _a_ _b_

- *a, b*: Strings to compare exactly and case-sensitively.

Return `1` for exact, case-sensitive equality, otherwise `0`.

### **string** **range** _value_ _first_ _last_

- *value*: String to slice.
- *first, last*: Inclusive decimal integer bounds; `end` notation is unsupported.

Return an inclusive substring. Bounds are decimal integers; clamp first to zero and
last to the final unit. Disjoint/reversed ranges return empty. No `end` notation.

### **eq** _a_ _b_

- *a, b*: Strings to compare exactly and case-sensitively.

SDK shorthand for `string equal a b`; return `0` or `1`.

### **ne** _a_ _b_

- *a, b*: Strings to compare exactly and case-sensitively.

SDK string inequality; return `0` or `1`.

`string` is native and supports only these three subcommands, spelled in full,
without options. ASCII length/range agree across backends. Non-ASCII indexing
uses Bash locale characters/bytes or PowerShell UTF-16 code units; see
[text portability](tcl-compatibility.md#text-and-host-portability).

```tcl
puts [string range abcdef 1 3]   ;# bcd
puts [eq 01 1]                  ;# 0: different strings
puts [== 01 1]                  ;# 1: equal decimal integers
```

## Lists

`list`, `llength`, and `lindex` are native; `concat` and `lappend` have native
implementations with retained SDK fallbacks. The other commands are SDK
procedures. All list inputs must be valid encoded lists. Returned lists use
canonical encoding; elements retain their decoded values.

### **list** ?_value_ ...?

- *value ...*: Zero or more values, each encoded as one list element.

Encode each argument as one element; return a list. No arguments returns empty.

### **llength** _list_

- *list*: Encoded list to count.

Return decimal element count.

### **lindex** _list_ _index_

- *list*: Encoded list to read.
- *index*: One element index, using the index notation described below.

Return one decoded element; negative/out-of-range index returns empty. Exactly one
index is required; no nested-index-list form.

### **lassign** _list_ ?_varName_ ...?

- *list*: Encoded list supplying the values.
- *varName ...*: Zero or more caller variables to assign in order.

Assign elements to caller variables in order; missing values become empty. Return
unassigned elements as a list. Validate input first; invalid variable names can leave
earlier assignments in place.

### **lrange** _list_ _first_ _last_

- *list*: Encoded list to slice.
- *first, last*: Inclusive element indices, using the index notation described below.

Return an inclusive element range. Clamp bounds to the list; disjoint/reversed ranges
return empty.

### **linsert** _list_ _index_ ?_element_ ...?

- *list*: Encoded list to extend.
- *index*: Insertion position; `end` appends.
- *element ...*: Zero or more elements to insert.

Return a new list with elements inserted before index; clamp index to beginning/end.
Here `end` means append.

### **lreplace** _list_ _first_ _last_ ?_element_ ...?

- *list*: Encoded list to edit.
- *first, last*: Inclusive indices of the range to replace.
- *element ...*: Zero or more replacement elements; omit them to delete the range.

Return a new list replacing the inclusive range. Omitted elements delete. Clamp first
to `0..length`, last to the final element. Last before first deletes nothing and
inserts before first.

### **lreverse** _list_

- *list*: Encoded list whose element order is reversed.

Return a new list with elements reversed.

### **lappend** _name_ ?_value_ ...?

- *name*: Caller variable containing a list; created if absent.
- *value ...*: Zero or more values to append as individual elements.

Append each value as one element to a caller variable, creating an empty list if
absent; return the new list. Validate and re-encode its existing value, even with no
new elements.
Malformed existing lists fail without changing the variable. Repeated appends
still validate and reconstruct the growing list string.

### **concat** ?_list_ ...?

- *list ...*: Zero or more encoded lists to combine by flattening one level.

Flatten one list level and return a canonical list. No arguments returns empty.
Every input must be a complete valid list; fragments cannot complete each other.

### **join** _list_ ?_separator_?

- *list*: Encoded list whose decoded elements are joined.
- *separator*: Optional string placed between elements; defaults to one space.

Join decoded elements into a string; separator defaults to one space. Empty list
returns empty.

Editing commands validate lists even for empty ranges or no inserted elements.
They do not change the input variable unless explicitly documented (`lappend`
and assignments by `lassign`).

Indices accept signed decimal integers, `end`, `end-N`, `end+N`, and one
decimal addition/subtraction such as `1+2` or `3-1`. Operands and results obey
the signed 32-bit limits. No whitespace or chained arithmetic is allowed.
The current resolver also accepts bare `e` and `en` as abbreviations of `end`;
prefer spelling `end` in application code.

For `lindex`, `lrange`, and `lreplace`, `end` is length minus one. For
`linsert`, `end` is length, so `end-1` inserts before the final element.

```tcl
set items {a b c d}
puts [lindex $items end]          ;# d
puts [lrange $items 1 end-1]      ;# b c
set items [linsert $items end e]  ;# a b c d e
set items [lreplace $items 1 2 x] ;# a x d e
puts [lreverse $items]           ;# e d x a
lassign $items first second
puts [join [list $first $second] ,] ;# a,x
```

## Dictionaries

Load `source dict.tcl`. All operations are shared SDK procedures, with no
native dictionary backend. Dictionaries are string values containing an
even-length list of alternating keys and values. Empty keys/values are valid;
keys are case-sensitive. Duplicate keys use their last value and retain their
first position. Updating a key keeps its position; adding a key appends it.
Removing and reinserting a key moves it to the end.

### **dict create** ?_key value ..._?

Return a dictionary from the supplied pairs, or empty with no arguments.
An unpaired key is an error.

### **dict get** _dictionaryValue_ ?_key ..._?

Return the value at the given key path. Pass each key as a separate argument;
`{a b}` denotes one key containing a space, not two nested keys. With no keys,
return all distinct key/value pairs. Missing keys, malformed lists, and
odd-length dictionaries along the path are errors. Leaf values are opaque
strings and need not themselves be dictionaries.

### **dict exists** _dictionaryValue key_ ?_key ..._?

Return `1` when retrieving that path would succeed, otherwise `0`. Missing keys
and malformed dictionaries along the path return `0`, following Tcl 8.6.
At least one key is required.

### **dict set** _dictionaryVariable key_ ?_key ..._? _value_

Update the dictionary in the named caller variable, creating the variable and
missing intermediate dictionaries as needed. Return the entire updated
dictionary. An existing malformed dictionary on the path is an error.

### **dict unset** _dictionaryVariable key_ ?_key ..._?

Remove the final key, store the result in the named caller variable, and
return the entire updated dictionary. An absent final key is allowed;
missing intermediate keys and malformed dictionaries are errors. Empty parent
dictionaries remain present. A missing variable is treated as empty, so
single-key `unset` creates an empty variable; a missing intermediate key fails
without creating the variable.

Both mutations accept ordinary variable names, `::` globals, and global
aliases; empty variable names fail. Validation errors leave the variable
unchanged. Variable names are passed literally, without `$`; read operations
take dictionary values. Copies remain independent after mutation.

### **dict keys** _dictionaryValue_

Return a list of distinct keys in insertion order. Tcl's optional glob pattern
is unsupported: Sycol has no glob API, and pattern matching is deferred to keep
this initial subset small.

### **dict size** _dictionaryValue_

Return the number of distinct keys. Both `keys` and `size` reject malformed
lists and odd-length dictionaries.

Only these seven subcommands are supported. Unambiguous Tcl 8.6 abbreviations
work (`c`, `g`, `e`, `k`, `se`, `si`, `un`); ambiguous prefixes such as `s` and
`u` are errors, including ambiguity with unsupported Tcl operations. Other
Tcl `dict` operations are errors. Argument-count errors are catchable. Returned
dictionaries use Sycol's canonical list encoding; compare decoded entries when
input spelling is irrelevant. Scans can repeatedly parse lists, and mutations
rebuild strings; lookup and update are not guaranteed constant time.

```tcl
source dict.tcl
set config [dict create host localhost port 8080]
puts [dict get $config host]       ;# localhost
puts [dict exists $config tls]     ;# 0
dict set config port 9000
dict set config tls enabled 1
puts [dict get $config tls enabled] ;# 1
set copy $config
dict unset copy port
puts [dict exists $config port]    ;# 1
puts [dict keys $copy]             ;# host tls
puts [dict size $copy]             ;# 2
```

## Text I/O and environment

All commands in this section are native.

### **puts** ?**-nonewline**? _value_

- `-nonewline`: Optional flag suppressing the final newline.
- *value*: Literal text to write to stdout.

Write literal text to stdout, with a newline unless `-nonewline` is given; return
empty. No channel argument.

### **source** _path_

- *path*: UTF-8 script file to read and evaluate.

Read and evaluate a UTF-8 file in the current frame; return its script result after
handling one return boundary. Normalize CRLF to LF. Absolute paths select files
directly; `./` and `../` paths use cwd. Other relative paths search
`::sycol_sdk_path`, then `::sycol_source_path`, each a list of directories.
No implicit cwd fallback occurs. The first existing candidate wins; missing,
unreadable, invalid, or malformed-list paths and evaluation failures are errors.

Files inside SDK roots activate matching native backends before Tcl evaluation.
Missing backends are allowed; failed backends stop loading. Backends load once,
while Tcl evaluates on every source. Native handlers always win over same-name
Tcl definitions. See [module loading](implementation.md#library-discovery) for
environment settings, defaults, subdirectory matching, and bootstrap behavior.

```tcl
source files.tcl
lappend ::sycol_source_path /opt/my-library
source utility.tcl
source ./local.tcl
```

### **readfile** _path_

- *path*: UTF-8 text file to read.

Return the entire UTF-8 file as text, preserving line endings and trailing newlines.
Do not evaluate its contents.

### **writefile** _path_ _text_

- *path*: File to create or overwrite; its parent directory must exist.
- *text*: UTF-8 text to write, without an added newline or BOM.

Create/overwrite a UTF-8 file, without adding a newline or BOM; return empty. Parent
directory must exist.

### **pwd**

Return the current working directory in host path format.

### **cd** _path_

- *path*: Directory to make the host's working directory.

Change the host's working directory; return empty. Exactly one path is required.

### **getenv** _name_

- *name*: Process environment variable name, matching `[A-Za-z_][A-Za-z0-9_]*`.

Return a process environment variable, or empty if absent. Name must match
`[A-Za-z_][A-Za-z0-9_]*`; lookup uses host case sensitivity.

Paths are literal. Except for `source` search rules above, relative paths use cwd.
Text files must be valid UTF-8 without NUL. A leading UTF-8 BOM is stripped by `source`
and `readfile`; encoding itself is not validated. Handles are closed before
returning. I/O failures are catchable errors. There are no channel or binary
I/O commands. Setting a Sycol variable does not export an environment variable.

```tcl
source files.tcl
file mkdir build
writefile [file join build message.txt] "hello\n"
puts -nonewline [readfile [file join build message.txt]]
```

## External processes

### **exec** ?**-capture**? ?**--**? _program_ ?_arg_ ...?

- `-capture`: Optional flag selecting a three-element capture result instead of stdout alone.
- `--`: Optional end-of-options marker, allowing a program named `-capture` or `--`.
- *program*: External executable name or explicit path.
- *arg ...*: Zero or more literal arguments, each passed as one OS argument.

Run one external executable resolved by explicit path or host `PATH`. Each
Sycol argument becomes one OS argument, including empty strings. Aliases,
shell functions, and built-ins are not executable lookup targets. `exec` is native.

Only an initial `-capture` enables capture mode. An optional `--` before the
program ends option recognition, allowing a program named `-capture` or `--`.
All words after the program are literal arguments, including `-capture`, `--`,
`|`, and `>`. There is no implicit shell, interpolation, globbing, pipeline,
redirection, background job, or `$HOME` expansion. The child inherits the
environment, stdin, and working directory.

**Plain execution.** Capture stdout, inherit stderr. On exit `0`, return stdout
with exactly one final LF removed, also removing its immediately preceding CR
if present. Other trailing newlines and a lone CR remain.

**Capture mode.** Return a proper three-element list `status stdout stderr`,
normally even for a nonzero child exit. Capture both streams and preserve every
trailing LF/CR. No ordering between streams is exposed.

Plain `exec` on nonzero exit raises `process exited with status N`, discarding
stdout after stderr has streamed. Lookup/start failures raise `cannot execute:
PROGRAM`. Capture I/O failures raise `cannot capture process output`.
After successful lookup, some Bash loader failures appear as child status
`126`/`127`, possibly with host diagnostics.

The status is the host-reported decimal exit status. Signal termination has
no portable metadata: Bash normally reports `128 + signal`; PowerShell reports
the platform exit code. Both streams must meet the UTF-8-without-NUL text
contract. Neither mode provides a timeout or process handle. Use a native
extension for programs requiring a terminal.

```tcl
puts [exec git --version]
lassign [exec -capture -- git status --short] status stdout stderr
puts "status: $status"
puts -nonewline $stdout
puts -nonewline $stderr
```

Use `apply exec [list git log -1 -- $filename]` to pass a dynamically built
argument list. An OS shell runs only if explicitly requested, for example
`exec bash -c {printf '%s\n' "$HOME"}`. See
[backend process handling](implementation.md#backend-differences) for capture
utilities and Windows command-line conventions.

## Filesystem and paths

Load this optional module with `source files.tcl` before using any `file` command.

`file operation arguments...` is a shared SDK procedure using native filesystem
primitives and shared path helpers. The following entries cover every supported
subcommand. Mutating operations return empty; inspection/path operations return
the described value. Unknown operations and options fail.

### Inspection and directories

#### **file** **list** ?_path_?

- *path*: Optional literal directory path; defaults to `.`.

Return a proper list of immediate entry names, including hidden entries, excluding
`.`/`..`. Default path is `.`; order is unspecified. Empty directories return empty.
Follows a link to the directory.

#### **file** **type** _path_

- *path*: Entry to inspect, without following its final symbolic link.

Return `file`, `directory`, `link`, `characterSpecial`, `blockSpecial`, `fifo`, or
`socket`. Inspect the final entry itself, including dangling links; ignore trailing
directory separators for identification. Missing paths fail.

#### **file** **exists** _path_

- *path*: Path to test, following links.

Return `1` if the entry exists, following links, otherwise `0`; missing/inaccessible
paths return `0`.

#### **file** **isfile** _path_

- *path*: Path to test for a regular file, following links.

Return `1` for a regular file, following links, otherwise `0`; missing/inaccessible
paths return `0`.

#### **file** **isdirectory** _path_

- *path*: Path to test for a directory, following links.

Return `1` for a directory, following links, otherwise `0`; missing/inaccessible
paths return `0`.

#### **file** **size** _path_

- *path*: Entry whose byte length is measured, following links.

Return byte length as a decimal string, following links; missing paths fail.
Directory sizes are host-dependent (`0` on Windows PowerShell).

#### **file** **mkdir** ?_path_ ...?

- *path ...*: Zero or more literal directory paths to create, including missing parents.

Create directories and missing parents, in order; existing directories succeed. No
arguments succeeds, an empty path fails. Return empty. Arguments are literal paths,
not options.

Size can exceed the arithmetic core's 32-bit range and remains a valid string.
A dangling link has type `link` but all three predicates return `0`.

### Copy, rename, and delete

#### **file** **copy** ?**-force**? ?**--**? _source_ ?_source_ ...? _target_

- `-force`: Optional flag permitting replacement of supported existing destinations.
- `--`: Optional end-of-options marker before paths.
- *source ...*: One or more entries to copy.
- *target*: Destination path or existing directory receiving the sources.

Recursively copy sources, preserving supported metadata. Return empty. Existing
destination entries require `-force`.

#### **file** **rename** ?**-force**? ?**--**? _source_ ?_source_ ...? _target_

- `-force`: Optional flag permitting replacement of supported existing destinations.
- `--`: Optional end-of-options marker before paths.
- *source ...*: One or more entries to move.
- *target*: Destination path or existing directory receiving the sources.

Move sources, using copy/delete across filesystems when needed. Return empty.
Existing destination entries require `-force`.

#### **file** **delete** ?**-force**? ?**--**? ?_path_ ...?

- `-force`: Optional flag allowing recursive deletion of nonempty directories and permission adjustments.
- `--`: Optional end-of-options marker before paths.
- *path ...*: Zero or more entries to delete in order.

Delete entries in order. Missing paths, an empty path, and zero paths succeed.
Nonempty directories require `-force`; read-only files can be removed without it.
Return empty.

Options precede paths; repeated `-force` is accepted. Use `--` for a first path
beginning with `-`. No `-recursive` or `-attributes` option exists: recursive
copy and supported metadata preservation are the defaults.

If target is an existing directory, including a link to a directory, sources
are placed inside it under their basenames. Otherwise exactly one source is
required and target is its new path. Target parents must already exist. Copy
and rename reject empty source/target paths.

Copy does not merge or replace destination directory trees, even empty ones.
Neither operation permits replacing a directory with a file/link or the reverse.
Forced rename can replace an empty destination directory with a directory;
nonempty destination trees are never merged. Copying onto the same file or a
directory into its descendant fails. Forced rename onto the same entry succeeds
without changing it.

Copy/delete act on the final symbolic link rather than traversing its referent,
including links inside recursive trees. Copying links requires host support
and permission; unsupported links fail. A force replacement of a final link
does not change its referent. Force deletion attempts to adjust permissions
and move cwd outside the removed tree when necessary.

Copy preserves modification/access timestamps and supported native attributes.
ACLs, ownership, metadata beyond host support, cross-platform permissions, and
portable copying of special objects are not guaranteed. These commands use
native filesystems; Tcl virtual filesystems are unsupported.

Operations process paths in order, stop on the first error, and do not roll
back earlier changes. Failed copies/deletions can leave partial trees. A
cross-filesystem rename deletes the source only after a successful copy; it
is not atomic. Source-deletion failure leaves both copies and reports an error.

```tcl
foreach name [file list .] { puts "$name: [file type $name]" }
set output [file join build backup]
file mkdir [file dirname $output]
file copy source-dir backup-dir
file rename backup-dir $output
if [file isfile [file join $output notes.txt]] {
    puts "notes: [file size [file join $output notes.txt]] bytes"
}
file delete -force $output
```

### Path operations

#### **file** **join** _name_ ?_name_ ...?

- *name ...*: One or more path components to join using host rules.

Join one or more components using host rules and `/` separators. A rooted or
leading-home component resets preceding components. Return the joined path.

#### **file** **pathtype** _path_

- *path*: Path to classify lexically; it need not exist.

Return `absolute`, `relative`, or `volumerelative` using host path rules, without
accessing the filesystem. Empty is `relative`; leading `~`, even `~user`, is
lexically `absolute`.

#### **file** **dirname** _path_

- *path*: Path whose parent component is returned.

Return parent component, ignoring trailing separators; a plain filename or empty path
has dirname `.`. Roots retain their root.

#### **file** **tail** _path_

- *path*: Path whose final component is returned.

Return final component, ignoring trailing separators; a root or empty path returns
empty. A literal leading tilde in the returned component is prefixed with `./`.

#### **file** **extension** _path_

- *path*: Path whose final extension is returned.

Return the final component's last dot and following text, or empty if absent.
Dotfiles have extensions; a trailing separator means no extension.

#### **file** **rootname** _path_

- *path*: Path whose final extension is removed.

Return the original path with that extension removed, preserving original separators.
No extension leaves it unchanged.

Unix recognizes `/`; Windows also recognizes backslashes, drive-relative
paths, drive roots, and UNC share roots. On Windows `C:/data` and `//server/share`
are absolute; `C:data`, `C:`, `/data`, and `\data` are volume-relative. On Unix
`/data` is absolute and `C:data` is relative.

Joins collapse repeated separators and remove trailing separators except
roots and bare home prefixes. They do not resolve `.`/`..` or symbolic links.
Path helpers do not require existing files, except that dirname/tail expand
a bare home name such as `~` before selecting its components.

Filesystem operations expand `~` and `~/...` to the current user's home using
HOME, then USERPROFILE where applicable, or host APIs. Named-user `~user`
lookup is unsupported; use an explicit path. Lexical classification of `~user`
as absolute does not perform that lookup. Paths do not expand wildcards,
environment variables, or shell syntax.

### Subcommand abbreviations

Tcl-compatible minimum prefixes are supported for the standard operations:

| Operation | Minimum prefix | Operation | Minimum prefix |
| --- | --- | --- | --- |
| **`copy`** | **`co`** | **`delete`** | **`de`** |
| **`type`** | **`ty`** | **`mkdir`** | **`mk`** |
| **`exists`** | **`exi`** | **`isfile`** | **`isf`** |
| **`isdirectory`** | **`isd`** | **`join`** | **`j`** |
| **`dirname`** | **`di`** | **`tail`** | **`ta`** |
| **`extension`** | **`ext`** | **`rootname`** | **`ro`** |
| **`size`** | **`si`** | **`rename`** | **`ren`** |
| **`pathtype`** | **`p`** | **`list`** (Sycol extension) | **`list`** in full |

Longer prefixes through the full spelling work. Ambiguous `c`, `d`, and `t`
fail. Prefer full names in documentation and reusable scripts.
