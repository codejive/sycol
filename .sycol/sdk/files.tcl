# Shared option parsing; sy.file supplies only host filesystem operations.
proc file {operation args} {
    # Resolve one candidate from Tcl's minimum unambiguous prefixes, then
    # validate the whole suffix. Do not re-enter file or rebuild its arguments.
    set prefix [string range $operation 0 1]
    set command {}
    set kind {}
    if [string equal $prefix co] { set command copy }
    if [string equal $prefix de] { set command delete }
    if [string equal $prefix ty] { set command type; set kind native }
    if [string equal $prefix mk] { set command mkdir }
    if [string equal $prefix di] { set command dirname; set kind path }
    if [string equal $prefix ta] { set command tail; set kind path }
    if [string equal $prefix ro] { set command rootname; set kind path }
    if [string equal $prefix si] { set command size; set kind native }
    set prefix [string range $operation 0 2]
    if [string equal $prefix exi] { set command exists; set kind native }
    if [string equal $prefix ext] { set command extension; set kind path }
    if [string equal $prefix isf] { set command isfile; set kind native }
    if [string equal $prefix isd] { set command isdirectory; set kind native }
    if [string equal $prefix ren] { set command rename }
    set prefix [string range $operation 0 0]
    if [string equal $prefix j] { set command join }
    if [string equal $prefix p] { set command pathtype; set kind path }
    if [string equal $operation list] { set command list }
    if [string equal $command {}] { error "unknown file operation: $operation" }
    if [string equal $operation [string range $command 0 [- [string length $operation] 1]]] {} else {
        error "unknown file operation: $operation"
    }
    set count [llength $args]
    set operation $command
    if [string equal $operation mkdir] {
        foreach path $args { sy.file mkdir $path }
        return {}
    }
    if [string equal $operation join] {
        if [== $count 0] { error {wrong # args: file join name ?name ...?} }
        return [sy.path.join $args [sy.file windows]]
    }
    if [string equal $kind path] {
        if [!= $count 1] { error "wrong # args: file $operation path" }
        if [string equal $operation pathtype] {
            return [sy.path.type [lindex $args 0] [sy.file windows]]
        }
        if [or {eq $operation extension} {eq $operation rootname}] {
            return [sy.path.extension $operation [lindex $args 0] [sy.file windows]]
        }
        return [sy.path.component $operation [lindex $args 0] [sy.file windows]]
    }
    if [string equal $operation list] {
        if [== $count 0] { return [sy.file list .] }
        if [!= $count 1] { error {wrong # args: file list ?path?} }
        return [sy.file list [lindex $args 0]]
    }
    if [string equal $kind native] {
        if [!= $count 1] { error "wrong # args: file $operation path" }
        return [sy.file $operation [lindex $args 0]]
    }
    set force 0
    set index 0
    while {< $index $count} {
        set option [lindex $args $index]
        if [string equal $option --] { incr index; break }
        if [ne [string range $option 0 0] -] { break }
        if [ne $option -force] { error "unknown file option: $option" }
        set force 1
        incr index
    }
    if [string equal $operation delete] {
        while {< $index $count} {
            sy.file delete [lindex $args $index] $force
            incr index
        }
        return {}
    }
    if [< [- $count $index] 2] { error "wrong # args: file $operation ?-force? ?--? source ?source ...? target" }
    set last [- $count 1]
    set target [lindex $args $last]
    set directory [sy.file isdirectory $target]
    if [and {> [- $last $index] 1} {! $directory}] { error "$operation target must be a directory: $target" }
    while {< $index $last} {
        sy.file $operation [lindex $args $index] $target $force $directory
        incr index
    }
    return {}
}
