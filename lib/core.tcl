# The shared SDK. Bodies and tests are Sycol source, never host shell snippets.
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

# Propagation must add this procedure boundary to the caught return level.
proc foreach {name items body} {
    set i 0
    while {< $i [llength $items]} {
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

proc eq {a b} { string equal $a $b }
proc ne {a b} { ! [eq $a $b] }

# Lazy boolean operators take scripts so unused operands have no side effects.
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

# Argument-list application; unlike eval, no argument becomes executable syntax.
proc apply {command arguments} {
    set code [catch {uplevel 1 [concat [list $command] $arguments]} value options]
    if [!= $code 0] { return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value }
    return $value
}
