# Working on Sycol

- Always use Conventional Commits when committing with Git. Describe the change
  clearly without making commit messages overly verbose.
- Read [SPEC.md](SPEC.md) before changing behavior; it defines the language,
  SDK, compatibility boundaries, and extension contracts. See [README.md](README.md)
  for usage and test commands.
- Keep the core tiny. Prefer shared Tcl procedures in `.sycol/sdk/` over new
  native commands. Preserve file-only execution, explicit `exec`, and no infix
  expression parser unless the requested change explicitly revises that design.
- Before adding a command or feature, check how full Tcl provides the same or
  similar functionality, including its name, syntax, options, and behavior.
  If the additional cost of following Tcl is negligible, always use Tcl's way.
  Assess cost against Sycol's small core, shared SDK, host parity, dependencies,
  and supported runtime versions. If alignment has a non-negligible cost,
  explain that cost and present a low-cost alternative that retains Tcl's naming,
  syntax, and behavior where possible before implementing the alternative.
  If a proposed feature already exists in Tcl under a different name or with
  different but similar characteristics, tell the user and propose adjusting
  the suggestion to align with Tcl, subject to the same cost considerations.
- Maintain equivalent behavior in `.sycol/bin/sycol` and `.sycol/bin/sycol.ps1`,
  including results, completion codes, argument boundaries, and errors. Support Bash 3.2+ and
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
