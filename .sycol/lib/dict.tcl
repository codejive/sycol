# Optional string-valued dictionaries. No native handlers or persistent state.

# Validate the whole dictionary before lookup; the last duplicate value wins.
proc sy.dict.find {dictionary key} {
    set count [llength $dictionary]
    if [% $count 2] { error {missing value to go with key} }
    set found -1
    set index 0
    while {< $index $count} {
        if [eq [lindex $dictionary $index] $key] { set found $index }
        incr index 2
    }
    return $found
}

# Preserve each key's first position while replacing its value on duplicates.
proc sy.dict.normalize {dictionary} {
    set count [llength $dictionary]
    if [% $count 2] { error {missing value to go with key} }
    set result {}
    set index 0
    while {< $index $count} {
        set key [lindex $dictionary $index]
        set value [lindex $dictionary [+ $index 1]]
        set position [sy.dict.find $result $key]
        if [< $position 0] {
            lappend result $key $value
        } else {
            set position [+ $position 1]
            set result [lreplace $result $position $position $value]
        }
        incr index 2
    }
    return $result
}

proc sy.dict.get {dictionary keys} {
    foreach key $keys {
        set index [sy.dict.find $dictionary $key]
        if [< $index 0] { error "key \"$key\" not known in dictionary" }
        set dictionary [lindex $dictionary [+ $index 1]]
    }
    return $dictionary
}

proc sy.dict.put {dictionary key value remove} {
    set dictionary [sy.dict.normalize $dictionary]
    set index [sy.dict.find $dictionary $key]
    if $remove {
        if [>= $index 0] { set dictionary [lreplace $dictionary $index [+ $index 1]] }
    } else {
        if [< $index 0] {
            lappend dictionary $key $value
        } else {
            set index [+ $index 1]
            set dictionary [lreplace $dictionary $index $index $value]
        }
    }
    return $dictionary
}

# Walk and rebuild paths iteratively: key depth does not consume call frames.
proc sy.dict.update {dictionary keys value remove} {
    set parents {}
    set last [- [llength $keys] 1]
    set index 0
    while {< $index $last} {
        set key [lindex $keys $index]
        set position [sy.dict.find $dictionary $key]
        lappend parents $dictionary
        if [< $position 0] {
            if $remove { error "key \"$key\" not known in dictionary" }
            set dictionary {}
        } else {
            set dictionary [lindex $dictionary [+ $position 1]]
        }
        incr index
    }
    set dictionary [sy.dict.put $dictionary [lindex $keys $last] $value $remove]
    while {> $index 0} {
        incr index -1
        set dictionary [sy.dict.put [lindex $parents $index] [lindex $keys $index] $dictionary 0]
    }
    return $dictionary
}

proc dict {args} {
    set count [llength $args]
    if [== $count 0] { error {wrong # args: dict operation ?arg ...?} }
    set operation [lindex $args 0]
    # Resolve against Tcl 8.6's full vocabulary so omitted operations still
    # reserve ambiguous prefixes (notably u for unset/update).
    set resolved {}
    set end [- [string length $operation] 1]
    if [>= $end 0] {
        foreach candidate {append create exists filter for get incr info keys lappend map merge remove replace set size unset update values with} {
            if [eq $operation $candidate] { set resolved $candidate; break }
            if [eq $operation [string range $candidate 0 $end]] {
                if [ne $resolved {}] { error "unknown or ambiguous dict operation: $operation" }
                set resolved $candidate
            }
        }
    }
    if [eq $resolved {}] { error "unknown dict operation: $operation" }
    set operation $resolved
    if [eq $operation create] {
        if [== [% $count 2] 0] { error {wrong # args: dict create ?key value ...?} }
        return [sy.dict.normalize [lrange $args 1 end]]
    }
    if [eq $operation get] {
        if [< $count 2] { error {wrong # args: dict get dictionaryValue ?key ...?} }
        if [== $count 2] { return [sy.dict.normalize [lindex $args 1]] }
        return [sy.dict.get [lindex $args 1] [lrange $args 2 end]]
    }
    if [eq $operation exists] {
        if [< $count 3] { error {wrong # args: dict exists dictionaryValue key ?key ...?} }
        # Tcl 8.6 returns false for malformed dictionaries along the path too.
        return [! [catch {sy.dict.get [lindex $args 1] [lrange $args 2 end]}]]
    }
    if [or {eq $operation keys} {eq $operation size}] {
        if [!= $count 2] { error "wrong # args: dict $operation dictionaryValue" }
        set dictionary [sy.dict.normalize [lindex $args 1]]
        set length [llength $dictionary]
        if [eq $operation size] { return [/ $length 2] }
        set keys {}
        set index 0
        while {< $index $length} {
            lappend keys [lindex $dictionary $index]
            incr index 2
        }
        return $keys
    }
    if [or {eq $operation set} {eq $operation unset}] {
        set remove [eq $operation unset]
        if $remove {
            if [< $count 3] { error {wrong # args: dict unset dictionaryVariable key ?key ...?} }
            set keys [lrange $args 2 end]
            set value {}
        } else {
            if [< $count 4] { error {wrong # args: dict set dictionaryVariable key ?key ...? value} }
            set keys [lrange $args 2 end-1]
            set value [lindex $args end]
        }
        set name [lindex $args 1]
        if [eq $name {}] { error {empty variable name} }
        if [catch {uplevel 1 [list set $name]} dictionary] { set dictionary {} }
        set dictionary [sy.dict.update $dictionary $keys $value $remove]
        # Commit only after every traversed dictionary has been validated.
        return [uplevel 1 [list set $name $dictionary]]
    }
    error "unknown dict operation: $operation"
}
