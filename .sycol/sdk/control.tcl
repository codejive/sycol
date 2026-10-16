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
