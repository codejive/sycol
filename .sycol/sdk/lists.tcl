# Shared SDK procedures; definitions only, with dependencies resolved at call time.

proc lappend {name args} {
    if [catch {uplevel 1 [list set $name]} value] { set value {} }
    # Re-encode existing elements too, and reject malformed input lists.
    set value [concat $value $args]
    uplevel 1 [list set $name $value]
}

proc concat {args} {
    set result {}
    set count [llength $args]
    set i 0
    while {< $i $count} {
        set part [lindex $args $i]
        set partCount [llength $part]
        set j 0
        while {< $j $partCount} {
            if [string length $result] { append result { } }
            append result [list [lindex $part $j]]
            incr j
        }
        incr i
    }
    return $result
}

proc join {items {separator { }}} {
    set result {}
    set count [llength $items]
    set i 0
    while {< $i $count} {
        if [> $i 0] { append result $separator }
        append result [lindex $items $i]
        incr i
    }
    return $result
}
