# The host driver registers host.echo without loading the SDK.
if [string equal [host.echo {literal ; $x [a]}] {literal ; $x [a]}] {} else {error {native argument changed}}
if [!= [catch {host.echo}] 1] {error {native arity was not checked}}
proc host.echo {} { return overridden }
if [string equal [host.echo native] native] {} else {error {native priority failed}}
puts {3 extension tests passed}
