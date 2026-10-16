# Run from the repository root. The same file runs on both implementations.
set passed 0
set failed 0
proc test {name body expected {expectedCode 0}} {
    global passed failed
    set code [catch $body actual]
    if [and {== $code $expectedCode} {eq $actual $expected}] {
        incr passed
        puts "ok - $name"
    } else {
        incr failed
        puts "FAIL - ${name}: expected ([list $expectedCode $expected]), got ([list $code $actual])"
    }
}

test empty { eval {} } {}
test last-result { set x one; set x two } two
test separators { eval "set x 1\n;set x 2\r\nset x 3" } 3
test comment { eval "# ignored \[bad\]\nset x yes; # another\nset x" } yes
test comment-inside-word { set x a#b } a#b
test comment-continuation { eval "# comment\\\nerror hidden\nset x yes" } yes
test braces-literal { set x {$missing [error nope] "text"; {nested}} } {$missing [error nope] "text"; {nested}}
test quotes { set x world; set x "hello $x [+ 1 2]" } {hello world 3}
test bare-concatenation { set x mid; set x pre${x}post } premidpost
test no-resplit { set x {a b; error nope}; llength [list $x] } 1
test no-double-substitute { set x {$missing [error nope]}; set y $x } {$missing [error nope]}
test variable-braces { set {odd name} good; set x ${odd name} } good
test literal-dollar { set x {$}; set y $ } {$}
test escapes { set x "a\tb\nc\rd\\e\"f" } "a\tb\nc\rd\\e\"f"
test escaped-space { set x hello\ world } {hello world}
test continuation { eval "set x hello\\\n  world" } {wrong # args: set name ?value?} 1
test quoted-continuation { eval "set x \"hello\\\n  world\"" } {hello world}
test brace-continuation { eval "set x \{hello\\\n  world\}" } {hello world}
test trailing-continuation { eval "set x ok\n\\\n" } ok
test escaped-braces { set x {a\{b\}c} } {a\{b\}c}
test quoted-bracket { set x [list "]"]; lindex $x 0 } {]}
test nested-substitution { + [+ 1 2] [* 3 4] } 15
test substitution-order { set x 0; list [incr x] [incr x] $x } {1 2 2}
test substitution-side-effects { set x 0; set y [incr x]; set x } 1
test dynamic-command { set cmd +; $cmd 3 4 } 7
test malformed-brace { eval "set x \{" } {missing close brace} 1
test malformed-quote { eval "set x \"abc" } {missing close quote} 1
test malformed-bracket { eval "set x \[+ 1 2" } {missing close bracket} 1
test malformed-variable { eval "set x \$\{name" } {missing variable close brace} 1
test malformed-after-brace { eval {set x {a}b} } {extra characters after close quote or brace} 1
test malformed-after-quote { eval {set x "a"b} } {extra characters after close quote or brace} 1
test trailing-backslash { eval "set x abc\\" } {trailing backslash} 1
test missing-variable { set not_defined_here } {no such variable: not_defined_here} 1
test unset-variable { set x yes; unset x; catch {set x} } 1
test empty-variable-name { set {} x } {empty variable name} 1
test case-sensitive-variables { set Case one; set case two; set Case } one
test no-command-fallback { sycol_nonexistent_command } {unknown command: sycol_nonexistent_command} 1
test eval { set x {+ 6 7}; eval $x } 13

test empty-list { llength {} } 0
test list-length { llength {a {b c} "d e" {}} } 4
test list-index { lindex {a {b c} d} 1 } {b c}
test list-outside { list [lindex {a} 9] [lindex {a} -1] } {{} {}}
test list-is-data { lindex {{$missing [error nope]} a;b} 0 } {$missing [error nope]}
test list-semicolon { llength {a;b} } 1
test list-roundtrip {
    set values [list {} {a b} {a{b}c} {a\b} {"quotes"} {$dollar} {[bracket]} "new\nline" {;#}]
    set copy {}
    foreach x $values { lappend copy $x }
    eq $values $copy
} 1
test malformed-list { llength "\{" } {missing close brace} 1
test negative-index-error { lindex {a} nope } {expected integer: nope} 1
test string-length { string length abc } 3
test string-equal { list [eq A a] [ne A a] [eq {} {}] } {0 1 1}
test string-range { string range abcdef 1 3 } bcd
test string-range-clamp { string range abc -2 99 } abc
test string-range-empty { string range abc 9 11 } {}

test arithmetic { list [+ 2 3] [- 2 3] [* 3 4] [/ 7 2] [% 7 2] } {5 -1 12 3 1}
test signed-division { list [/ -7 2] [% -7 2] [/ 7 -2] [% 7 -2] } {-3 -1 -3 1}
test decimal-integers { + 00008 +009 } 17
test comparisons { list [< 1 2] [<= 2 2] [> 2 3] [>= 4 3] [== 2 2] [!= 2 2] [! 0] } {1 1 0 1 1 0 1}
test divide-zero { / 1 0 } {division by zero} 1
test remainder-zero { % 1 0 } {division by zero} 1
test noninteger { + 1.5 2 } {expected integer: 1.5} 1
test infix-rejected { expr {1 + 2} } {unknown command: expr} 1
test integer-overflow { + 2147483647 1 } {integer overflow} 1
test integer-underflow { - -2147483648 1 } {integer overflow} 1
test multiply-overflow { * 2147483647 2147483647 } {integer overflow} 1
test divide-overflow { / -2147483648 -1 } {integer overflow} 1
test parse-overflow { + 99999999999999999999999999 0 } {integer overflow} 1
test zero-normalized { + -0000 0 } 0
test host-injection-integer { + {1; error hacked} 2 } {expected integer: 1; error hacked} 1

test proc-basic { proc add {a b} { + $a $b }; add 4 5 } 9
test proc-defaults { proc greet {{who world}} { return "hi $who" }; greet } {hi world}
test proc-default-override { greet friend } {hi friend}
test proc-varargs { proc gather {first args} { list $first $args }; gather a b c } {a b\ c}
test proc-empty-varargs { proc count {args} { llength $args }; count } 0
test proc-arity-few { add 1 } {wrong # args: procedure arguments} 1
test proc-arity-many { proc zero {} {}; zero extra } {wrong # args: procedure arguments} 1
test proc-bad-formal { proc invalid {{}} {} } {invalid formal parameter} 1
test proc-redefine { proc same {} {return old}; proc same {} {return new}; same } new
test case-sensitive-commands { proc Upper {} { return yes }; catch {upper} } 1
test proc-local { set x outer; proc local {} { set x inner }; local; set x } outer
test no-dynamic-scope { proc invisible {} { set caller_value }; set caller_value x; invisible } {no such variable: caller_value} 1
test explicit-global { set ::shared a; proc modify {} { global shared; append shared b }; modify; set ::shared } ab
test explicit-global-prefix { proc modify2 {} { set ::shared c }; modify2; set ::shared } c
test global-alias-cleanup { proc alias {} { global shared }; alias; proc fresh {} { catch {set shared} }; fresh } 1
test arbitrary-name { set {@x} one; set x two; list ${@x} $x } {one two}
test uplevel { proc change {} { uplevel 1 {set x changed} }; set x before; change; set x } changed
test uplevel-global { uplevel #0 {set from_global yes}; set ::from_global } yes
test bad-level { uplevel 99 {set x a} } {bad level} 1
test recursive {
    proc factorial {n} { if [<= $n 1] {return 1}; * $n [factorial [- $n 1]] }
    factorial 6
} 720
test recursion-limit { proc forever {} {forever}; forever } {evaluation depth exceeded} 1
test early-return { proc early {} { if true { return done }; error nope }; early } done
test catch-ok { catch {set x fine} value options; list $value $options } {fine -code\ 0\ -level\ 0}
test catch-error { catch {error broken} value options; list $value $options } {broken -code\ 1\ -level\ 0}
test catch-return { catch {return value} result options; list $result $options } {value -code\ 0\ -level\ 1}
test catch-break { catch {break} } 3
test catch-continue { catch {continue} } 4
test return-code-error { proc raise {} {return -code 1 broken}; raise } broken 1
test return-level { proc inner {} {return -level 2 done}; proc outer {} {inner; error nope}; outer } done
test return-level-zero { return -level 0 value } value
test invalid-return { return -code 9 value } {invalid return options} 1
test invalid-return-option { return -unknown value } {wrong # args: return ?-code 0..4? ?-level n? ?value?} 1

test if-else { if 0 {error nope} else {set x good} } good
test if-integer { if -2 {set x yes} } yes
test if-false { if false {error nope} } {}
test if-bad-boolean { if abc {} } {expected integer: abc} 1
test if-script-rejected { if {< 1 2} {} } {expected integer: < 1 2} 1
test while-count { set x 0; while {< $x 4} { incr x }; set x } 4
test while-break { set x 0; while {== 1 1} { incr x; if [== $x 3] {break} }; set x } 3
test while-continue { set x 0; set sum 0; while {< $x 4} {incr x; if [== $x 2] {continue}; incr sum $x}; set sum } 8
test while-return { proc wr {} { while {== 1 1} {return done} }; wr } done
test foreach-control { set out {}; foreach x {a b c} {if [eq $x b] {continue}; append out $x; if [eq $x c] {break}}; set out } ac
test foreach-return { proc fr {} {foreach x {a b} {return $x}; error nope}; fr } a
test foreach-error { foreach x {a b} {error broken} } broken 1
test foreach-nested-return { proc fn {} {foreach x {a} {foreach y {b} {return yes}}; error nope}; fn } yes
test foreach-return-code { proc frc {} {foreach x {a} {return -code 1 broken}; error nope}; frc } broken 1
test foreach-empty { foreach x {} {error nope} } {}
test for-count { set total 0; for {set x 0} {< $x 4} {incr x} {incr total $x}; set total } 6
test for-continue-step { set out {}; for {set x 0} {< $x 4} {incr x} {if [== $x 2] {continue}; append out $x}; set out } 013
test for-return { proc frr {} {for {set i 0} {< $i 2} {incr i} {return yes}; error nope}; frr } yes
test for-test-return { proc ftr {} {for {} {return yes} {} {}; error nope}; ftr } yes
test for-step-error { for {set i 0} {< $i 1} {error broken} {} } broken 1
test for-boolean { for {} {set x false} {} {error nope} } {}
test lazy-and { and {set x 0} {error nope} } 0
test lazy-or { or {set x 1} {error nope} } 1
test boolean-words { list [and {set x true} {set x true}] [or {set x false} {set x false}] } {1 0}
test logical-return { proc lr {} {and {return done} {error nope}; error nope}; lr } done

test incr-default { set x 1; incr x; set x } 2
test incr-amount { set x 5; incr x -2 } 3
test append-new { append new_value a b c } abc
test append-existing { set x a; append x b c } abc
test lappend-new { lappend new_list {a b} c; lindex $new_list 0 } {a b}
test concat { concat {a {b c}} {{d e} f} } {a b\ c d\ e f}
test join { join {a b c} , } a,b,c
test join-empty { join {} } {}
test apply-safe { apply list [list {a; error nope} {$missing}]; llength [apply list [list {a; error nope} {$missing}]] } 2
test apply-caller-scope { set x old; apply set {x new}; set x } new
test apply-return { proc ar {} {apply return {done}; error nope}; ar } done

test source-caller-scope { set fixture_value before; source tests/fixtures/scope.tcl; set fixture_value } after
test source-return { source tests/fixtures/return.tcl } sourced
test source-error { source tests/fixtures/error.tcl } {fixture error} 1
test source-missing { source tests/fixtures/not-present.tcl } {cannot read file: tests/fixtures/not-present.tcl} 1
test readfile { readfile tests/fixtures/text.txt } "hello\nworld\n"
test writefile {
    # Test drivers provide an isolated temporary directory via argv.
    set path "[lindex $::argv 0]/round trip.txt"
    writefile $path "space ; \$ \[ ] \\ quote \"\n\n"
    readfile $path
} "space ; \$ \[ ] \\ quote \"\n\n"
test getenv-missing { getenv SYCOL_TEST_VARIABLE_THAT_IS_UNSET } {}
test exec-missing { exec sycol_nonexistent_executable_7654321 } {cannot execute: sycol_nonexistent_executable_7654321} 1
test exec-arity { exec } {wrong # args: exec program ?arg ...?} 1
test argv-count { llength $::argv } 2
test argv-literal { lindex $::argv 1 } {argument with spaces; $literal [brackets]}

test arity-errors {
    set count 0
    foreach script {{set} {set a b c} {unset} {proc a} {eval} {uplevel 1} {catch} {break x} {continue x} {error} {if 1} {while 1} {llength} {lindex {a}} {string} {+ 1} {! 1 2} {puts} {source} {readfile} {writefile a} {pwd a} {cd} {getenv}} {
        if [!= [catch $script] 1] { error "expected arity failure: $script" }
        incr count
    }
    set count
} 24

puts "$passed tests passed; $failed failed"
if [> $failed 0] { error "$failed tests failed" }
