# These contracts run unchanged against native, fallback, and partial backends.
proc promoted-identity {args} { lindex $args 0 }
test promoted-procedure-crlf {
    set text " \t\r\n"
    eq [promoted-identity $text] $text
} 1
test promoted-arity {
    set result {}
    foreach script {{incr} {incr x 1 2} {append} {lappend}} {
        catch $script message
        lappend result [eq $message {wrong # args: procedure arguments}]
    }
    set result
} {1 1 1 1}
test promoted-empty-names {
    set result {}
    foreach script {{incr {}} {incr ::} {append {}} {append :: x} {lappend {}} {lappend :: x}} {
        catch $script message
        lappend result [eq $message {empty variable name}]
    }
    set result
} {1 1 1 1 1 1}
test promoted-missing-incr {
    catch {unset promoted_missing}
    catch {incr promoted_missing invalid} message options
    list $message $options [catch {set promoted_missing}]
} {no\ such\ variable:\ promoted_missing -code\ 1\ -level\ 0 1}
test promoted-decimal { set x +0009; list [incr x] [incr x -0002] [incr x +0] } {10 8 8}
test promoted-integer-errors {
    set result {}
    foreach operands {{bad invalid} {1 bad} {2147483647 1} {-2147483648 -1} {2147483648 0} {1 2147483648}} {
        set x [lindex $operands 0]
        catch [list incr x [lindex $operands 1]] message options
        lappend result $message [eq $x [lindex $operands 0]] $options
    }
    eq $result [list {expected integer: bad} 1 {-code 1 -level 0} {expected integer: bad} 1 {-code 1 -level 0} {integer overflow} 1 {-code 1 -level 0} {integer overflow} 1 {-code 1 -level 0} {integer overflow} 1 {-code 1 -level 0} {integer overflow} 1 {-code 1 -level 0}]
} 1
proc promoted-inner {} {
    set {odd name;[$]} +01
    incr {odd name;[$]} 2
    append {odd name;[$]} {} {;[$]}
    lappend {odd list;[$]} ${odd name;[$]} {}
    return ${odd list;[$]}
}
proc promoted-outer {} {
    set {odd name;[$]} untouched
    set result [promoted-inner]
    list [lindex $result 0] [lindex $result 1] ${odd name;[$]}
}
test promoted-nested-locals { promoted-outer } {3\;\[\$\] {} untouched}
test promoted-no-frame-leak { catch {set {odd list;[$]}} } 1
proc promoted-alias {} {
    global promoted_global
    incr promoted_global 2
    append ::promoted_global x
    lappend promoted_global {a b}
}
test promoted-global-alias { set ::promoted_global 1; promoted-alias; eq $::promoted_global [list 3x {a b}] } 1
test promoted-append-create {
    catch {unset promoted_new}
    set first [append promoted_new]
    append promoted_new {} " \t\r\n" {\;[$]} {}
    eq [list $first $promoted_new] [list {} " \t\r\n\\;\[\$\]"]
} 1
test promoted-lappend-create {
    catch {unset promoted_new_list}
    list [lappend promoted_new_list] [lappend promoted_new_list {}] [llength $promoted_new_list]
} {{} \{\} 1}
test promoted-canonical-empty { list [concat] [concat {} " \t\r\n"] } {{} {}}
test promoted-canonical-lists {
    set x {  "a b"  {c d} e\ f  {} }
    eq [concat $x {g}] [list {a b} {c d} {e f} {} g]
} 1
test promoted-lappend-canonical-no-values {
    set x {  "a b"  {c d} e\ f  {} }
    eq [lappend x] [list {a b} {c d} {e f} {}]
} 1
test promoted-list-data {
    set values [list {} "\t\r\n" "\\" {a;b} {[error executed]} {$missing} {{nested}}]
    set x {}
    foreach value $values { lappend x $value }
    eq [concat $x $values] [concat $values $values]
} 1
test promoted-malformed-atomic {
    set result {}
    set errors [list {missing close brace} {missing close quote} {trailing backslash} {extra characters after close quote or brace} {extra characters after close quote or brace}]
    set index 0
    foreach bad [list "\{" "\"" "a\\" "\{a\}b" "\"a\"b"] {
        set x $bad
        set code [catch {lappend x new} message options]
        if [ne $message [lindex $errors $index]] {error "unexpected diagnostic: $message"}
        lappend result [list $code [eq $x $bad] $options]
        set code [catch {lappend x}]
        lappend result [list $code [eq $x $bad]]
        lappend result [catch [list concat {valid} $bad]]
        incr index
    }
    eq $result [concat [list [list 1 1 {-code 1 -level 0}] {1 1} 1] [list [list 1 1 {-code 1 -level 0}] {1 1} 1] [list [list 1 1 {-code 1 -level 0}] {1 1} 1] [list [list 1 1 {-code 1 -level 0}] {1 1} 1] [list [list 1 1 {-code 1 -level 0}] {1 1} 1]]
} 1
proc promoted-flow {} {
    set n 0
    set output {}
    while {< $n 4} {
        incr n
        set x 2147483647
        catch {incr x} message options
        if [== $n 1] { continue }
        if [== $n 3] { break }
        lappend output $n
    }
    return [list $output $options $x]
}
test promoted-completion-flow { promoted-flow } {2 -code\ 1\ -level\ 0 2147483647}
test promoted-return-state {
    catch {return -code 4 -level 2 pending} value before
    set n 0
    incr n
    catch {incr n invalid} message after
    list $before $after $n
} {-code\ 4\ -level\ 2 -code\ 1\ -level\ 0 1}
