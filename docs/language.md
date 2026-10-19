# Language basics

[Documentation](README.md) · [Command reference](commands.md) · [Running scripts](running.md)

Sycol uses Tcl's command-and-word syntax with a deliberately smaller command
set. The syntax below describes Sycol; the [compatibility guide](tcl-compatibility.md)
identifies differences from full Tcl.

## Commands and values

A command is a name followed by arguments. Spaces and tabs separate words;
newlines and semicolons separate commands. CR also separates words. Names and
string comparisons are case-sensitive. Every value, including a number or
list, is a string.

```tcl
set name Alice
puts $name
set count 3; incr count
```

Each command returns a value. A script returns the last command's value; an
empty script returns an empty string. Results are not printed automatically:
use `puts` to write to stdout. `set count 3` returns `3`; `puts $count` prints
`3` and returns an empty string.

Commands are looked up by name. The first word can itself be substituted:

```tcl
set operation +
puts [$operation 2 3]       ;# 5
```

Unknown names are errors. Writing `git status` does not run Git; use
`exec git status`.

## Quoting and substitution

| Form | Meaning |
| --- | --- |
| `word` | One word ending at a separator; substitutions apply |
| `"two words: $name"` | One word retaining whitespace; substitutions apply |
| `{two words: $name}` | One literal word; nested braces are allowed |
| `$name` | Insert a variable's value |
| `${odd name}` | Insert a variable with a name delimited by braces |
| `[command args]` | Evaluate a script in the current variable frame and insert its result |
| `{}` or `""` | An empty string argument |

Braces and quotes group a word only when they begin it. After their closing
delimiter, only a separator, the enclosing substitution's `]`, or end of input
is allowed. `{a}b` and `"a"b` are errors. In a bare word, literal text can be
combined with substitutions:

```tcl
set name Alice
puts "Hello, $name"          ;# Hello, Alice
puts {Hello, $name}          ;# Hello, $name
puts pre${name}[+ 1 2]post   ;# preAlice3post
```

`$name` consumes ASCII letters, digits, underscores, and colons. `${name}`
accepts any nonempty name through the next `}`. A `$` without a following
name is literal. Missing variables are errors.

Substitutions run left to right, once. Substituted text stays within its
original word: spaces do not split it, wildcards do not expand, and `$`, `;`,
or brackets inside the value do not trigger another evaluation.

```tcl
set text {two words; error nope}
set copy $text                ;# One value; error is not executed.
puts [llength [list $copy]]    ;# 1
```

Braces suppress variable and command substitution. Commands such as `proc`,
`while`, and `foreach` later evaluate their braced body arguments as scripts.
Grouping and evaluating are separate operations.

## Escapes, continuation, and comments

Outside braces, `\n`, `\r`, and `\t` produce a newline, carriage return, and
tab. A backslash before any other character removes the backslash and quotes
that character: `\ ` includes a space, `\$` includes a literal dollar sign,
and `\\` includes a backslash. There are no numeric or Unicode escape forms.

Inside a braced word, unescaped inner braces must balance, but do not need
escaping. These inner pairs remain in the value; only the outermost pair is
removed. Backslashes remain literal. A backslash before `{` or `}` prevents
that brace from opening or closing a group; both the backslash and brace
remain in the resulting value:

```tcl
puts {a {b} c}                  ;# Prints: a {b} c
puts {a {b} \{ c}               ;# Prints: a {b} \{ c
puts {a \} b}                   ;# Prints: a \} b
```

In the second line, `{b}` is a balanced inner pair. The escaped `\{` does not
open another pair, so the final `}` closes the word. Its backslash remains
visible in the output; escaping here changes brace matching, not the value.

To include an unmatched brace without a backslash in the value, use a quoted
word. Braces inside quotes are ordinary characters, though variable, command,
and backslash substitutions still apply:

```tcl
puts "a {b} { c"                ;# Prints: a {b} { c
```

The exception to literal backslashes inside braces is backslash immediately
followed by LF: it and any following spaces/tabs fold to one space, in every
quoting form. Between bare words this separates words; inside quotes or braces
it remains within the word.

```tcl
puts "first line\nsecond line"
set message {a long\
    message}                    ;# a long message
```

`#` starts a comment only where a command's first word could start. For an
inline comment, finish the preceding command with `;`. A backslash-newline
continues a comment onto the next physical line.

```tcl
# A whole-line comment.
set tag a#b                     ;# The value is a#b.
```

Unclosed braces, quotes, brackets, variable braces, and a final unpaired
backslash are errors. Parsing is incremental: commands before a later syntax
error may already have changed variables or files.

## Variables and procedures

`set name value` creates or replaces a variable; `set name` reads it.
`unset name` removes it. Names must be nonempty. Use `${...}` to substitute
names containing spaces. Sycol has no arrays or dictionaries.

`proc name parameters body` defines a globally available command. Each call
has local variables. A parameter is a name or a `{name default}` pair; defaults
are literal strings. A final parameter named `args` collects remaining
arguments into a list.

```tcl
proc greet {name {prefix Hello}} {
    return "$prefix, $name"
}
proc show {heading args} {
    puts $heading
    foreach item $args { puts $item }
}
puts [greet Alice]              ;# Hello, Alice
show Guests Alice {Bob Smith}
```

Without `return`, a procedure returns its last command's result. Parameters
cannot be empty or start with `::`. Missing required or excess arguments are
errors. Procedure definitions replace earlier definitions, including built-ins.
There are no closures; defining a procedure inside another does not capture
its variables.

An unqualified variable refers only to the current frame. It does not search
the caller or global frame. Use `::name` for a global, or `global name` to make
the local name refer to it. Only a leading `::` is special; other colons do
not create namespaces.

```tcl
set total 0
proc add-total {n} {
    global total
    incr total $n
}
add-total 4
puts $total                    ;# 4
```

Startup provides `argv0`, `argc`, `argv`, `sycol_host`, and `sycol_version` in
the global frame. Access them inside procedures through `global` or `::`;
see [script arguments](running.md#script-arguments-and-results).

## Lists and argument boundaries

A list is a string containing encoded elements. `list` constructs it safely;
`lindex` decodes one element. Lists can contain spaces, empty strings, and
nested lists without losing boundaries.

```tcl
set guests [list Alice {Bob Smith} {}]
puts [llength $guests]          ;# 3
puts [lindex $guests 1]         ;# Bob Smith
set guests [linsert $guests end Carol]
```

In list parsing, variables and command substitutions are disabled. Semicolons
and brackets are literal characters; braces, quotes, escapes, and whitespace
still control element boundaries. Malformed lists are errors. Equivalent list
strings can have different spellings; commands constructing lists use a
canonical encoding. Compare decoded elements when spelling does not matter.

Most list operations return a new list; `lappend` changes a variable and
`lassign` assigns variables. List indices support `end` and limited index
arithmetic, described in the [list reference](commands.md#lists).

There is no `{*}` argument expansion. Use `apply command argumentList`:

```tcl
set arguments [list {one two} three]
puts [apply list $arguments]    ;# A two-element list.
```

Use `list` to build a command when passing values to `eval` or `uplevel`.
Concatenating raw values into script text lets their punctuation become code.
Sycol's `apply` invokes a named command; it does not accept Tcl lambdas.

## Arithmetic, conditions, and loops

Arithmetic operators are commands: `[+ 2 3]`, `[* $n $n]`, `[< $n 10]`.
There is no `expr` or infix expression parser. Arithmetic accepts signed
decimal 32-bit integers; leading zeros are decimal. Overflow and division
by zero are errors.

Use `==` for numeric equality and `!=` for numeric inequality. They compare
integer values, so `01` and `1` are equal. Use `eq`, `ne`, or `string equal`
to compare exact text, even when it contains digits. These comparisons return
`1` for true and `0` for false:

```tcl
puts [== 01 1]                 ;# 1: equal integer values
puts [!= 01 1]                 ;# 0: the integers do not differ
puts [eq 01 1]                 ;# 0: different strings
puts [ne 01 1]                 ;# 1: the strings differ
```

`if` takes a computed boolean. `while` and `for` take a script that computes
the condition again on each iteration. Boolean values are lowercase `true`,
`false`, or signed decimal integers: zero is false, other valid integers true.

```tcl
set n 0
if [< $n 3] { puts small } else { puts large }
while {< $n 3} { incr n }
for {set i 0} {< $i 3} {incr i} { puts $i }
foreach name {Alice {Bob Smith}} { puts $name }
```

`if {< $n 3} ...` fails because the braced argument is script text rather than
a boolean. There is no `elseif`; put another `if` inside the `else` body.
Use `and {leftScript} {rightScript}` or `or` for lazy conditions. The unused
right script is skipped. Use `break` to leave a loop and `continue` to skip
the remaining body; in `for`, continuing the body still runs the step.

## Errors, returns, and file loading

An error stops the current script unless caught. `catch script ?resultVar? ?optionsVar?`
evaluates in the current frame and returns a completion code:

| Code | Meaning |
| --- | --- |
| `0` | Normal completion |
| `1` | Error |
| `2` | Return in progress |
| `3` | Break |
| `4` | Continue |

```tcl
if [catch {readfile missing.txt} message] {
    puts "Could not read: $message"
}
```

The result variable receives the value, or the error message on code `1`.
The options variable receives `-code CODE -level LEVEL` as a list. Advanced
`return -code` and `-level` behavior is covered in the
[command reference](commands.md#evaluation-and-completions).

`source path` evaluates another UTF-8 file in the current variable frame.
Its path resolves from the current working directory, as do nested sources;
it does not resolve relative to the containing file. A procedure or `source`
boundary consumes one ordinary `return` level. A top-level `return` therefore
ends the entry script successfully.

An uncaught error or unresolved exceptional completion produces a failing
process status. `exit ?status?` terminates immediately and cannot be caught.
Scripts have their host shell's filesystem and process access; run trusted
scripts. Text must be valid UTF-8 without NUL; binary I/O is unsupported.
