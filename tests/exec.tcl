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
foreach status {0 7} {
    set result [apply exec [concat {-capture --} $probe [list capture $status]]]
    set expected [list $status "out ; \[literal\] {x} \\ \"\r\n\n" "err\r\n\n"]
    if [ne $result $expected] {error "bad capture: $result"}
    set result [apply exec [concat {-capture} $probe [list empty $status]]]
    if [ne $result [list $status {} {}]] {error "bad empty capture: $result"}
}
set result [apply exec [concat {-capture} $probe {large}]]
if [ne [lindex $result 0] 0] {error {large capture failed}}
foreach index {1 2} {
    if [!= [string length [lindex $result $index]] 131072] {error {large capture truncated}}
}
set result [apply exec [concat {-capture --} $probe [list args {} {a b} {2>@1} {-capture} {--}]]]
if [ne $result [list 0 "<><a b><2>@1><-capture><-->\n" {}]] {error {capture argument boundaries changed}}
set result [apply exec [concat {--} $probe {newlines}]]
if [ne $result "line\n"] {error {plain exec -- changed newline handling}}
foreach arguments {{} {-capture} {--} {-capture --}} {
    if [!= [catch {apply exec $arguments} message] 1] {error {missing program accepted}}
}
if [!= [catch {exec -capture -- ./sycol-nonexistent-program} message] 1] {error {missing executable accepted}}
if [ne $message {cannot execute: ./sycol-nonexistent-program}] {error "bad launch error: $message"}
puts {ok - exec-capture}
set original [pwd]
cd [lindex $argv 1]
check exec-cwd [pwd] {cwd}
cd $original
if [> $failed 0] {error "$failed process tests failed"}
puts {process tests passed}
