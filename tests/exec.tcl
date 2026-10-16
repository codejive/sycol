# argv[0] is a list containing a native executable and its probe arguments.
set probe [lindex $argv 0]
set failed 0
proc check {name expected arguments} {
    global probe failed
    set actual [apply exec [concat $probe $arguments]]
    if [ne $actual $expected] {
        incr failed
        puts "FAIL - ${name}: expected ([list $expected]), got ([list $actual])"
    } else { puts "ok - $name" }
}
check exec-arguments {<><a b><; $literal [brackets]><"quoted"><end\>} [list args {} {a b} {; $literal [brackets]} {"quoted"} "end\\"]
check exec-newlines "line\n" {newlines}
check exec-carriage-return "line\r" {carriage}
set code [catch {apply exec [concat $probe {fail}]} message]
if [or {!= $code 1} {ne $message {process exited with status 7}}] {error "bad process failure: $code $message"}
puts {ok - exec-failure}
set original [pwd]
cd [lindex $argv 1]
check exec-cwd [pwd] {cwd}
cd $original
if [> $failed 0] {error "$failed process tests failed"}
puts {5 process tests passed}
