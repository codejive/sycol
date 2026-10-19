# Sycol documentation

Sycol runs a small Tcl-like language using Bash or PowerShell. Both backends
load the same SDK. All values are strings; external programs run explicitly
through `exec`.

| Guide | Contents |
| --- | --- |
| [Language basics](language.md) | Start here: commands, words, quoting, substitution, lists, variables, procedures, control flow, and errors |
| [Command reference](commands.md) | All application commands and subcommands, with parameters, results, limits, and examples |
| [Running scripts](running.md) | Runtime requirements, installation, launchers, script arguments, versions, and Windows quoting |
| [Testing and development](development.md) | Test drivers, writing tests, timing configuration, benchmarks, CI, and contribution rules |
| [Implementation](implementation.md) | Repository layout, evaluation, backend differences, library loading, native extensions, and embedding |
| [Tcl compatibility](tcl-compatibility.md) | Differences from full Tcl, unsupported facilities, and portability boundaries |

Read the language basics before the command reference. The command reference
describes a normal installation with its SDK loaded; implementation helpers
are documented separately in the implementation guide.

[SPEC.md](../SPEC.md) is the authoritative language and extension contract.
[RELEASE.md](../RELEASE.md) covers versioning, packaging, and publishing.
The [project README](../README.md) contains the introduction and quick run commands.
