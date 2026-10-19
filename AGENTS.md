# Working on Sycol

- Always use Conventional Commits when committing with Git. Write a descriptive
  subject explaining the main change and its purpose or resulting behavior.
  Add a short body only when it contributes useful change information, such as
  motivation, compatibility consequences, or a significant design tradeoff.
  Exclude procedural details: tests run, validation results, runtime versions
  used for testing, checks performed, and development steps belong in the work
  report, not the commit message. Describe changes to tests when those changes
  are themselves significant, but do not report executing them. Avoid vague
  labels, exhaustive lists of minor edits, and filler; every sentence should
  help a reader understand what changed or why.
- Read [SPEC.md](SPEC.md) before changing behavior; it defines the language,
  SDK, compatibility boundaries, and extension contracts. See [README.md](README.md)
  for a quick start and [docs/development.md](docs/development.md) for test commands.
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
- When adding or changing commands, update [docs/commands.md](docs/commands.md)
  and any affected guides in `docs/` in the same change. Document parameters,
  options, return values, errors, and examples as applicable.
- Run `bash tests/run.sh` and `powershell` / `pwsh -NoProfile -File tests/run.ps1`
  on available supported hosts. Report what ran, failures, and unavailable
  runtimes; do not claim minimum-version or CI coverage passed without evidence.
  Documentation-only edits need a content/link check, not interpreter tests.
