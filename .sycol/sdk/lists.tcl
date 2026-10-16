# Shared SDK procedures; definitions only, with dependencies resolved at call time.

# Resolve a list index against a caller-supplied end position. Decimal lindex
# calls inside this helper stay on the native fast path and cannot recurse.
proc sy.list.index {index length} {
    set size [string length $index]
    if [or {eq $index e} {or {eq $index en} {eq $index end}}] { return [- $length 1] }
    set split 1
    if [eq [string range $index 0 2] end] { set split 3 }
    while {< $split $size} {
        set op [string range $index $split $split]
        if [or {eq $op +} {eq $op -}] {
            set left [string range $index 0 [- $split 1]]
            set right [string range $index [+ $split 1] [- $size 1]]
            if [eq $left end] { set left [- $length 1] }
            return [$op $left $right]
        }
        incr split
    }
    return [+ $index 0]
}

proc lassign {items args} {
    set length [llength $items]
    set index 0
    foreach name $args {
        uplevel 1 [list set $name [lindex $items $index]]
        incr index
    }
    return [lrange $items $index [- $length 1]]
}

proc lrange {items first last} {
    set length [llength $items]
    set first [sy.list.index $first $length]
    set last [sy.list.index $last $length]
    if [< $first 0] { set first 0 }
    if [>= $last $length] { set last [- $length 1] }
    set result {}
    while {<= $first $last} {
        lappend result [lindex $items $first]
        incr first
    }
    return $result
}

proc linsert {items index args} {
    set length [llength $items]
    # For insertion Tcl's end denotes the position after the final element.
    set index [sy.list.index $index [+ $length 1]]
    if [< $index 0] { set index 0 }
    if [> $index $length] { set index $length }
    return [concat [lrange $items 0 [- $index 1]] $args [lrange $items $index end]]
}

proc lreplace {items first last args} {
    set length [llength $items]
    set first [sy.list.index $first $length]
    set last [sy.list.index $last $length]
    if [< $first 0] { set first 0 }
    if [> $first $length] { set first $length }
    if [< $last $first] { set last [- $first 1] }
    # Clamp before adding one, so a valid maximum index cannot overflow.
    if [>= $last $length] { set last [- $length 1] }
    return [concat [lrange $items 0 [- $first 1]] $args [lrange $items [+ $last 1] end]]
}

proc lreverse {items} {
    set index [llength $items]
    set result {}
    while {> $index 0} {
        incr index -1
        lappend result [lindex $items $index]
    }
    return $result
}

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
