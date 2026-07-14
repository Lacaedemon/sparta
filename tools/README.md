# tools/

Developer tooling for Sparta — small helpers that speed up the edit → verify
loop. None of it ships in the game build.

## `check.sh` — run CI's checks locally

A single entry point that reproduces the **gating** checks from
`.github/workflows/` on your machine, so you can get a CI-equivalent pass (or
failure) without pushing and waiting on the runners.

```sh
tools/check.sh                 # default set: validate, test, chars, comments
tools/check.sh test chars      # only the named checks, in order
tools/check.sh all             # every check (adds links if lychee is installed)
tools/check.sh --list          # list the available checks
tools/check.sh --help          # full usage
```

| Check | What it does | Mirrors |
|---|---|---|
| `validate` | `godot --headless --import` loads the whole project (autoloads, `class_name` globals, cross-script refs) and fails on any script/parse error. | `godot-ci.yml` |
| `test` | Runs the GUT unit suite headlessly (`-gexit`). | `godot-ci.yml` |
| `chars` | Flags curly quotes and en/em dashes in the Quarto docs (`*.qmd`, `*.R`), which are kept plain-ASCII. | `check-non-standard-chars.yml` |
| `comments` | Flags issue/PR-number citations (`#123`) added by this diff's GDScript (`*.gd`) comment lines — CLAUDE.md's "no issue-number references" rule (`TODO(#N):`/`FIXME(#N):` excepted). Diff-scoped against `origin/main` (or `SPARTA_CHECK_COMMENTS_BASE`), not a whole-repo scan, so pre-existing citations elsewhere in the tree don't fail the check. | `check-comment-citations.yml` |
| `coverage` | Runs the GUT suite instrumented for line coverage and writes `coverage/lcov.info` (git-ignored). Slower than `test` (instrumentation overhead) and coverage numbers never gate a PR on their own, so it's **not** in the default set. | `test-coverage.yml` |
| `patch_coverage` | Local approximation of Codecov's `codecov/patch` check: regenerates `coverage/lcov.info` fresh (runs `coverage` first), then reports what fraction of THIS diff's added `scripts/*.gd` lines are covered — per-file breakdown plus the exact missing line numbers. Diff-scoped against `origin/main` (or `SPARTA_CHECK_PATCH_COVERAGE_BASE`), same as `comments`. Run it before pushing a `scripts/` change to catch a `codecov/patch` shortfall locally instead of after a CI round trip — see "Checking patch coverage before you push" below. **Not** in the default set (inherits `coverage`'s slowness). | `codecov/patch` (GitHub check, driven by `test-coverage.yml`'s upload) |
| `links` | Markdown link-check via [lychee](https://github.com/lycheeverse/lychee), if installed. Needs network, so it's **not** in the default set. | `check-links.yml` |

Exit status is non-zero if any selected check fails, so it drops straight into a
pre-push hook or a `&&` chain:

```sh
tools/check.sh && git push
```

### Requirements

- **Bash 3.2+** — works with the system Bash that ships on macOS (no Homebrew
  Bash needed); uses only POSIX/BSD-compatible tool flags.
- **Godot 4.7 (Standard build)** on `PATH`, or point `GODOT_BIN` at it
  (e.g. `/Applications/Godot.app/Contents/MacOS/Godot` on macOS). See the README's
  "Running Godot headlessly" snippet for a Linux download.
- **GUT** is vendored on demand into `addons/gut/` the first time `validate`/`test`
  runs (it isn't committed); no manual install needed.
- **lychee** only for the optional `links` check.
- **`comments`** needs a resolvable diff base (`origin/main`, a local `main`, or
  `SPARTA_CHECK_COMMENTS_BASE`) to find the lines this diff adds — see below. A
  shallow clone with no such ref available skips the check rather than falling
  back to a whole-tree scan.

### Environment variables

| Var | Default | Purpose |
|---|---|---|
| `GODOT_BIN` | `godot` | Godot 4.7 binary to invoke. |
| `GUT_VERSION` | `v9.7.0` | GUT release to vendor when `addons/gut/` is missing. Keep in sync with `godot-ci.yml` and `test/README.md`. |
| `NO_COLOR` | _(unset)_ | Set to disable coloured output. |
| `SPARTA_CHECK_VALIDATE_TIMEOUT` | `900` | Hard timeout (s) for the `validate` Godot run. |
| `SPARTA_CHECK_TEST_TIMEOUT` | `1800` | Hard timeout (s) for the `test` Godot run. |
| `SPARTA_CHECK_COVERAGE_TIMEOUT` | `2700` | Hard timeout (s) for the `coverage` Godot run. |
| `SPARTA_CHECK_COMMENTS_BASE` | _(unset)_ | Commit-ish the `comments` check diffs `HEAD` against to find new lines to scan. Falls back to `origin/main` then a local `main`; CI sets this per-event (PR base SHA, or the push event's `before`) — see `check-comment-citations.yml`. |
| `SPARTA_CHECK_PATCH_COVERAGE_BASE` | _(unset)_ | Same, for the `patch_coverage` check's diff base. |
| `SPARTA_GODOT_PREFLIGHT_LIMIT` | `5` | Warn when more Godot processes than this are already running before the checks start. |

## Checking patch coverage before you push

`codecov/patch` (Codecov's per-diff coverage gate, uploaded from the `coverage`
CI job) only reports after a push — a ~15–20 min round trip to discover a
`scripts/` change fell short. Run it locally first:

```sh
tools/check.sh patch_coverage
```

This regenerates `coverage/lcov.info` fresh (so the numbers reflect your
current working tree, not a stale report from a previous diff), diffs against
`origin/main` to find this diff's added `scripts/*.gd` lines, and reports a
per-file breakdown plus the exact missing line numbers — a local
approximation of what Codecov will report, verified to match its output
directly (same percentage, same missing lines) on a real PR's diff. Like
`coverage`, patch coverage never gates the check itself (it always reports
`PASS` — reading the number and deciding what to do about it is on you, same
as Codecov's own check never blocking a merge on its own).

If a diff comes up short, the fix is either genuine new test coverage for the
newly-added lines, or — when the code is structurally hard to cover (a scene
transition, an OS/input-dependent path) — accepting the residual and saying
so explicitly in the PR, the same way `_on_restart`/`_on_quit_to_menu`-style
handlers are deliberately left untested elsewhere in this codebase (see
`test/unit/test_main_menu.gd`'s own note on why). Padding coverage with tests
that don't guard real behavior is worse than a documented gap.

## Orphaned Godot processes: prevention and cleanup

Headless Godot runs survive their calling shell on Windows (no process-tree
kill), so a hung run whose shell died — a harness command timeout, a session
end — lives forever as an orphan and starves every later run on the machine.
Three layers keep that from piling up:

1. **Hard timeouts at the source.** Every Godot invocation in the repo's shell
   scripts (`check.sh`, `demo/dump-state.sh`, `demo/capture-frames.sh`,
   `benchmark/run-benchmark.sh`, `../website/tools/record-demos.sh`) runs under
   coreutils `timeout` via the shared `lib/run-bounded.sh` helper, so a hung
   Godot is killed — not just the calling shell. Budgets are generous
   hang-detectors, overridable per script (see each script's header). On stock
   macOS (no coreutils), the scripts run unbounded with a one-time warning;
   `brew install coreutils` restores the net.
2. **In-engine safety nets.** Each runner scene quits itself once a wall-clock
   budget expires, even when the invoker forgot `--quit-after`:
   `demo/RunWatchdog.gd` (attached by `DemoRunner` and `DemoInputRecorder`;
   default 900 s, override via `SPARTA_RUN_TIMEOUT_SEC`) and
   `benchmark/BenchmarkRunner.gd`'s own timeout + stall guard.
3. **Pre-flight warning.** `check.sh` warns when more than a handful of Godot
   processes are already running — the early signal of a leak building up (and
   the likely explanation for slow or flaky local runs).

### `kill-orphan-godot.ps1` / `kill-orphan-godot.sh` — sweep script

Lists Godot processes whose command line matches a **non-interactive run
signature** (headless import, GUT suite, demo/benchmark recording — an
interactive editor session never matches, so it is never touched) and
classifies each:

- **Orphaned** — the parent process is gone, so nothing is consuming the
  output. Safe to kill by construction: killing Godot cannot lose git state.
- **Overdue** — older than the age ceiling (default 2 h; no legitimate repo
  run takes that long).
- **Child** — a matched process whose parent is itself being killed by this
  sweep (the Windows console build is a launcher exe that spawns the real
  Godot as a child; killing only the launcher would leave the real process
  behind).
- **Live** — everything else; never touched.

**Dry-run by default** — it only prints what it would kill:

```sh
tools/kill-orphan-godot.sh                    # dry run (any platform)
tools/kill-orphan-godot.sh --force            # actually kill
tools/kill-orphan-godot.sh --max-age-hours 4  # relax the age ceiling
tools/kill-orphan-godot.sh --pid 1234,5678    # restrict to specific PIDs
```

On Windows the `.sh` delegates to the PowerShell twin (the MSYS `ps` cannot
see native processes), which can also be run directly:

```powershell
powershell -NoProfile -File tools/kill-orphan-godot.ps1          # dry run
powershell -NoProfile -File tools/kill-orphan-godot.ps1 -Force   # kill
```

Optionally (user-machine config, not repo policy), register the sweep as a
scheduled task every 30–60 min so a leak never builds up unattended.

## `demo/`

The headless demo recorder used by the demo-video pipeline — see
[`demos/README.md`](../demos/README.md).

## `ci/`

Small helpers invoked by GitHub Actions workflows.

- `upsert-pr-comment.sh <repo> <pr> <marker> <body> [label]` — PATCH the existing
  marker-tagged PR comment if one exists, else POST a new one. Used by
  `.github/workflows/demo-video.yml` so its recorded-clip and "no clip applies"
  paths share one comment-upsert implementation. Needs `gh` authenticated via
  `GH_TOKEN`.
