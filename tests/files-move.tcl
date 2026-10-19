source files.tcl
# The drivers place these roots on different filesystems when available.
source ./tests/test-run.tcl
set from "[lindex $argv 0]/move-source"
set to "[lindex $argv 1]/move-target"
file mkdir $from $to
proc check {name actual expected} {
    if [ne $actual $expected] { error "$name: expected [list $expected], got [list $actual]" }
    puts "ok - $name"
}
# These fixed fixture suffixes need no lexical path processing. Path joining
# has its own suite; keep the move tests focused on filesystem operations.
test-run move-file {
writefile "$from/file" payload
file rename "$from/file" "$to/file"
check move-file [list [file exists "$from/file"] [readfile "$to/file"]] {0 payload}
}
test-run move-replace {
writefile "$from/overwrite" replacement
writefile "$to/overwrite" original
file rename -force "$from/overwrite" "$to/overwrite"
check move-replace [list [file exists "$from/overwrite"] [readfile "$to/overwrite"]] {0 replacement}
}
test-run move-directory {
file mkdir "$from/directory/sub"
writefile "$from/directory/sub/child" child
file rename "$from/directory" "$to/directory"
check move-directory [list [file exists "$from/directory"] [readfile "$to/directory/sub/child"]] {0 child}
}
test-run move-failure-retains-source {
writefile "$from/retained" retained
set code [catch {file rename "$from/retained" "$to/missing-parent/child"}]
check move-failure-retains-source [list $code [readfile "$from/retained"]] {1 retained}
}
file delete -force $from $to
puts {filesystem move tests passed}
