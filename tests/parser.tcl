# Exercise literal runs across the Bash parser's bounded scan windows. These
# assertions also run on PowerShell: the optimization must not change syntax.
set parser_text 0123456789abcdef
while {< [string length $::parser_text] 4096} { set parser_text "$::parser_text$::parser_text" }
set parser_prefix [string range $::parser_text 0 1022]

test parser-long-words {
    list [eq [eval "set value {$::parser_text}"] $::parser_text] \
         [eq [eval "set value \"$::parser_text\""] $::parser_text] \
         [eq [eval "set value $::parser_text"] $::parser_text]
} {1 1 1}
test parser-unicode-boundary {
    set text "${::parser_prefix}éΩ😀$::parser_text"
    list [eq [eval "set value {$text}"] $text] \
         [eq [eval "set value \"$text\""] $text] \
         [eq [eval "set value $text"] $text] \
         [eq [lindex [list $text] 0] $text]
} {1 1 1 1}
test parser-substitution-boundary {
    set value middle
    eq [eval "set result ${::parser_prefix}\${value}\[set value\]$::parser_text"] "${::parser_prefix}middlemiddle$::parser_text"
} 1
test parser-bracket-boundary {
    eq [eval "set result \[set value $::parser_text\]"] $::parser_text
} 1
test parser-nested-braces-boundary {
    eq [eval "set result {$::parser_prefix\{$::parser_text\}}"] "$::parser_prefix\{$::parser_text\}"
} 1
test parser-escaped-braces-boundary {
    eq [eval "set result {$::parser_prefix\\\{$::parser_text\\\}}"] "$::parser_prefix\\\{$::parser_text\\\}"
} 1
test parser-braced-continuation-boundary {
    eq [eval "set result {$::parser_prefix\\\n \t$::parser_text}"] "$::parser_prefix $::parser_text"
} 1
test parser-quoted-continuation-boundary {
    eq [eval "set result \"$::parser_prefix\\\n \t$::parser_text\""] "$::parser_prefix $::parser_text"
} 1
test parser-comment-boundary {
    eval "#$::parser_text\\\nerror hidden\nset result ok"
} ok
test parser-list-literals-boundary {
    eq [lindex "$::parser_prefix\$missing\[error nope\];tail" 0] "$::parser_prefix\$missing\[error"
} 1
test parser-list-quote-boundary {
    eq [lindex "\"$::parser_prefix\$missing\[error nope\];tail\"" 0] "$::parser_prefix\$missing\[error nope\];tail"
} 1
test parser-encoding-specials-boundary {
    set text "$::parser_prefix \t\r\n\\\{\}\[\]\$\";#$::parser_text"
    eq [lindex [list $text] 0] $text
} 1
test parser-long-missing-brace {
    catch "set result \{$::parser_text" value
    set value
} {missing close brace}
test parser-long-close-suffix {
    catch "set result {$::parser_text}suffix" value
    set value
} {extra characters after close quote or brace}
test parser-incremental-error {
    set result before
    catch "set result $::parser_text; set value \{" value
    eq $result $::parser_text
} 1
test parser-long-variable-names {
    set $::parser_text found
    list [eval "set result \$$::parser_text"] [eval "set result \${$::parser_text}"]
} {found found}
test parser-long-whitespace {
    set spaces {                }
    while {< [string length $spaces] 4096} { set spaces "$spaces$spaces" }
    list [eval "${spaces}set${spaces}result${spaces}ok"] \
         [lindex "$spaces\{ok\}$spaces" 0] \
         [eval "set result \"a\\\n${spaces}b\""]
} {ok ok a\ b}
