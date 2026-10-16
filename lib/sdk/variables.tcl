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
