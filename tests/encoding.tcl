# Both host drivers generate the same valid UTF-8 fixtures.
set directory [lindex $argv 0]
set expected [lindex $argv 1]
foreach name {plain bom} {
    set path "$directory/$name.tcl"
    if [ne [source $path] $expected] { error "UTF-8 source changed: $name" }
}
if [ne [readfile "$directory/plain.tcl"] [readfile "$directory/bom.tcl"]] {
    error {UTF-8 BOM was not removed}
}
puts {UTF-8 file tests passed}
