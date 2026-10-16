# Shared list contracts and literal data boundaries.
test list-index-end { lindex {a b c d} end } d
test list-index-offsets { list [lindex {a b c d} end-1] [lindex {a b c d} 1+1] [lindex {a b c d} 3-2] } {c c b}
test list-index-end-abbreviations { list [lindex {a b} e] [lindex {a b} en] } {b b}
test list-index-empty-end { lindex {} end } {}
test list-index-outside-end { list [lindex {a b} end+1] [lindex {a b} end-3] } {{} {}}
test list-index-decimal { list [lindex {a b c} +0001] [lindex {a b c} end-0001] } {b b}
test list-index-signed-offset { lindex {a b c} end+-1 } b
test list-index-overflow { lindex {a b} end+2147483647 } {integer overflow} 1
test list-index-underflow { lindex {} end-2147483647 } {}
test list-index-invalid {
    foreach index {end- endx END {end -1} {end-1;error hacked} 1+2+3} {
        if [!= [catch {lindex {a b} $index}] 1] { error "accepted invalid index: $index" }
    }
    return -level 0 ok
} ok

test lassign-basic { lassign {0 output errors} status stdout stderr; list $status $stdout $stderr } {0 output errors}
test lassign-short { set b old; lassign {a} a b c; list $a $b $c } {a {} {}}
test lassign-rest { lassign {a b c d} first second } {c d}
test lassign-no-names { lassign {a {b c} {}} } [list a {b c} {}]
test lassign-no-rest { lassign {a b} first second } {}
test lassign-empty { lassign {} a; set a } {}
proc list-assign-local {} { lassign {inner global} value ::list_assignment; return $value }
test lassign-scope { set value outer; list [list-assign-local] $value $::list_assignment } {inner outer global}
test lassign-names { lassign {one two} {odd name} {x; error injected}; list ${odd name} [set {x; error injected}] } {one two}
test lassign-repeated { lassign {a b} repeated repeated; set repeated } b
test lassign-empty-name { lassign {a} {} } {empty variable name} 1
test lassign-malformed-before-assignment {
    set target unchanged
    catch {lassign "a \{" target}
    set target
} unchanged

test lrange-basic { lrange {a b c d} 1 2 } {b c}
test lrange-relative { lrange {a b c d} 1 end-1 } {b c}
test lrange-clamp { lrange {a b c} -99 99 } {a b c}
test lrange-empty { list [lrange {} 0 end] [lrange {a b} 2 0] [lrange {a b} 0 -1] } {{} {} {}}
test lrange-single-list { lrange {{a b} c} 0 0 } [list {a b}]
test linsert-basic { linsert {a d} 1 b c } {a b c d}
test linsert-end { linsert {a b} end c d } {a b c d}
test linsert-end-offset { linsert {a b c} end-1 x y } {a b x y c}
test linsert-clamp { list [linsert {a b} -99 x] [linsert {a b} 99 x] } [list {x a b} {a b x}]
test linsert-empty { linsert {} end x } x
test linsert-no-elements { linsert {a b} 1 } {a b}
test lreplace-basic { lreplace {a b c d} 1 2 x y z } {a x y z d}
test lreplace-delete { lreplace {a b c} end end } {a b}
test lreplace-insert { lreplace {a b c} 1 0 x } {a x b c}
test lreplace-prepend { lreplace {a b} -10 -1 x } {x a b}
test lreplace-append { lreplace {a b} 99 100 x } {a b x}
test lreplace-clamp { lreplace {a b c} -10 99 x } x
test lreplace-empty { lreplace {} 0 end x y } {x y}
test lreplace-max-index { lreplace {a b} 2147483647 2147483647 x } {a b x}
test lreverse-basic { lreverse {a b c} } {c b a}
test lreverse-empty { lreverse {} } {}
test list-edit-literal-boundaries {
    set original [list {} {a b} {$missing [error hacked];} "line\nend"]
    set reversed [lreverse $original]
    set inserted [linsert $reversed 2 {x y}]
    set restored [lreplace $inserted 2 2]
    eq [lreverse $restored] $original
} 1
test list-edit-malformed {
    foreach command {lrange linsert lreplace lreverse lassign} {
        set arguments [list "a \{"]
        if [eq $command lrange] { lappend arguments 0 end }
        if [eq $command linsert] { lappend arguments 0 x }
        if [eq $command lreplace] { lappend arguments 0 1 x }
        if [!= [catch {apply $command $arguments}] 1] { error "accepted malformed list: $command" }
    }
    return -level 0 ok
} ok
test list-edit-arity {
    foreach script {{lassign} {lrange a 0} {lrange a 0 1 extra} {linsert a} {lreplace a 0} {lreverse} {lreverse a b}} {
        if [!= [catch $script] 1] { error "accepted invalid arguments: $script" }
    }
    return -level 0 ok
} ok
