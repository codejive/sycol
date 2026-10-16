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
foreach name {empty bom-empty} {
    if [ne [readfile "$directory/$name.tcl"] {}] { error "empty UTF-8 read changed: $name" }
    if [ne [source "$directory/$name.tcl"] {}] { error "empty UTF-8 source changed: $name" }
}
if [ne [readfile "$directory/trailing.tcl"] "$expected\r\n\n\n"] {
    error {readfile changed trailing line endings}
}
set encoding_side_effect unchanged
foreach name {nul nul-end} {
    foreach command {readfile source} {
        set path "$directory/$name.tcl"
        if [!= [catch [list $command $path] value] 1] { error "NUL accepted: $command $name" }
        if [ne $value "NUL in text file: $path"] { error "unexpected NUL error: $value" }
    }
}
if [ne $encoding_side_effect unchanged] { error {source ran before checking NUL} }
if [!= [source "$directory/locale.tcl"] [string length $expected]] {
    error {source changed the character indexing locale}
}
puts {UTF-8 file tests passed}
