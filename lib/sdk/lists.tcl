# Shared SDK procedures; definitions only, with dependencies resolved at call time.

proc lappend {name args} {
    if [catch {uplevel 1 [list set $name]} value] { set value {} }
    # Re-encode existing elements too, and reject malformed input lists.
    set value [concat $value $args]
    uplevel 1 [list set $name $value]
}

proc concat {args} {
    set result {}
    set i 0
    while {< $i [llength $args]} {
        set part [lindex $args $i]
        set j 0
        while {< $j [llength $part]} {
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
    set i 0
    while {< $i [llength $items]} {
        if [> $i 0] { append result $separator }
        append result [lindex $items $i]
        incr i
    }
    return $result
}
