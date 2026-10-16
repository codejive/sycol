# Shared option parsing; sy.file supplies only host filesystem operations.
proc file {operation args} {
    # These abbreviations are unambiguous in full Tcl's larger file command.
    foreach entry {{copy 2} {delete 2} {type 2} {mkdir 2} {exists 3} {isfile 3} {isdirectory 3} {join 1} {dirname 2} {tail 2} {extension 3} {rootname 2} {size 2} {rename 3}} {
        set command [lindex $entry 0]
        if [and {>= [string length $operation] [lindex $entry 1]} {eq $operation [string range $command 0 [- [string length $operation] 1]]}] { set operation $command }
    }
    if [eq $operation mkdir] {
        foreach path $args { sy.file mkdir $path }
        return {}
    }
    if [eq $operation join] {
        if [== [llength $args] 0] { error {wrong # args: file join name ?name ...?} }
        return [sy.path.join $args [sy.file windows]]
    }
    foreach command {dirname tail extension rootname} {
        if [eq $operation $command] {
            if [!= [llength $args] 1] { error "wrong # args: file $operation path" }
            if [or {eq $operation extension} {eq $operation rootname}] {
                return [sy.path.extension $operation [lindex $args 0] [sy.file windows]]
            }
            return [sy.path.component $operation [lindex $args 0] [sy.file windows]]
        }
    }
    if [eq $operation list] {
        if [== [llength $args] 0] { return [sy.file list .] }
        if [!= [llength $args] 1] { error {wrong # args: file list ?path?} }
        return [sy.file list [lindex $args 0]]
    }
    foreach command {type exists isfile isdirectory size} {
        if [eq $operation $command] {
            if [!= [llength $args] 1] { error "wrong # args: file $operation path" }
            return [sy.file $operation [lindex $args 0]]
        }
    }
    if [and {ne $operation delete} {and {ne $operation copy} {ne $operation rename}}] { error "unknown file operation: $operation" }
    set force 0
    set index 0
    while {< $index [llength $args]} {
        set option [lindex $args $index]
        if [eq $option --] { incr index; break }
        if [ne [string range $option 0 0] -] { break }
        if [ne $option -force] { error "unknown file option: $option" }
        set force 1
        incr index
    }
    if [eq $operation delete] {
        while {< $index [llength $args]} {
            sy.file delete [lindex $args $index] $force
            incr index
        }
        return {}
    }
    if [< [- [llength $args] $index] 2] { error "wrong # args: file $operation ?-force? ?--? source ?source ...? target" }
    set last [- [llength $args] 1]
    set target [lindex $args $last]
    set directory [sy.file isdirectory $target]
    if [and {> [- $last $index] 1} {! $directory}] { error "$operation target must be a directory: $target" }
    while {< $index $last} {
        sy.file $operation [lindex $args $index] $target $force $directory
        incr index
    }
    return {}
}
