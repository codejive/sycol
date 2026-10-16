# Working on Sycol

- Read [SPEC.md](SPEC.md) before changing behavior; it defines the language,
  SDK, compatibility boundaries, and extension contracts. See [README.md](README.md)
  for usage and test commands.
- Keep the core tiny. Prefer shared Tcl procedures in `lib/core.tcl` over new
  native commands. Preserve file-only execution, explicit `exec`, and no infix
  expression parser unless the requested change explicitly revises that design.
- Maintain equivalent behavior in `sycol.sh` and `sycol.ps1`, including results,
  completion codes, argument boundaries, and errors. Support Bash 3.2+ and
  Windows PowerShell 5.1+ as specified; avoid newer host-only features.
- For bug reports, reproduce the issue, check the intended behavior against the
  spec, add a failing regression test, and make the smallest coherent fix.
  Prefer shared Tcl tests; use host-specific probes only where necessary.
- For change requests, implement the requested scope, update the spec when the
  contract changes, and add meaningful tests. Update usage examples when needed.
  Clarify material ambiguity or compatibility breaks before dependent work;
  otherwise proceed using the existing design.
- Run `bash tests/run.sh` and `powershell` / `pwsh -NoProfile -File tests/run.ps1`
  on available supported hosts. Report what ran, failures, and unavailable
  runtimes; do not claim minimum-version or CI coverage passed without evidence.
  Documentation-only edits need a content/link check, not interpreter tests.
