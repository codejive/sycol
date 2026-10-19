# Releasing Sycol

Releases are started explicitly from GitHub Actions. Pushes and tags never
trigger a release. The process uses JReleaser's generic `archive` assembler
and GitHub releaser; Sycol does not need Maven, Gradle, or Java at runtime.
The workflow installs Java only to run JReleaser 1.26.0.

## Create a release

1. Merge the changes to `main`.
2. Open [Actions → Release](https://github.com/codejive/sycol/actions/workflows/release.yml).
3. Select **Run workflow**, choose **main**, and enter an unused version such
   as `0.2.0`. Use `MAJOR.MINOR.PATCH`, without `v`, leading zeroes, prerelease
   suffixes, or build metadata. The first release may use the checked-in `0.1.0`.
4. Start the workflow. It validates the input and runs the complete test matrix
   with that version: Linux and macOS Bash, Windows PowerShell 5.1, and
   PowerShell 7 on Windows and Linux.
5. After the tests pass, it commits `.sycol/VERSION` with
   `chore(release): VERSION` if the file changed, assembles and checks the
   distributions, smoke tests the packaged interpreters, and dry-runs JReleaser.
   It then pushes the release commit to `main` and publishes tag `vVERSION`
   and the GitHub release at that commit.

The workflow uses the built-in `GITHUB_TOKEN` with `contents: write`; no
additional secrets, Maven Central credentials, signing keys, or environment
approval are required. Repository rules must permit the workflow to push the
version commit to `main` and create release tags. It does not bypass branch
protection or force-push. If `main` advances while the tests run, publication
fails before the version push; start a new run from the updated branch.

Releases run one at a time. Existing tags and releases are never overwritten.
There is no automatic next-development-version bump: `.sycol/VERSION` remains
at the last released version until the next explicitly requested release.

## Downloads

Each release contains:

- `sycol-VERSION.zip`
- `sycol-VERSION.tgz`
- `checksums_sha256.txt`

Both archives contain a `sycol-VERSION/` directory with the two root wrappers,
the complete `.sycol/` runtime and SDK, license, README, release guide,
specification, `docs/` guides, and examples. The same archive works on every
supported platform; add its `.sycol/bin/` directory to `PATH` or copy the runtime
and wrappers into your project as described in the README. TGZ preserves the
Bash launchers' executable bits; ZIP also records them, though extraction tools
may ignore those bits.

Release notes are generated from Conventional Commits since the previous tag.
The runtime version, tag, archive names, and JReleaser project version all derive
from `.sycol/VERSION` after the requested version has been written there.

## Local verification

With Java and [JReleaser 1.26.0](https://jreleaser.org/guide/latest/install.html)
installed, run from the repository root on Linux or macOS:

```sh
export JRELEASER_PROJECT_VERSION="$(cat .sycol/VERSION)"
# A placeholder is sufficient for offline configuration and dry-run checks.
export JRELEASER_GITHUB_TOKEN=local-validation
jreleaser assemble
bash tests/release.sh "$JRELEASER_PROJECT_VERSION"
jreleaser full-release --dry-run
```

The archive check uses Bash, `tar`, `unzip`, and standard Unix utilities.
Run it on Linux or macOS so extracted Unix executable permissions can be checked.
On Windows, run the complete Linux sequence in WSL for archive verification.
PowerShell can separately check JReleaser's assembly and dry run:

```powershell
$env:JRELEASER_PROJECT_VERSION = (Get-Content .sycol/VERSION -Raw).Trim()
$env:JRELEASER_GITHUB_TOKEN = 'local-validation'
jreleaser assemble
jreleaser full-release --dry-run
```

Archive verification checks file contents, the exact release version, and Unix
executable permissions. The publishing workflow assembles and checks on Ubuntu.
Generated output is ignored under `out/`. A dry run does not push commits,
create tags, or publish releases.

## Failed runs

The workflow saves JReleaser's trace and output properties as the
`jreleaser-release-output` Actions artifact. If a failure happens after the
version commit was pushed but before a tag was created, start a new run from
the current `main` with the same version. If a tag or release already exists,
inspect that release and the diagnostics before taking any manual recovery
action; rerunning cannot overwrite it. Do not use **Re-run jobs** after `main`
has changed, since it uses the old source commit.

References: [generic archives](https://jreleaser.org/guide/latest/reference/assemble/archive.html),
[GitHub releases](https://jreleaser.org/guide/latest/reference/release/github.html),
and the [java-jpm workflow](https://github.com/codejive/java-jpm/blob/main/.github/workflows/release.yml)
that inspired this process.
