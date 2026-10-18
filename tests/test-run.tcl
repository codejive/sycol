# Run one named body in the caller's frame, optionally recording elapsed time.
proc test-run {name body} {
    if [ne [getenv SYCOL_TIMING_FILE] {}] {
        set code [catch {uplevel 1 [list test.time $name $body]} value options]
    } else { set code [catch {uplevel 1 $body} value options] }
    return -code [lindex $options 1] -level [+ [lindex $options 3] 1] $value
}
