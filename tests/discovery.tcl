# Executed against a copied installation with extra discovered library files.
if [string equal [native.order] last] {} else { error {native load order changed} }
if [string equal [sdk.order] last] {} else { error {SDK load order changed} }
if [string equal [getenv ignored] overridden] {} else { error {native override failed} }
set words [native.echo {literal ; $x [a]} {} {two words}]
if [== [llength $words] 3] {} else { error {native arguments split} }
if [string equal [lindex $words 0] {literal ; $x [a]}] {} else { error {native argument substituted} }
if [string equal [lindex $words 1] {}] {} else { error {empty native argument lost} }
if [string equal [lindex $words 2] {two words}] {} else { error {native argument changed} }
if [== [catch {Native.echo}] 1] {} else { error {native lookup ignored case} }
proc native.order {} { return script }
if [string equal [native.order] script] {} else { error {procedure override failed} }
puts {discovery tests passed}
