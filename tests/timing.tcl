# Verify that the test-only native helper preserves interpreter completion state.
foreach completion {{normal {set value ok} 0 ok {-code 0 -level 0}} {error {error broken} 1 broken {-code 1 -level 0}} {return {return done} 2 done {-code 0 -level 1}} {break {break} 3 {} {-code 3 -level 0}} {continue {continue} 4 {} {-code 4 -level 0}} {return-level {return -code 1 -level 2 raised} 2 raised {-code 1 -level 2}}} {
    set name "timing-helper-[lindex $completion 0]"
    set code [catch [list test.time $name [lindex $completion 1]] value options]
    if [ne [list $code $value $options] [list [lindex $completion 2] [lindex $completion 3] [lindex $completion 4]]] {
        error "$name changed completion state"
    }
    puts "ok - $name"
}
set timing_probe before
test.time timing-helper-scope {set timing_probe {after ; $literal [brackets]}}
if [ne $timing_probe {after ; $literal [brackets]}] {error {timing helper changed scope or arguments}}
puts {ok - timing-helper-scope}
