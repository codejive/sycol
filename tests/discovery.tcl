# Shared module-loader conformance, run in a copied installation.
proc check {name body expected} {
    set actual [uplevel 1 $body]
    if [eq $actual $expected] {} else { error "$name: expected [list $expected], got [list $actual]" }
}
check core-only { list [catch {file exists .}] [catch {sy.file windows}] [catch {rogue}] } {1 1 1}
check initial-path-lists { list [llength $::sycol_sdk_path] [llength $::sycol_native_path] [llength $::sycol_source_path] } {1 1 0}
source ./user/files.tcl
check user-no-native { list [user.files] [catch {sy.file windows}] } {user 1}
set ::tcl_loads 0
source sample.tcl
check native-first { list [replacement] [native.loads] $::tcl_loads } {native 1 1}
proc replacement {} { return application }
check application-cannot-shadow { replacement } native
source sample.tcl
check repeated-source { list [replacement] [native.loads] $::tcl_loads } {native 1 2}
source "[pwd]/.sycol/lib/sample.tcl"
check absolute-sdk { list [replacement] [native.loads] $::tcl_loads } {native 1 3}
source pure.tcl
check pure-tcl { portable } portable
check no-cwd-search { catch {source cwd-only.tcl} } 1
source ./cwd-only.tcl
check cwd-explicit { cwd.only } cwd
lappend ::sycol_source_path [fileless.path user]
source library.tcl
check user-search { library } user
lappend ::sycol_sdk_path [fileless.path extra-sdk]
lappend ::sycol_native_path [fileless.path extra-native]
source extra.tcl
check sdk-before-user { precedence } sdk
source secondary.tcl
check mutable-native-path { secondary.native } secondary
source sub/nested.tcl
check nested-backend { nested.native } nested
source {space name.tcl}
check spaces { space.native } space
check first-error { catch {source broken.tcl} message; set message } first-broken
check directory-first-match { catch {source directory.tcl} } 1
check directory-no-fallback { catch {wrong.directory.fallback} } 1
check backend-error { catch {source bad-native.tcl} } 1
check backend-error-cached { catch {source bad-native.tcl}; native.failed-loads } 1
check backend-prevents-tcl { catch {should.not.exist} } 1
check malformed-path-list {
    set saved $::sycol_source_path
    set ::sycol_source_path "\{"
    set code [catch {source absent.tcl}]
    set ::sycol_source_path $saved
    set code
} 1
source ./user/sample.tcl
check user-same-basename { user.sample } user
source ./.sycol/lib-sibling/outsider.tcl
check sdk-component-boundary { catch {outsider.native} } 1
source ././.sycol/lib/sub/../pure.tcl
check normalized-sdk { portable } portable
source files.tcl
check optional-files { file isfile .sycol/VERSION } 1
check native-fallback-after-path-change {
    set saved $::sycol_native_path
    set ::sycol_native_path {}
    source pure.tcl
    set ::sycol_native_path $saved
    portable
} portable
check source-scope {
    proc local.load {} { set marker before; source ./scope.tcl; return $marker }
    local.load
} after
check source-return { source ./return.tcl } returned
puts {module loading tests passed}
