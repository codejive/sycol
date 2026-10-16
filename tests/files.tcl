# Run by all.tcl, with a fresh directory prepared by each host driver.
set fsroot "[lindex $::argv 0]/filesystem"
test file-list-empty { file list "$::fsroot/empty" } {}
test file-list-names {
    set names [file list "$::fsroot/source"]
    set count 0
    foreach entryName $names {
        if [or {eq $entryName {.hidden}} {or {eq $entryName {a ; [literal].txt}} {eq $entryName nested}}] { incr count }
    }
    list [llength $names] $count
} {3 3}
test file-list-default { set old [pwd]; cd "$::fsroot/empty"; set names [file list]; cd $old; set names } {}
test file-type-file { file type "$::fsroot/source/a ; \[literal\].txt" } file
test file-type-directory { file type "$::fsroot/source" } directory
test file-type-home { file type ~ } directory
test file-type-file-trailing-separator { file type "$::fsroot/source/.hidden/" } file
test file-type-missing { file type "$::fsroot/missing" } "cannot stat path: $::fsroot/missing" 1
test file-list-missing { file list "$::fsroot/missing" } "cannot list directory: $::fsroot/missing" 1
test file-list-file { catch {file list "$::fsroot/source/.hidden"} } 1
test file-copy-literal {
    file copy "$::fsroot/source/a ; \[literal\].txt" "$::fsroot/copy.txt"
    readfile "$::fsroot/copy.txt"
} payload
test file-copy-existing { file copy "$::fsroot/source/.hidden" "$::fsroot/copy.txt" } "copy target exists: $::fsroot/copy.txt" 1
test file-copy-force { file copy -force "$::fsroot/source/.hidden" "$::fsroot/copy.txt"; readfile "$::fsroot/copy.txt" } hidden
test file-copy-force-readonly { file copy -force "$::fsroot/source/.hidden" "$::fsroot/readonly-target"; readfile "$::fsroot/readonly-target" } hidden
test file-delete-readonly { file delete "$::fsroot/readonly-file" } {}
test file-copy-self { file copy -force "$::fsroot/copy.txt" "$::fsroot/copy.txt" } {cannot copy a file onto itself} 1
test file-copy-recursive {
    file copy "$::fsroot/source" "$::fsroot/copydir"
    list [readfile "$::fsroot/copydir/nested/child"] [readfile "$::fsroot/copydir/.hidden"]
} {child hidden}
test file-copy-attributes { file copy "$::fsroot/source/.hidden" "$::fsroot/attributes-copy"; file copy "$::fsroot/source" "$::fsroot/attributes-dir" } {}
test file-copy-into-directory {
    file copy "$::fsroot/source/.hidden" "$::fsroot/copydir"
} "copy target exists: $fsroot/copydir/.hidden" 1
test file-copy-multiple {
    file copy "$::fsroot/source/.hidden" "$::fsroot/source/nested/child" "$::fsroot/empty"
    list [readfile "$::fsroot/empty/.hidden"] [readfile "$::fsroot/empty/child"]
} {hidden child}
test file-copy-directory-into-directory {
    file copy "$::fsroot/source/nested" "$::fsroot/empty"
    readfile "$::fsroot/empty/nested/child"
} child
test file-copy-directory-no-merge { catch {file copy -force "$::fsroot/source/nested" "$::fsroot/empty"} } 1
test file-copy-multiple-needs-directory { catch {file copy "$::fsroot/source/.hidden" "$::fsroot/source/nested/child" "$::fsroot/new-target"} } 1
test file-copy-missing-parent { catch {file copy "$::fsroot/source" "$::fsroot/not-present/target"} } 1
test file-copy-missing-source { file copy "$::fsroot/missing" "$::fsroot/unused" } "cannot copy path: $fsroot/missing" 1
test file-copy-descendant { catch {file copy "$::fsroot/source" "$::fsroot/source/nested/copy"} } 1
test file-copy-stops-on-error {
    writefile "$::fsroot/copy-last" last
    set code [catch {file copy "$::fsroot/source/nested/child" "$::fsroot/missing" "$::fsroot/copy-last" "$::fsroot/copydir"}]
    list $code [readfile "$::fsroot/copydir/child"] [catch {file type "$::fsroot/copydir/copy-last"}]
} {1 child 1}
test file-delete-nonempty { catch {file delete "$::fsroot/copydir"} } 1
test file-delete-recursive { file delete -force "$::fsroot/copydir"; catch {file type "$::fsroot/copydir"} } 1
test file-delete-file { file delete "$::fsroot/copy.txt"; catch {file type "$::fsroot/copy.txt"} } 1
test file-delete-multiple { file delete -force "$::fsroot/empty" "$::fsroot/missing"; catch {file type "$::fsroot/empty"} } 1
test file-delete-empty { file copy "$::fsroot/source/nested" "$::fsroot/empty-dir"; file delete "$::fsroot/empty-dir/child"; file delete "$::fsroot/empty-dir" } {}
test file-delete-missing { file delete "$::fsroot/missing" } {}
test file-delete-missing-force { file delete -force "$::fsroot/missing" } {}
test file-delete-no-paths { file delete; file delete -force; file delete --; file delete {} } {}
test file-delete-stops-on-error {
    writefile "$::fsroot/delete-first" first
    writefile "$::fsroot/delete-last" last
    set code [catch {file delete "$::fsroot/delete-first" "$::fsroot/source" "$::fsroot/delete-last"}]
    list $code [catch {file type "$::fsroot/delete-first"}] [readfile "$::fsroot/delete-last"]
} {1 1 last}
test file-abbreviations { file cop "$::fsroot/source/.hidden" "$::fsroot/abbreviation"; set kind [file ty "$::fsroot/abbreviation"]; file del "$::fsroot/abbreviation"; set kind } file

test file-abbreviations-dispatch {
    file mk "$::fsroot/abbreviations"
    file co "$::fsroot/source/.hidden" "$::fsroot/abbreviations/a ; literal.txt"
    file ren "$::fsroot/abbreviations/a ; literal.txt" "$::fsroot/abbreviations/b.txt"
    set path "$::fsroot/abbreviations/b.txt"
    set joined [file j dir b.txt]
    set result [list [file ty $path] [file exi $path] [file isf $path] [file isd "$::fsroot/abbreviations"] [file di $joined] [file ta $joined] [file ext $joined] [file ro $joined] [file si $path] [file p relative]]
    file de -force "$::fsroot/abbreviations"
    set result
} {file 1 1 1 dir b.txt .txt dir/b 6 relative}

test file-abbreviations-invalid {
    list [catch {file c a b}] [catch {file d a}] [catch {file t a}] [catch {file join-extra a b}] [catch {file exi}]
} {1 1 1 1 1}
test file-options {
    set count 0
    foreach script {{file} {file bogus} {file list a b} {file type} {file copy -recursive a b} {file copy -attributes a b} {file copy a} {file delete -attributes a} {file copy -bogus a b} {file delete -recursive a} {file copy {} a}} {
        if [!= [catch $script] 1] { error "expected file error: $script" }
        incr count
    }
    set count
} 11
test file-leading-dash { set old [pwd]; cd $::fsroot; writefile -literal dash; file copy -- -literal -copy; file delete -- -literal; set result [readfile -copy]; file delete -- -copy; cd $old; set result } dash
test exit-invalid {
    list [catch {exit -1}] [catch {exit 256}] [catch {exit abc}] [catch {exit 1 2}]
} {1 1 1 1}
test file-mkdir-parents { file mkdir "$::fsroot/made/a/b" "$::fsroot/made/c"; file mkdir "$::fsroot/made/a"; file isdirectory "$::fsroot/made/a/b" } 1
test file-mkdir-no-args { file mkdir } {}
test file-mkdir-file-error { catch {file mkdir "$::fsroot/source/.hidden"} } 1
test file-mkdir-stops-on-error {
    catch {file mkdir "$::fsroot/made-first" "$::fsroot/source/.hidden" "$::fsroot/made-last"}
    list [file exists "$::fsroot/made-first"] [file exists "$::fsroot/made-last"]
} {1 0}
test file-predicates {
    list [file exists "$::fsroot/missing"] [file exists {}] [file exists "$::fsroot/source"] [file isfile "$::fsroot/source/.hidden"] [file isfile "$::fsroot/source"] [file isdirectory "$::fsroot/source"] [file isdirectory "$::fsroot/source/.hidden"]
} {0 0 1 1 0 1 0}
test file-predicate-home-unknown { list [file exists ~sycol_no_such_user_019283] [file isfile ~sycol_no_such_user_019283] [file isdirectory ~sycol_no_such_user_019283] } {0 0 0}
test file-size { file size "$::fsroot/source/.hidden" } 6
test file-size-bytes { writefile "$::fsroot/utf8-size" {é😀}; file size "$::fsroot/utf8-size" } 6
test file-size-missing { catch {file size "$::fsroot/missing"} } 1
test file-rename-file {
    writefile "$::fsroot/move-first" payload
    file rename "$::fsroot/move-first" "$::fsroot/move-second"
    list [file exists "$::fsroot/move-first"] [readfile "$::fsroot/move-second"]
} {0 payload}
test file-rename-existing { catch {file rename "$::fsroot/move-second" "$::fsroot/source/.hidden"} } 1
test file-rename-force {
    file rename -force "$::fsroot/move-second" "$::fsroot/readonly-target"
    list [file exists "$::fsroot/move-second"] [readfile "$::fsroot/readonly-target"]
} {0 payload}
test file-rename-same-file { file rename -force "$::fsroot/readonly-target" "$::fsroot/readonly-target" } {}
test file-rename-multiple {
    writefile "$::fsroot/move-a" a
    writefile "$::fsroot/move-b" b
    file rename "$::fsroot/move-a" "$::fsroot/move-b" "$::fsroot/made"
    list [readfile "$::fsroot/made/move-a"] [readfile "$::fsroot/made/move-b"] [file exists "$::fsroot/move-a"]
} {a b 0}
test file-rename-directory {
    file mkdir "$::fsroot/move-dir/a"
    file rename "$::fsroot/move-dir" "$::fsroot/moved-dir"
    list [file isdirectory "$::fsroot/moved-dir/a"] [file exists "$::fsroot/move-dir"]
} {1 0}
test file-rename-empty-directory-replacement {
    file mkdir "$::fsroot/parent/moved-dir"
    file rename -force "$::fsroot/moved-dir" "$::fsroot/parent"
    file isdirectory "$::fsroot/parent/moved-dir/a"
} 1
test file-rename-nonempty-directory { file mkdir "$::fsroot/parent/moved-dir/a/existing"; catch {file rename -force "$::fsroot/made/a" "$::fsroot/parent/moved-dir"} } 1
test file-rename-descendant { catch {file rename "$::fsroot/parent" "$::fsroot/parent/inside"} } 1
test file-rename-stops-on-error {
    writefile "$::fsroot/rename-first" first
    writefile "$::fsroot/rename-last" last
    catch {file rename "$::fsroot/rename-first" "$::fsroot/missing" "$::fsroot/rename-last" "$::fsroot/made"}
    list [file exists "$::fsroot/rename-first"] [file exists "$::fsroot/made/rename-first"] [file exists "$::fsroot/rename-last"]
} {0 1 1}
test file-new-arity { list [catch {file exists}] [catch {file isfile a b}] [catch {file isdirectory}] [catch {file size a b}] [catch {file mkdir {}}] [catch {file rename a}] [catch {file rename -bogus a b}] } {1 1 1 1 1 1 1}
# Drivers create links only when the host permits them.
if [== [lindex $::argv 2] 1] {
    test file-predicates-links { list [file exists "$::fsroot/link"] [file isdirectory "$::fsroot/link"] [file isfile "$::fsroot/link"] [file exists "$::fsroot/dangling"] [file isfile "$::fsroot/file-link"] [file isdirectory "$::fsroot/file-link"] } {1 1 0 0 1 0}
    test file-size-link { file size "$::fsroot/file-link" } 6
    test file-rename-link { file rename "$::fsroot/file-link" "$::fsroot/moved-link"; list [file type "$::fsroot/moved-link"] [readfile "$::fsroot/source/.hidden"] } {link hidden}
    test file-type-link { file type "$::fsroot/link" } link
    test file-type-dangling { file type "$::fsroot/dangling" } link
    test file-type-link-trailing-separator { file type "$::fsroot/link/" } link
    test file-copy-link { file copy "$::fsroot/link" "$::fsroot/link-copy"; file type "$::fsroot/link-copy" } link
    test file-copy-force-link { file copy -force "$::fsroot/source/.hidden" "$::fsroot/dangling"; file type "$::fsroot/dangling" } file
    test file-delete-link { file delete -force "$::fsroot/link/"; readfile "$::fsroot/source/.hidden" } hidden
    test file-delete-dangling { file delete "$::fsroot/dangling" } {}
}
