# The drivers place these roots on different filesystems when available.
set from [file join [lindex $argv 0] move-source]
set to [file join [lindex $argv 1] move-target]
file mkdir $from $to
proc check {name actual expected} {
    if [ne $actual $expected] { error "$name: expected [list $expected], got [list $actual]" }
    puts "ok - $name"
}
writefile [file join $from file] payload
file rename [file join $from file] [file join $to file]
check move-file [list [file exists [file join $from file]] [readfile [file join $to file]]] {0 payload}
writefile [file join $from overwrite] replacement
writefile [file join $to overwrite] original
file rename -force [file join $from overwrite] [file join $to overwrite]
check move-replace [list [file exists [file join $from overwrite]] [readfile [file join $to overwrite]]] {0 replacement}
file mkdir [file join $from directory sub]
writefile [file join $from directory sub child] child
file rename [file join $from directory] [file join $to directory]
check move-directory [list [file exists [file join $from directory]] [readfile [file join $to directory sub child]]] {0 child}
writefile [file join $from retained] retained
set code [catch {file rename [file join $from retained] [file join $to missing-parent child]}]
check move-failure-retains-source [list $code [readfile [file join $from retained]]] {1 retained}
file delete -force $from $to
puts {filesystem move tests passed}
