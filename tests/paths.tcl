test path-join-basic { file join a {} b//c/ } a/b/c
test path-join-preserves-dot { file join a ./b .. } a/./b/..
test path-join-absolute { file join a /b c } /b/c
test path-join-home-reset { file join a ~/b } ~/b
test path-join-literal-home { file join a ./~literal } a/~literal
test path-join-home-slash { file join ~/ } ~/
test path-dirname-empty { file dirname {} } .
test path-dirname-relative { file dirname a//b/// } a
test path-dirname-root { file dirname / } /
test path-tail-root { file tail / } {}
test path-tail-trailing { file tail a//b/// } b
test path-tail-literal-home { file tail a/~literal } ./~literal
test path-tail-empty { file tail {} } {}
test path-extension { file extension a/b.tar.gz } .gz
test path-extension-dotfile { file extension .hidden } .hidden
test path-extension-parent-dot { file extension a.b/file } {}
test path-extension-trailing-slash { file extension a.txt/ } {}
test path-rootname { file rootname a/b.tar.gz } a/b.tar
test path-rootname-dotfile { file rootname .hidden } {}
test path-rootname-preserve-slashes { file rootname a//b/// } a//b///
test path-rootname-trailing-slash { file rootname a.txt/ } a.txt/
# Exercise both lexical platforms even on a single host.
test path-windows-drive { sy.path.join {a c:foo} 1 } c:foo
test path-windows-drive-join { sy.path.join {c: foo} 1 } c:foo
test path-windows-drive-root { sy.path.join {c:/ foo} 1 } c:/foo
test path-windows-dirname { sy.path.component dirname {C:\a\b.txt} 1 } C:/a
test path-windows-tail { sy.path.component tail {C:\a\b.txt} 1 } b.txt
test path-windows-extension { sy.path.extension extension {C:\a\b.txt} 1 } .txt
test path-windows-rootname { sy.path.extension rootname {C:\a\b.txt} 1 } {C:\a\b}
test path-windows-unc { sy.path.join {//server/share foo} 1 } //server/share/foo
test path-windows-unc-root { sy.path.component tail //server/share 1 } {}
test path-windows-partial-unc { sy.path.join {//server} 1 } /server
test path-unix-double-slash { sy.path.join {//server/share foo} 0 } /server/share/foo
test path-unix-colon { sy.path.join {a c:foo} 0 } a/c:foo
test path-unix-backslash { sy.path.component tail {a\b.txt} 0 } {a\b.txt}
test path-arity {
    list [catch {file join}] [catch {file dirname}] [catch {file tail a b}] [catch {file extension}] [catch {file rootname a b}]
} {1 1 1 1 1}
