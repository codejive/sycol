# Lexical path handling shared by both hosts. No filesystem access is needed
# except to expand a bare home name for dirname/tail, as in Tcl 8.6.
proc sy.path.parts {path windows} {
    # Split and recognize separators in one pass, without rebuilding the path
    # character by character first (particularly costly for long temp paths).
    set text $path
    set root {}
    if [and {set windows} {string equal [string range $text 1 1] :}] {
        set root [string range $text 0 1]
        set text [string range $text 2 [string length $text]]
        set first [string range $text 0 0]
        if [or {string equal $first /} {string equal $first "\\"}] { set root $root/ }
    }
    set names {}
    set word {}
    set index 0
    set length [string length $text]
    if $windows {
        while {< $index $length} {
            set char [string range $text $index $index]
            if [string equal $char "\\"] { set char / }
            if [string equal $char /] {
                if [string equal $word {}] {} else { lappend names $word; set word {} }
            } else { set word $word$char }
            set index [+ $index 1]
        }
    } else {
        while {< $index $length} {
            set char [string range $text $index $index]
            if [string equal $char /] {
                if [string equal $word {}] {} else { lappend names $word; set word {} }
            } else { set word $word$char }
            set index [+ $index 1]
        }
    }
    if [string equal $word {}] {} else { lappend names $word }
    if [string equal $root {}] {
        set first [string range $text 0 0]
        set second [string range $text 1 1]
        if $windows {
            if [string equal $first "\\"] { set first / }
            if [string equal $second "\\"] { set second / }
        }
        if [and {set windows} {and {string equal $first$second //} {>= [llength $names] 2}}] {
            set root //[lindex $names 0]/[lindex $names 1]
            set rest {}
            set count [llength $names]
            set index 2
            while {< $index $count} { lappend rest [lindex $names $index]; set index [+ $index 1] }
            set names $rest
        } else {
            if [string equal $first /] { set root / }
        }
    }
    list $root $names
}
proc sy.path.type {path windows} {
    set first [string range $path 0 0]
    if [string equal $first ~] { return absolute }
    if $windows {} else {
        if [string equal $first /] { return absolute }
        return relative
    }
    if [string equal [string range $path 1 1] :] {
        set third [string range $path 2 2]
        if [string equal $third /] { return absolute }
        if [string equal $third "\\"] { return absolute }
        return volumerelative
    }
    if [string equal $first "\\"] { set first / }
    if [string equal $first /] {} else { return relative }
    set second [string range $path 1 1]
    if [string equal $second "\\"] { set second / }
    if [string equal $second /] {} else { return volumerelative }
    # A UNC root needs two nonempty components. Stop as soon as the share
    # begins; neither the rest of the share nor the remaining path matters.
    set count 0
    set inWord 0
    set index 2
    set length [string length $path]
    while {< $index $length} {
        set char [string range $path $index $index]
        if [string equal $char "\\"] { set char / }
        if [string equal $char /] { set inWord 0 } else {
            if $inWord {} else {
                set count [+ $count 1]
                if [== $count 2] { return absolute }
                set inWord 1
            }
        }
        set index [+ $index 1]
    }
    return volumerelative
}
proc sy.path.render {root names} {
    set result $root
    foreach name $names {
        if [string equal $result {}] { set result $name } else {
            set last [string range $result [- [string length $result] 1] [string length $result]]
            if [or {string equal $last /} {and {string equal $result $root} {string equal $last :}}] {
                set result $result$name
            } else { set result $result/$name }
        }
    }
    return $result
}
proc sy.path.join {paths windows} {
    set root {}
    set names {}
    set trailingHome 0
    foreach path $paths {
        if [ne $path {}] {
            set parts [sy.path.parts $path $windows]
            set newRoot [lindex $parts 0]
            set newNames [lindex $parts 1]
            if [or {ne $newRoot {}} {string equal [string range $path 0 0] ~}] {
                set root $newRoot
                set names {}
            }
            # ./ protects a literal leading tilde only at the start of a path.
            if [and {> [llength $names] 0} {and {string equal [lindex $newNames 0] .} {string equal [string range [lindex $newNames 1] 0 0] ~}}] {
                set newNames [sy.path.dropfirst $newNames]
            }
            foreach name $newNames { lappend names $name }
            set last [string range $path [- [string length $path] 1] [string length $path]]
            set trailingHome [and {string equal [string range $path 0 0] ~} {and {== [llength $newNames] 1} {or {string equal $last /} {and {set windows} {string equal $last "\\"}}}}]
        }
    }
    set result [sy.path.render $root $names]
    if $trailingHome { set result $result/ }
    return $result
}
proc sy.path.dropfirst {names} {
    set result {}
    set count [llength $names]
    set index 1
    while {< $index $count} { lappend result [lindex $names $index]; set index [+ $index 1] }
    return $result
}
proc sy.path.component {operation path windows} {
    set parts [sy.path.parts $path $windows]
    set root [lindex $parts 0]
    set names [lindex $parts 1]
    if [and {string equal [string range $path 0 0] ~} {== [llength $names] 1}] {
        set parts [sy.path.parts [sy.file expand $path] $windows]
        set root [lindex $parts 0]
        set names [lindex $parts 1]
    }
    set last [- [llength $names] 1]
    if [string equal $operation tail] {
        set result [lindex $names $last]
        if [string equal [string range $result 0 0] ~] { set result ./$result }
        return $result
    }
    set parents {}
    set index 0
    while {< $index $last} { lappend parents [lindex $names $index]; set index [+ $index 1] }
    set result [sy.path.render $root $parents]
    if [string equal $result {}] { set result . }
    return $result
}
proc sy.path.extension {operation path windows} {
    # Only the last component can contribute an extension. Walk backwards
    # until its final dot or separator, retaining original string indices.
    set length [string length $path]
    set index [- $length 1]
    set dot -1
    while {>= $index 0} {
        set char [string range $path $index $index]
        if [string equal $char .] { set dot $index; break }
        if [string equal $char /] { break }
        if $windows { if [string equal $char "\\"] { break } }
        set index [- $index 1]
    }
    if [string equal $operation extension] {
        if [< $dot 0] { return {} }
        return [string range $path $dot $length]
    }
    if [< $dot 0] { return $path }
    string range $path 0 [- $dot 1]
}

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
