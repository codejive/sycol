# Shared portable core; native commands always take precedence.

# Shared SDK procedures; definitions only, with dependencies resolved at call time.
# Caller-script completion propagation adds this procedure boundary to return levels.

proc foreach {name items body} {
    set count [llength $items]
    set i 0
    while {< $i $count} {
        uplevel 1 [list set $name [lindex $items $i]]
        set code [catch {uplevel 1 $body} value options]
        if [== $code 3] { break }
        if [== $code 4] { set code 0 }
        if [!= $code 0] {
            return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value
        }
        incr i
    }
    return {}
}

proc for {initial test step body} {
    set code [catch {uplevel 1 $initial} value options]
    if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
    while {== 1 1} {
        set code [catch {uplevel 1 $test} value options]
        if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
        if $value {} else { break }
        set code [catch {uplevel 1 $body} value options]
        if [== $code 3] { break }
        if [== $code 4] { set code 0 }
        if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
        set code [catch {uplevel 1 $step} value options]
        if [== $code 3] { break }
        if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
    }
    return {}
}

# Lazy boolean operators evaluate scripts in the caller and skip unused operands.
proc and {left right} {
    set code [catch {uplevel 1 $left} value options]
    if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
    if $value {
        set code [catch {uplevel 1 $right} value options]
        if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
        if $value { return 1 }
    }
    return 0
}

proc or {left right} {
    set code [catch {uplevel 1 $left} value options]
    if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
    if $value { return 1 }
    set code [catch {uplevel 1 $right} value options]
    if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
    if $value { return 1 }
    return 0
}

# Named-command/list invocation, retaining argument boundaries.
proc apply {command arguments} {
    set code [catch {uplevel 1 [concat [list $command] $arguments]} value options]
    if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
    return $value
}

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

# Shared SDK procedures; definitions only, with dependencies resolved at call time.

proc eq {a b} { string equal $a $b }

proc ne {a b} { ! [eq $a $b] }

# Shared SDK procedures; definitions only, with dependencies resolved at call time.

proc incr {name {amount 1}} {
    set value [+ [uplevel 1 [list set $name]] $amount]
    uplevel 1 [list set $name $value]
}

proc append {name args} {
    if [catch {uplevel 1 [list set $name]} value] { set value {} }
    set i 0
    while {< $i [llength $args]} {
        set value "$value[lindex $args $i]"
        incr i
    }
    uplevel 1 [list set $name $value]
}
