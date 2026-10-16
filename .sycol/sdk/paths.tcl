# Lexical path handling shared by both hosts. No filesystem access is needed
# except to expand a bare home name for dirname/tail, as in Tcl 8.6.
proc sy.path.parts {path windows} {
    # Split and recognize separators in one pass, without rebuilding the path
    # character by character first (particularly costly for long temp paths).
    set text $path
    set root {}
    if [and {set windows} {eq [string range $text 1 1] :}] {
        set root [string range $text 0 1]
        set text [string range $text 2 [string length $text]]
        set first [string range $text 0 0]
        if [or {eq $first /} {eq $first "\\"}] { set root $root/ }
    }
    set names {}
    set word {}
    set index 0
    while {<= $index [string length $text]} {
        set char [string range $text $index $index]
        if [eq $char "\\"] { if $windows { set char / } }
        if [or {eq $char /} {eq $char {}}] {
            if [ne $word {}] { lappend names $word; set word {} }
        } else { set word $word$char }
        set index [+ $index 1]
    }
    if [eq $root {}] {
        set first [string range $text 0 0]
        set second [string range $text 1 1]
        if $windows {
            if [eq $first "\\"] { set first / }
            if [eq $second "\\"] { set second / }
        }
        if [and {set windows} {and {eq $first$second //} {>= [llength $names] 2}}] {
            set root //[lindex $names 0]/[lindex $names 1]
            set rest {}
            set index 2
            while {< $index [llength $names]} { lappend rest [lindex $names $index]; set index [+ $index 1] }
            set names $rest
        } else {
            if [eq $first /] { set root / }
        }
    }
    list $root $names
}
proc sy.path.type {path windows} {
    if [eq [string range $path 0 0] ~] { return absolute }
    set root [lindex [sy.path.parts $path $windows] 0]
    if [eq $root {}] { return relative }
    if $windows {
        if [or {eq $root /} {and {== [string length $root] 2} {eq [string range $root 1 1] :}}] {
            return volumerelative
        }
    }
    return absolute
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
