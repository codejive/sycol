# Lexical path handling shared by both hosts. No filesystem access is needed
# except to expand a bare home name for dirname/tail, as in Tcl 8.6.
proc sy.path.parts {path windows} {
    set text {}
    set index 0
    while {< $index [string length $path]} {
        set char [string range $path $index $index]
        if [and {set windows} {eq $char "\\"}] { set char / }
        set text $text$char
        set index [+ $index 1]
    }
    set root {}
    if [and {set windows} {eq [string range $text 1 1] :}] {
        set root [string range $text 0 1]
        set text [string range $text 2 [string length $text]]
        if [eq [string range $text 0 0] /] { set root $root/ }
    }
    set names {}
    set word {}
    set index 0
    while {<= $index [string length $text]} {
        set char [string range $text $index $index]
        if [or {eq $char /} {eq $char {}}] {
            if [ne $word {}] { lappend names $word; set word {} }
        } else { set word $word$char }
        set index [+ $index 1]
    }
    if [eq $root {}] {
        if [and {set windows} {and {eq [string range $text 0 1] //} {>= [llength $names] 2}}] {
            set root //[lindex $names 0]/[lindex $names 1]
            set rest {}
            set index 2
            while {< $index [llength $names]} { lappend rest [lindex $names $index]; set index [+ $index 1] }
            set names $rest
        } else {
            if [eq [string range $text 0 0] /] { set root / }
        }
    }
    list $root $names
}
proc sy.path.render {root names} {
    set result $root
    foreach name $names {
        if [eq $result {}] { set result $name } else {
            set last [string range $result [- [string length $result] 1] [string length $result]]
            if [or {eq $last /} {and {eq $result $root} {eq $last :}}] {
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
            if [or {ne $newRoot {}} {eq [string range $path 0 0] ~}] {
                set root $newRoot
                set names {}
            }
            # ./ protects a literal leading tilde only at the start of a path.
            if [and {> [llength $names] 0} {and {eq [lindex $newNames 0] .} {eq [string range [lindex $newNames 1] 0 0] ~}}] {
                set newNames [sy.path.dropfirst $newNames]
            }
            foreach name $newNames { lappend names $name }
            set last [string range $path [- [string length $path] 1] [string length $path]]
            set trailingHome [and {eq [string range $path 0 0] ~} {and {== [llength $newNames] 1} {or {eq $last /} {and {set windows} {eq $last "\\"}}}}]
        }
    }
    set result [sy.path.render $root $names]
    if $trailingHome { set result $result/ }
    return $result
}
proc sy.path.dropfirst {names} {
    set result {}
    set index 1
    while {< $index [llength $names]} { lappend result [lindex $names $index]; set index [+ $index 1] }
    return $result
}
proc sy.path.component {operation path windows} {
    set parts [sy.path.parts $path $windows]
    set root [lindex $parts 0]
    set names [lindex $parts 1]
    if [and {eq [string range $path 0 0] ~} {== [llength $names] 1}] {
        set parts [sy.path.parts [sy.file expand $path] $windows]
        set root [lindex $parts 0]
        set names [lindex $parts 1]
    }
    set last [- [llength $names] 1]
    if [eq $operation tail] {
        set result [lindex $names $last]
        if [eq [string range $result 0 0] ~] { set result ./$result }
        return $result
    }
    set parents {}
    set index 0
    while {< $index $last} { lappend parents [lindex $names $index]; set index [+ $index 1] }
    set result [sy.path.render $root $parents]
    if [eq $result {}] { set result . }
    return $result
}
proc sy.path.extension {operation path windows} {
    set dot -1
    set index 0
    while {< $index [string length $path]} {
        set char [string range $path $index $index]
        if [or {eq $char /} {and {set windows} {eq $char "\\"}}] { set dot -1 } else {
            if [eq $char .] { set dot $index }
        }
        set index [+ $index 1]
    }
    if [eq $operation extension] {
        if [< $dot 0] { return {} }
        return [string range $path $dot [string length $path]]
    }
    if [< $dot 0] { return $path }
    string range $path 0 [- $dot 1]
}
