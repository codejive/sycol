# Shared optional dictionary contracts; no host-specific helpers.
test dict-before-load { catch {dict create} } 1
source dict.tcl

test dict-empty { list [dict create] [dict keys {}] [dict size {}] [dict get {}] } {{} {} 0 {}}
test dict-create { dict create host localhost port 8080 } {host localhost port 8080}
test dict-get { dict get {host localhost port 8080} host } localhost
test dict-get-all { dict get {a 1 b 2 a 3} } {a 3 b 2}
test dict-duplicates { list [dict create a 1 b 2 a 3] [dict keys {a 1 b 2 a 3}] [dict size {a 1 b 2 a 3}] [dict get {a 1 b 2 a 3} a] } [list {a 3 b 2} {a b} 2 3]
test dict-case { list [dict size {Host one host two}] [dict get {Host one host two} Host] [dict exists {Host one} host] } {2 one 0}
test dict-empty-key-value { set d [dict create {} {} x value]; list [dict exists $d {}] [dict get $d {}] [lindex [dict keys $d] 0] } {1 {} {}}
test dict-literal-data {
    set key {a; error injected $missing [bad]}
    set value "space \" brace \{ slash \\ tab\tline\nnext"
    set d [dict create $key $value]
    list [eq [dict get $d $key] $value] [eq [lindex [dict keys $d] 0] $key]
} {1 1}
test dict-unicode { dict get [dict create café 日本語] café } 日本語
test dict-equivalent-list { dict get "a \"b c\"" a } {b c}
test dict-exists { list [dict exists {a {b {}}} a] [dict exists {a {b {}}} a b] [dict exists {a {b {}}} a c] [dict exists {} a b] } {1 1 0 0}
test dict-exists-invalid { list [dict exists {a} a] [dict exists "\{" a] [dict exists {a odd} a b] [dict exists {a 1 dangling} a] } {0 0 0 0}
test dict-missing-key { dict get {a 1} absent } {key "absent" not known in dictionary} 1
test dict-nested-get { dict get {a {b {c value}}} a b c } value
test dict-nested-missing { dict get {a {b 1}} a absent } {key "absent" not known in dictionary} 1
test dict-leaf-is-opaque { dict get {a odd} a } odd
test dict-malformed-get { dict get {a 1 dangling} a } {missing value to go with key} 1
test dict-malformed-nested { dict get {a odd} a b } {missing value to go with key} 1
test dict-malformed-list { dict size "a \{" } {missing close brace} 1
test dict-malformed-reads {
    foreach operation {get keys size} {
        if [!= [catch {dict $operation {a}} message] 1] { error "accepted odd dictionary: $operation" }
        if [ne $message {missing value to go with key}] { error $message }
    }
    set message
} {missing value to go with key}
test dict-set-create { dict set dict_new_variable port 8080 } {port 8080}
test dict-set-return { set d {a 1 b 2}; set result [dict set d a 3]; list $d $result } [list {a 3 b 2} {a 3 b 2}]
test dict-set-append { set d {a 1 b 2}; dict set d c 3; dict keys $d } {a b c}
test dict-set-duplicates { set d {a 1 b 2 a 3}; dict set d a 4 } {a 4 b 2}
test dict-copy { set original [dict create port 8080]; set copy $original; dict set copy port 9000; list [dict get $original port] [dict get $copy port] } {8080 9000}
test dict-nested-set-create { dict set dict_new_nested a b c value; dict get $dict_new_nested a b c } value
test dict-nested-set-preserve {
    set d {before 1 a {first 2 b old last 3} after 4}
    dict set d a b new
    list [dict keys $d] [dict keys [dict get $d a]] [dict get $d a b]
} [list {before a after} {first b last} new]
test dict-nested-copy { set original {a {b 1}}; set copy $original; dict set copy a b 2; list [dict get $original a b] [dict get $copy a b] } {1 2}
test dict-unset-return { set d {a 1 b 2}; list [dict unset d a] $d } [list {b 2} {b 2}]
test dict-unset-missing-leaf { set d {a 1}; dict unset d absent } {a 1}
test dict-unset-missing-variable { list [dict unset dict_unset_new a] $dict_unset_new } {{} {}}
test dict-unset-missing-parent { set d {}; dict unset d absent child } {key "absent" not known in dictionary} 1
test dict-unset-no-create-on-error { catch {dict unset dict_unset_failed a b}; catch {set dict_unset_failed} } 1
test dict-unset-duplicates { set d {a 1 b 2 a 3}; dict unset d a } {b 2}
test dict-unset-retains-parent { set d {a {b {c value}}}; dict unset d a b c; list [dict exists $d a b] [dict size [dict get $d a b]] } {1 0}
test dict-unset-reinsert-order { set d {a 1 b 2}; dict unset d a; dict set d a 3; dict keys $d } {b a}
test dict-mutation-atomic {
    foreach operation {set unset} {
        foreach bad [list {odd} "a \{"] {
            set d $bad
            if [eq $operation set] { set code [catch {dict set d a value}] } else { set code [catch {dict unset d a}] }
            if [!= $code 1] { error "accepted malformed dictionary: $operation" }
            if [ne $d $bad] { error "changed dictionary on error: $operation" }
        }
    }
    set code
} 1
test dict-nested-mutation-atomic {
    set original {before 1 a {b odd} after 2}
    set d $original
    catch {dict set d a b c value}
    set first [eq $d $original]
    catch {dict unset d a b c}
    list $first [eq $d $original]
} {1 1}
proc dict-local-scope {} {
    set d {local 1}
    dict set d local 2
    dict set ::dict_global value 3
    global dict_alias
    dict set dict_alias value 4
    dict unset d local
    return $d
}
test dict-scope { set d {outer 1}; set ::dict_global {}; set ::dict_alias {}; list [dict-local-scope] $d [dict get $::dict_global value] [dict get $::dict_alias value] } [list {} {outer 1} 3 4]
test dict-variable-names { dict set {odd name; error injected} {a b} value; dict get [set {odd name; error injected}] {a b} } value
test dict-empty-name-set { dict set {} a b } {empty variable name} 1
test dict-empty-name-unset { dict unset {} a } {empty variable name} 1
test dict-path-is-separate-arguments { set d {}; dict set d {a b} value; list [dict get $d {a b}] [dict exists $d a b] } {value 0}
test dict-long-path {
    set keys {}
    set index 0
    while {< $index 6} { lappend keys k$index; incr index }
    apply dict [concat [list set d] $keys [list value]]
    set value [apply dict [concat [list get $d] $keys]]
    apply dict [concat [list unset d] $keys]
    list $value [apply dict [concat [list exists $d] $keys]]
} {value 0}
test dict-arity {
    foreach script {{dict} {dict create key} {dict get} {dict exists} {dict exists {}} {dict keys} {dict keys {} *} {dict size} {dict size {} extra} {dict set} {dict set d key} {dict unset} {dict unset d}} {
        if [!= [catch $script message] 1] { error "accepted arguments: $script" }
        if [ne [string range $message 0 12] {wrong # args:}] { error $message }
    }
    set message
} {wrong # args: dict unset dictionaryVariable key ?key ...?}
test dict-unsupported { dict merge {} {} } {unknown dict operation: merge} 1
test dict-abbreviations {
    set d [dict c a 1]
    dict se d b 2
    dict un d a
    list [dict g $d b] [dict e $d a] [dict k $d] [dict si $d]
} {2 0 b 1}
test dict-ambiguous-prefixes {
    foreach operation {s u f i m r {}} {
        if [!= [catch {dict $operation {}}] 1] { error "accepted ambiguous operation: $operation" }
    }
    set operation
} {}
test dict-reload { source dict.tcl; dict get {a value} a } value
