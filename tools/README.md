# tools/

Developer tooling for Sparta -- small helpers that speed up the edit → verify
loop. None of it ships in the game build.

## `check.sh` -- run CI's checks locally

A single entry point that reproduces the **gating** checks from
`.github/workflows/` on your machine, so you can get a CI-equivalent pass (or
failure) without pushing and waiting on the runners.

```sh
tools/check.sh                 # default set: validate, test, chars, comments, units, file_length, shell_tests, markdown, own_links
tools/check.sh test chars      # only the named checks, in order
tools/check.sh all             # every check (adds lint/links if gdlint/lychee are installed)
tools/check.sh --list          # list the available checks
tools/check.sh --help          # full usage
```

| Check | What it does | Mirrors |
|---|---|---|
| `validate` | `godot --headless --import` loads the whole project (autoloads, `class_name` globals, cross-script refs) and fails on any script/parse error, then a compile sweep (`tools/ci/compile_all_scripts.gd`) force-loads every `.gd` -- catching parse errors in scripts nothing references at import time, which the import pass alone misses. | `godot-ci.yml` |
| `test` | Runs the GUT unit suite headlessly (`-gexit`). Self-sufficient: imports the project first if it hasn't been imported yet this invocation (reusing `validate`'s import when both run together), so `tools/check.sh test` alone in a fresh checkout doesn't need `validate` to run first. | `godot-ci.yml` |
| `chars` | Flags curly quotes (U+2018, U+2019, U+201C, U+201D), en/em dashes (U+2013, U+2014), and the multiplication sign (U+00D7) in docs (`*.qmd`, `*.R`, `*.md`; whole-tree) and in added lines in source files (`*.gd`, `*.sh`; diff-scoped against `origin/main` so pre-existing code occurrences are grandfathered). Configured in `tools/ci/banned_chars.json`. Remedy differs by file type: `x` or `*` in `.R` / code, `&times;` in `.qmd` prose (a `\uXXXX` escape is rendered literally by Pandoc, so it is not a substitute there). | `check-non-standard-chars.yml` & `check-comment-citations.yml` |
| `comments` | Flags issue/PR-number citations (`#123`) added by this diff's GDScript (`*.gd`) comment lines -- CLAUDE.md's "no issue-number references" rule (`TODO(#N):`/`FIXME(#N):` excepted). Diff-scoped against `origin/main` (or `SPARTA_CHECK_COMMENTS_BASE`), not a whole-repo scan, so pre-existing citations elsewhere in the tree don't fail the check. | `check-comment-citations.yml` |
| `file_length` | Caps NEW `scripts/*.gd` files (added by this diff, not existing ones) at 100 lines (override with `SPARTA_CHECK_MAX_NEW_FILE_LINES`) -- a modularity budget for genuinely new files, introduced by this check itself (not an existing CLAUDE.md rule). Diff-scoped like `comments`, sharing its base resolution: a whole-tree gate would fail on the 167 of 274 tracked `*.gd` files that already exceed 100 lines. Scoped to `scripts/`, not `test/` (this repo's test files deliberately group many test functions per file). | `check-comment-citations.yml` |
| `shell_tests` | Runs every `tools/lib/tests/test-*.sh` with `bash` and fails if any exits non-zero (skips with an info line if the directory is empty). Each test file is self-contained -- own fixtures, own assertions -- so this driver only aggregates their exit codes. No Godot needed, so it's fast and in the default set. | `check-comment-citations.yml` |
| `markdown` | The **blocking** Markdown checks CI runs from Morrison-Lab/gha: lint-markdown's list-item merge splices on lines added since `origin/main` (diff-scoped, committed changes only, as in CI) and blank lines splitting a GFM table (whole tracked tree, as in CI; markdownlint itself is advisory here), plus check-new-line-breaks' missing semantic line breaks on lines added since the merge-base, with that workflow's default inputs (on a dirty tree it follows the checker's own scope and includes uncommitted edits to tracked files, where the splice check reads only `HEAD`). Runs gha's own Node and Python scripts, fetched on first use into `.check-cache/` (git-ignored) at the commit `SPARTA_CHECK_GHA_REF` (default `v2`, both workflows' pin) resolves to, so a moved tag refetches; offline it reuses the newest complete cached copy, while a ref gha does not have is an error. In the default set, but skips unless the diff touches `*.md`; `tools/check.sh markdown` runs it regardless. Only the table check needs no diff base, so with none an explicit run checks just tables and reports `skip`. The Node checks skip when `node` is missing and the line-break check when `python3` is. On Windows the line-break check refuses to run when a changed file's path reaches 260 characters (`SPARTA_CHECK_WINDOWS_MAX_PATH`), since the checker would skip that file unread and pass. A check that could not run, for want of `node`, `python3`, or a diff base, reports `skip`, not `pass`. | `lint-markdown.yml`, `check-new-line-breaks.yml` |
| `own_links` | Checks the repo's own `https://github.com/Lacaedemon/sparta/{blob,tree}/main/<path>` links in tracked `*.md`/`*.qmd`/`*.html` against `git ls-files` (`tools/ci/check-own-blob-links.sh`), ignoring `#fragment`/`?query` and links inside code spans. `lychee.toml` excludes these URLs because github.com 503s the CI runner intermittently (#1796), so this keeps a deleted or renamed link target failing. Offline, fast, in the default set. | `check-own-blob-links.yml` |
| `coverage` | Runs the GUT suite instrumented for line coverage and writes `coverage/lcov.info` (git-ignored). Slower than `test` (instrumentation overhead), so it's **not** in the default set. The overall number never gates a PR; the CI job gates only on `patch_coverage` below. | `test-coverage.yml` |
| `patch_coverage` | Local approximation of Codecov's `codecov/patch` check: regenerates `coverage/lcov.info` fresh (runs `coverage` first), then reports what fraction of THIS diff's added `scripts/*.gd` lines are covered -- per-file breakdown plus the exact missing line numbers -- and **fails when that fraction is below the effective target** (auto: the project-wide total from the regenerated report, mirroring `codecov/patch`'s `target: auto`; override with `SPARTA_CHECK_PATCH_COVERAGE_TARGET`). Diff-scoped against `origin/main` (or `SPARTA_CHECK_PATCH_COVERAGE_BASE`), same as `comments`. Run it before pushing a `scripts/` change to catch a `codecov/patch` shortfall locally instead of after a CI round trip -- see "Checking patch coverage before you push" below. **Not** in the default set (inherits `coverage`'s slowness). | `test-coverage.yml`'s `Coverage` job runs this same `tools/check.sh coverage patch_coverage` and fails on it; Codecov's `codecov/patch` check reports the same metric when Codecov is reachable |
| `lint` | GDScript style lint via [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit)'s `gdlint`, if installed (`pip install gdtoolkit==4.5.0`). Config in `.gdlintrc` at the project root, tuned to this repo's actual conventions -- see that file's own header for the disabled-rule rationale. Runs over every tracked `*.gd` file (not diff-scoped: the baseline is clean, so any finding is unambiguously new), skipping `addons/`. **Not** in the default set (an external tool most local setups won't have installed by default). | `check-gdlint.yml` |
| `links` | Markdown link-check via [lychee](https://github.com/lycheeverse/lychee), if installed. Needs network, so it's **not** in the default set. | `check-links.yml` |
| `demo_defects` | Deterministic defect scan of THIS diff's changed demo declaration files. A changed `demos/inputs/*.json` script gets a FULL state dump run through the DemoDefects analyzer (the formation defect metrics plus the script's own declared `expect` assertions). A changed `demos/*.defects.json` replay sidecar (see `demos/README.md`'s "Sidecar declarations" section) gets its `expect`/`defect_exemptions` shape validated -- a shape failure fails the check the same way a malformed input script does -- and, when this tree carries `tools/demo/DemoStateSink.gd`, its paired replay (`demos/<name>.json`) additionally gets the same dump-and-analyze pass; on a tree without `DemoStateSink.gd` the sidecar is shape-validated locally only, and the analyzer pass for it runs in CI's sweep instead. Drives a real headless battle per changed script/replay, so **not** in the default set. | `demo-video.yml` |

Exit status is non-zero if any selected check fails, so it drops straight into a
pre-push hook or a `&&` chain:

```sh
tools/check.sh && git push
```

### Requirements

- **Bash 3.2+** -- works with the system Bash that ships on macOS (no Homebrew
  Bash needed); uses only POSIX/BSD-compatible tool flags.
- **Godot 4.7 (Standard build)** on `PATH`, or point `GODOT_BIN` at it
  (e.g. `/Applications/Godot.app/Contents/MacOS/Godot` on macOS). See the README's
  "Running Godot headlessly" snippet for a Linux download. Every Godot-driving
  check compares that binary's `major.minor` against the version `project.godot`
  targets (`config/features`) and refuses to run on a mismatch -- see
  "A Godot version mismatch fails fast" below.
- **GUT** is vendored on demand into `addons/gut/` the first time `validate`/`test`
  runs (it isn't committed); no manual install needed.
- **ai-config** for Gemini/AGY is bootstrapped on demand into `.ai-config/` via
  `tools/bootstrap-ai-config.sh` (pinned by `.ai-config-ref`, gitignored); run it
  once per fresh clone before a Gemini session. Claude uses the plugin marketplace
  instead (`.claude/settings.json`).
- **lychee** only for the optional `links` check.
- **gdtoolkit** (`pip install gdtoolkit==4.5.0`) only for the optional `lint` check.
- **`comments`** needs a resolvable diff base (`origin/main`, a local `main`, or
  `SPARTA_CHECK_COMMENTS_BASE`) to find the lines this diff adds -- see below. A
  shallow clone with no such ref available skips the check rather than falling
  back to a whole-tree scan.

### Environment variables

| Var | Default | Purpose |
|---|---|---|
| `GODOT_BIN` | `godot` | Godot 4.7 binary to invoke. |
| `GUT_VERSION` | `v9.7.0` | GUT release to vendor when `addons/gut/` is missing. Keep in sync with `godot-ci.yml` and `test/README.md`. |
| `SPARTA_ALLOW_GODOT_VERSION_MISMATCH` | _(unset)_ | Set to `1` to run even when `GODOT_BIN`'s `major.minor` differs from the version `project.godot` targets. Off by default -- see "A Godot version mismatch fails fast" below. |
| `NO_COLOR` | _(unset)_ | Set to disable coloured output. |
| `SPARTA_CHECK_VALIDATE_TIMEOUT` | `900` | Hard timeout (s) for the `validate` Godot run. |
| `SPARTA_CHECK_TEST_TIMEOUT` | `1800` | Hard timeout (s) for the `test` Godot run. |
| `SPARTA_CHECK_COVERAGE_TIMEOUT` | `2700` | Hard timeout (s) for the `coverage` Godot run. |
| `SPARTA_CHECK_COMMENTS_BASE` | _(unset)_ | Commit-ish the `comments` (and `units`, `file_length`, `markdown`) check diffs `HEAD` against to find new lines to scan. Falls back to `origin/main` then a local `main`; CI sets this per-event (PR base SHA, or the push event's `before`) -- see `check-comment-citations.yml`. |
| `SPARTA_CHECK_GHA_REF` | `v2` | Morrison-Lab/gha ref whose lint-markdown and check-new-line-breaks checkers the `markdown` check runs; keep in step with both workflows' pin. |
| `SPARTA_CHECK_WINDOWS_MAX_PATH` | `260` | On Windows, the path length at which the `markdown` check refuses to run the line-break checker on a changed file, since the checker would skip it unread; `0` disables the guard where long paths are enabled. |
| `SPARTA_CHECK_PATCH_COVERAGE_BASE` | _(unset)_ | Same, for the `patch_coverage` check's diff base. |
| `SPARTA_CHECK_PATCH_COVERAGE_TARGET` | _(unset)_ | Fixed pass/fail threshold (percent) for `patch_coverage`. Unset mirrors `codecov/patch`'s `target: auto`: the project-wide line coverage from the regenerated `coverage/lcov.info`. |
| `SPARTA_GODOT_PREFLIGHT_LIMIT` | `5` | Warn when more Godot processes than this are already running before the checks start. |

## A Godot version mismatch fails fast

Every Godot-driving check (`validate`, `test`, `coverage`, `patch_coverage`,
`demo_defects`) compares `GODOT_BIN`'s `major.minor` against the version
`project.godot` declares in `config/features`, and refuses to run when they
differ:

```
Godot 4.6.3.stable.official.7d41c59c4 found at 'godot', but project.godot targets 4.7.
  Point GODOT_BIN at a 4.7 binary -- see tools/README.md and README.md.
  Left to run, this surfaces as parse errors from addons/gut/, not as a version error.
  Set SPARTA_ALLOW_GODOT_VERSION_MISMATCH=1 to run across versions deliberately.
```

(printed in red on stderr, via the same `err()` helper every other check uses --
no severity tag is prefixed.)

**Why a hard failure rather than a warning.** A mismatch does not fail cleanly
on its own. The vendored GUT release is pinned to match the targeted engine, so
an older binary cannot parse GUT's own singleton shim -- under a 4.6 binary,
GUT v9.7.0's reference to `AccessibilityServer` (a 4.7 addition) produces
`SCRIPT ERROR` lines from `addons/gut/`, which `has_script_errors()` matches and
reports as a plain `FAIL test` / `FAIL patch_coverage`. From the summary that is
indistinguishable from a real defect in the diff, and the backtrace points at
files the author never touched -- so the natural response is to go hunting
through their own changes. Failing at the version probe instead names the actual
cause, and costs a `--version` call rather than the suite's twenty-odd minutes.

**Major.minor only.** A 4.7.1 binary against a 4.7 target passes; pinning the
patch level would make the guard itself the nuisance.

**Either version being unreadable stands the check down** with a warning rather
than blocking a run over a probe that could not answer -- a `project.godot` with
no version-shaped entry in `config/features`, or a binary whose `--version` this
does not recognize.

**Deliberate cross-version runs** set
`SPARTA_ALLOW_GODOT_VERSION_MISMATCH=1`, which skips the comparison entirely.

## Checking patch coverage before you push

The CI `Coverage` job (`test-coverage.yml`) runs this same check, and Codecov's
`codecov/patch` reports the same metric when it is reachable, but both only after
a push -- a ~15-20 min round trip to discover a `scripts/` change fell short.
Run it locally first:

```sh
tools/check.sh patch_coverage
```

**Run it in the SAME invocation as `test`/the default set, not as a separate
command** -- e.g. `tools/check.sh validate test chars comments units
patch_coverage` (or just add `patch_coverage` to whatever other checks you're
already running). `patch_coverage` internally runs `coverage`, which is a
strict superset of what `test` checks (same suite, same pass/fail semantics,
plus the same script-parse-error guard) -- `main()` reorders a same-invocation
`test` to run *after* `coverage`/`patch_coverage` and `check_test` then
reuses that result instead of re-running the whole ~4-5 min GUT suite a
second time. This dedup only works **within one process invocation**:
`RESULT_NAMES`/`RESULT_STATUSES` are in-memory bash arrays that don't survive
between separate `tools/check.sh` calls, so running `tools/check.sh test`
and then, later, `tools/check.sh patch_coverage` as two separate commands
still pays for the full suite twice.

This regenerates `coverage/lcov.info` fresh (so the numbers reflect your
current working tree, not a stale report from a previous diff), diffs against
`origin/main` to find this diff's added `scripts/*.gd` lines, and reports a
per-file breakdown plus the exact missing line numbers -- a local
approximation of what Codecov will report, verified to match its output
directly (same percentage, same missing lines) on a real PR's diff. The check
then **gates on the effective target**, the same way the `codecov/patch`
status check judges a PR: with no explicit Codecov config, `codecov/patch`
uses `target: auto` -- patch coverage must reach the project-wide coverage of
the PR's base -- so this check compares against the project-wide total of the
report it just regenerated (HEAD's total rather than the base's: the closest
number available without a second instrumented run, differing only by this
diff's own effect on the total). The target is printed alongside the
percentage; a shortfall is a `FAIL`, matching what `codecov/patch` will do in
CI. Set `SPARTA_CHECK_PATCH_COVERAGE_TARGET` to pin a fixed threshold
instead (e.g. a deliberate one-off waiver, or reproducing a specific CI
verdict). It can still report `SKIP`, when there's no resolvable diff base.
Whether Codecov's own `codecov/patch` status check is configured to block a
merge on GitHub is a repo/branch-protection setting this local tool has no
visibility into.
The check also validates that files with added executable lines
have coverage records:
it warns on known uninstrumented autoloads
(`scripts/Settings.gd`, `scripts/Replay.gd`, `scripts/Sfx.gd`)
and fails if an unexpected file has zero instrumented lines
(guarding against the coverage instrumenter's block counter losing the rest of a file,
e.g. to a bracket inside a multiline string, which it does not tokenize).

If a diff comes up short, the fix is either genuine new test coverage for the
newly-added lines, or -- when a specific line is structurally hard to cover (a
scene-transition call, an OS/input-dependent path) -- accepting that one
residual line and saying so explicitly in the PR. Extract whatever IS
testable around it into its own function first, the way `HUD._on_quit_to_menu`
was split so its reset prelude is covered by
`test/unit/test_hud_scene_transitions.gd`, leaving only the actual
`change_scene_to_file(...)` call itself untested -- not the whole handler.
`test/unit/test_main_menu.gd`'s own note explains why that ONE call is never
exercised directly (it would trigger a real scene swap against the live test
runner). Padding coverage with tests that don't guard real behavior is worse
than a documented gap.

## Orphaned Godot processes: prevention and cleanup

Headless Godot runs survive their calling shell on Windows (no process-tree
kill), so a hung run whose shell died -- a harness command timeout, a session
end -- lives forever as an orphan and starves every later run on the machine.
Three layers keep that from piling up:

1. **Hard timeouts at the source.** Every Godot invocation in the repo's shell
   scripts (`check.sh`, `demo/dump-state.sh`, `demo/capture-frames.sh`,
   `benchmark/run-benchmark.sh`, `../website/tools/record-demos.sh`) runs under
   coreutils `timeout` via the shared `lib/run-bounded.sh` helper, so a hung
   Godot is killed -- not just the calling shell. Budgets are generous
   hang-detectors, overridable per script (see each script's header). On stock
   macOS (no coreutils), the scripts run unbounded with a one-time warning;
   `brew install coreutils` restores the net.
2. **In-engine safety nets.** Each runner scene quits itself once a wall-clock
   budget expires, even when the invoker forgot `--quit-after`:
   `demo/RunWatchdog.gd` (attached by `DemoRunner` and `DemoInputRecorder`;
   default 900 s, override via `SPARTA_RUN_TIMEOUT_SEC`) and
   `benchmark/BenchmarkRunner.gd`'s own timeout + stall guard.
3. **Pre-flight warning.** `check.sh` warns when more than a handful of Godot
   processes are already running -- the early signal of a leak building up (and
   the likely explanation for slow or flaky local runs).

### `kill-orphan-godot.ps1` / `kill-orphan-godot.sh` -- sweep script

Lists Godot processes whose command line matches a **non-interactive run
signature** (headless import, GUT suite, demo/benchmark recording -- an
interactive editor session never matches, so it is never touched) and
classifies each:

- **Orphaned** -- the parent process is gone, so nothing is consuming the
  output. Safe to kill by construction: killing Godot cannot lose git state.
- **Overdue** -- older than the age ceiling (default 2 h; no legitimate repo
  run takes that long).
- **Child** -- a matched process whose parent is itself being killed by this
  sweep (the Windows console build is a launcher exe that spawns the real
  Godot as a child; killing only the launcher would leave the real process
  behind).
- **Live** -- everything else; never touched.

**Dry-run by default** -- it only prints what it would kill:

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
scheduled task every 30-60 min so a leak never builds up unattended.

## `check-worktree-state.sh` -- find stale or abandoned worktrees

A checkout can sit dozens of commits behind `origin` with staged entries that
exist in no commit and on no remote, and still look entirely ordinary.
It is not mid-merge, mid-rebase, or mid-cherry-pick, so nothing announces it.
Two hazards follow.
A session obeying the standing freshness rule either fails to fast-forward or
silently carries that staged set into unrelated work.
And the staged content itself is one disk failure from gone.

This script makes that observable.
It walks every worktree of the repository and reports, per worktree, its branch,
how far it is behind and ahead of the remote default branch, how many commits no
remote ref contains, and how many uncommitted and staged entries it holds.

```sh
tools/check-worktree-state.sh              # table; exit 1 if anything is flagged
tools/check-worktree-state.sh --json       # one JSON object, for scripting
tools/check-worktree-state.sh --strict     # also flag feature-branch dirt
tools/check-worktree-state.sh --warn-only  # report, but always exit 0
```

The verdicts:

| verdict | meaning | remedy |
| --- | --- | --- |
| `prunable` | the worktree's directory is gone | `git worktree prune` |
| `stale` | on the default branch, behind its remote | `git merge --ff-only origin/<default>` |
| `diverged` | on the default branch, with commits the remote lacks | needs a human; a fast-forward will refuse |
| `unpushed` | commits reachable from HEAD that no remote ref contains | push the branch |
| `misplaced` | uncommitted entries in a default-branch worktree | commit to a branch and push, then clean up |
| `dirty` | uncommitted entries on a feature branch | nothing; this is what a live session looks like |

`dirty` is reported but not flagged unless `--strict`, deliberately:
a working session always has uncommitted edits,
and a check that goes red every time is a check nobody reads.

The summary line reports how many worktrees were **examined** alongside how many
were flagged, so a clean run is distinguishable from a detector that silently
examined nothing.

The default-branch verdicts (`stale`, `diverged`, `misplaced`) key on the
worktree's branch NAME matching the resolved default branch.
A worktree sitting at the default branch's tip in detached HEAD is therefore
judged by the feature-branch rules instead, so its dirt reads as `dirty` rather
than `misplaced`.
That is a deliberate narrowing rather than an oversight:
a detached worktree is somebody's deliberate scratch checkout,
and the state this tool exists to catch was a named `main` checkout.
The default branch is resolved from the remote
(`refs/remotes/<remote>/HEAD`, falling back to `git ls-remote --symref`),
never assumed to be `main`.
Measured against a ref that does not exist, every worktree would read as clean.
Tune with `SPARTA_WORKTREE_REMOTE` (default `origin`)
and `SPARTA_WORKTREE_STALE_MAX`
(commits of staleness tolerated on the default branch, default `0`).

`tools/lib/tests/test-worktree-state.sh` covers it,
and runs with the rest of the shell tests (`tools/check.sh shell_tests`).
Each case regresses a throwaway repository into the state one verdict is meant
to catch and asserts both the verdict and the exit status,
so the suite would fail if the detector answered "ok" for everything.
## `bootstrap-ai-config.sh` -- vendor ai-config for Gemini / Antigravity

Shallow-clones [`Morrison-Lab/ai-config`](https://github.com/Morrison-Lab/ai-config)
into `.ai-config/` at the commit pinned in `.ai-config-ref` (committed at the repo
root). The checkout is gitignored. Claude Code uses the plugin marketplace instead;
this script is for Gemini CLI and Antigravity sessions that read
`.gemini/config.json` and `.agents/{plugins,skills}.json`.

```sh
tools/bootstrap-ai-config.sh
```

Re-run after bumping `.ai-config-ref`. The script is idempotent: it skips work when
the checkout already matches the pin.

## `demo/`

The headless demo recorder used by the demo-video pipeline -- see
[`demos/README.md`](../demos/README.md).

## Perturbed melee-outcome delta (`ci/melee-outcome-delta.sh`)

The acceptance check for a change to melee dynamics.
Melee outcomes in the catalog clips are chaotic:
nudging each unit's facing by 0.0001 rad once flips which routers escape and when units die.
So "no router breaks later than main on any clip" cannot tell a regression from chance.
This script runs each melee clip K times on both trees, each run on a different seed,
and flags only the shifts that hold up across the runs.

```sh
GODOT_BIN=godot tools/ci/melee-outcome-delta.sh <base-tree> <head-tree> <out-dir>
MELEE_DELTA_CLIPS=spear_standoff,charge MELEE_DELTA_METRICS='uid[0-9]+_(break|contact_break|travel_300)$' \
  tools/ci/melee-outcome-delta.sh <base-tree> <head-tree> <out-dir>
```

**A clean report is not evidence of no regression.**
A row's MDS column is the change it would flag 80% of the time, so a row is weak evidence of no effect only for changes larger than its MDS,
and a change smaller than the MDS is usually missed.
At the defaults over all 50 clips, about 40% of tested rows cannot be flagged with any change at all.
Ask a narrow question instead: name the clips and metrics the change is about, which keeps the row count small.

### Perturbation

`SPARTA_DEMO_SEED_RUN=k` (`tools/demo/DemoSeed.gd`, read by `DemoInputRecorder` and `DemoRunner`) plays the clip on a seed hashed from its own seed and `k`.
The scenario, orders and spawn are unchanged.
What differs is every draw from `Replay.rng` (melee land, fall and damage rolls, missile hits)
and the scatter of a far-tier promotion, which comes from a local RNG seeded with `Replay.seed_value`.
A run is bit-identical to the clip until the first of those, which can be a missile volley or a promotion before any melee contact.
Unset, the clip's own seed plays, so every existing clip hash is unchanged.
Both trees must carry `DemoSeed.gd`.

### Metrics per run

`tools/demo/MeleeOutcomes.gd` reads compact state dumps taken every `MELEE_DELTA_STEP` ticks (default 5).
Per run it records the first contact tick and each team's men on the field at the end.
Per unit it records its first contact tick, its break tick (first `ROUTING` snapshot) and the tick it left play.
After a break it also records the contact-break delay (ticks from the break until the unit is out of contact),
its men's centroid travel 60, 150 and 300 ticks after the break,
and whether it had left play by each of those offsets (a removed-by indicator).

Each value is one of three things.
A number means the event happened.
"never" means the run was observed to its end (the last scheduled snapshot, or a `battle_over` snapshot) and the event did not happen.
It ranks after every tick.
Unobserved means the stream was cut off first, or the question does not apply: travel after the unit left play is censored, and so is the break of a unit destroyed unbroken.
Unobserved values are dropped, not ranked, and every row reports how many it dropped on each side.
Each run directory records its last scheduled tick and cadence in `run.json`,
and a `metrics.json` is reused only when it was made with the same travel offsets, cadence and end,
so a re-extraction from kept snapshots still tells a cut-off run from a complete one.
Leaving play does not yet say whether the unit escaped or died (TODO(#1832)),
and a replay clip's stream has no `battle_over` marker (#1831), so a replay battle that ends early reads as cut off.

### Comparison

`tools/demo/MeleeOutcomeDelta.gd`, `OutcomeStats.gd` and `OutcomePower.gd` do the statistics.
Each clip and tick, metre or headcount metric gets an exact two-sided rank-sum (Mann-Whitney) test, with tied values sharing a mid-rank.
A removed-by indicator is a proportion, so it gets Fisher's exact test, and its effect is the change in percentage points.
A median of 0/1 values could not register a change from 0% to 40% at all.
Whenever a metric has unobserved values on either side, a `<metric>:unobserved` row tests how often it went unobserved, also with Fisher's test.
That row is flagged on significance alone,
and when it is significant the metric's own row is marked "not comparable", because its two sides dropped different shares of runs.
Dropping censored runs is still a simplification: a censoring-aware rank test (Gehan) belongs here once escapes are told from deaths (TODO(#1832)).
Then Benjamini-Hochberg runs across every row tested in the report, at `MELEE_DELTA_ALPHA` (default 0.05).
That bounds the false discovery rate: in expectation, at most 5% of the flags are false.
It bounds the chance of any flag at all only when no row has a real change.
BH's bound assumes the rows are independent or positively dependent.
These rows are not independent: the travel offsets come from the same runs, and two teams' headcounts move against each other.
`MELEE_DELTA_CORRECTION=by` uses Benjamini-Yekutieli, which holds under any dependence at the cost of dividing alpha by about 5.8 for 180 rows.
BH stays the default because power, not false flags, is the binding limit (see the table below), and both measured nulls flagged nothing.
Use `by` when a report gates a decision.

A significant rank row is flagged only when its Hodges-Lehmann shift is also at least its threshold:
`MELEE_DELTA_MIN_EFFECT` (default 0.5) times that row's own run-to-run spread,
the robust standard deviation of its base runs (1.4826 times the median absolute deviation, or the sample standard deviation when that is 0).
The criterion is a standardized effect size of half a standard deviation (Cohen's "medium"), fixed before any validation run.
The floors are the measurement resolution: the snapshot cadence (5 ticks), 0.1 m (`MELEE_DELTA_FLOOR_METRES`) and 1 man (`MELEE_DELTA_FLOOR_MEN`).
A removed-by indicator is flagged when significant and at least `MELEE_DELTA_MIN_PP` (default 20) percentage points:
a unit removed in roughly one more battle in five, a change a player would notice over a handful of battles.
At K=16 it rarely binds: in the back-test's narrow report the 80%-power detectable change of a removed-by row was 69 points or more.
The threshold does not screen noise on its own: in the null run below, 39 of the 222 rows had a shift past it.
The significance test screens noise, and the threshold then drops significant shifts too small to matter.

Each tested row also reports its smallest attainable p-value and its minimum detectable change (the MDS column):
the change a fresh experiment of the row's own run counts would flag alone (at alpha divided by the row count, and by the harmonic number for `by`) with 80% probability,
and never less than the row's threshold, since a smaller change is never flagged.
It comes from simulation in `OutcomePower.gd` with a fixed seed.
For a tick, metre or headcount row it is the normal-model shift in standard deviations times the row's robust spread,
so on a heavily tied row the real power is lower and the MDS is a lower bound.
For a row with "never" in its base runs it is the change in how often the event never happens, in percentage points,
and for a proportion row the change in percentage points.
`test/unit/test_outcome_power.gd` checks each against an independent simulation, which detects a change of that size 72% to 88% of the time.
The MDS is `inf` for a row that cannot reach the level whatever the change, typically a row with few runs, such as the travel of a unit that rarely breaks.
A metric with fewer than `MELEE_DELTA_MIN_RUNS` (4) runs on a side is listed but not tested.

### Power

Measured 2026-10-12 by simulation (300 trials per cell, two normal samples of K, the head shifted by d standard deviations),
the chance the exact test reaches the level one row needs alone among m rows:

| K | d | m = 1 (p <= 0.05) | m = 10 (0.005) | m = 150 (0.00033) |
|---|---|---|---|---|
| 8 | 1.0 | 0.43 | 0.12 | 0.03 |
| 8 | 2.0 | 0.96 | 0.69 | 0.23 |
| 16 | 1.0 | 0.77 | 0.43 | 0.13 |
| 16 | 1.5 | 0.98 | 0.82 | 0.58 |
| 16 | 2.0 | 1.00 | 0.99 | 0.87 |
| 24 | 1.0 | 0.90 | 0.66 | 0.34 |
| 24 | 1.5 | 0.99 | 0.98 | 0.87 |

So the default K is 16.
A whole-catalog report (m about 170) reliably catches only shifts near 2 SD.
A narrow question (m about 10 to 30) catches 1.5 SD.
Pass a larger `MELEE_DELTA_K` when the change is subtle.

### Output

`<out-dir>/melee-delta.md` is a summary to paste into a PR.
It lists the flagged rows, says how many tested rows could not be flagged with any change, and, collapsed, the smallest p-values.
`melee-delta.tsv` holds every row with its threshold, smallest attainable p, minimum detectable change and its unit, unobserved runs per side, and status.
Exit code 0 means nothing was flagged, 1 means at least one flagged shift, and 2 means a usage, input or run failure.

### Cost and subsets

The defaults (`K=16`, all 50 clips in `tools/lib/melee-clips.sh`) make 1600 Godot runs.
Measured on a 20-thread Windows machine with a second delta running beside it (2026-10-12),
1600 runs took 58 minutes at `MELEE_DELTA_JOBS=8`, and 800 took 30.
`MELEE_DELTA_CLIPS=a,b` runs a list of your own, and `MELEE_DELTA_SUBSET=quick` the 6 clips whose outcomes flipped under the facing nudge.
`MELEE_DELTA_METRICS` narrows the rows without changing the runs.
`MELEE_DELTA_JOBS` (default 2) sets how many runs go in parallel.

Each run's metrics are extracted in the pool, right after its dump, into its own `metrics.json`,
so the comparison itself takes seconds.
The snapshots (about 5 MB a run) are then deleted unless `MELEE_DELTA_KEEP_DUMPS=1`.
A re-run reuses every finished run, keyed on side, clip and seed, and compares only the clips and seeds it selected,
so change thresholds or questions freely, but use a fresh out-dir when a tree changes.

### Validation

Measured 2026-10-12 at `K=16` over all 50 clips with the defaults above.
The effect multiple, the floors, `MELEE_DELTA_MIN_PP` and K were set before these runs, from the criteria above and the power table.
The two known effects were new and not used to choose anything.
An earlier round fitted a fixed 1 m travel threshold to a routers-30%-slower run.
That threshold is withdrawn.

- **Null:** the same tree against itself on disjoint seeds (`MELEE_DELTA_HEAD_RUN_OFFSET=16`) flagged 0 of 222 tested rows,
  51 of them `:unobserved` rows, and marked none "not comparable".
  6 rows had a raw p at or below 0.05.
  88 of the 222 could not be flagged with any change.
  The quick subset alone flagged 0 of 108.
  (The previous round's code, without the proportion rows, also flagged 0 of 171 under BY.)

- **Routers 15% slower** (`flee_speed()` times 0.85) flagged 3 of 219 rows, all in `rout_rally`:
  team 0's median end headcount rose from 140 to 152, because the 12-man router, removed at a median tick 655, stayed on the field in all 16 runs,
  and its travel 300 ticks after the break fell from 15.4 m to 14.8 m.
  `trapped_routing`'s router travel also fell, by 0.05 m: significant, but under the 0.1 m floor.

- **Melee wounds 20% weaker** (the wound times 0.8 in `SoldierMelee`) flagged 33 of 214 rows in 24 clips: 28 team headcounts and 5 break ticks.
  For example, `spear_standoff`'s router broke at a median tick 847.5 instead of 710, and `file_major_reform_contrast`'s at 925 instead of 745.

- **Back-test:** the first version of PR #1814 (581db291 against its base 9d39a353), run with the previous round's code over all 50 clips, flagged 11 rows.
  They are in `cycle_charge`, the caracole regression with a traced mechanism (contact timing and both headcounts),
  in `pace_modes` (contact 70 ticks earlier in every run, and both teams about 10 men stronger),
  and in `support` (a unit that made contact at tick 800 in every base run made none in 14 of 16).
  It flagged no router row in `file_major_reform_contrast`, `spear_standoff` or `last_unit_rally`,
  and neither does this round's narrow report on those three clips' router metrics (43 rows).
  That is not evidence the routers were unaffected: those rows' 80%-power minimum detectable changes are
  54 to 265 ticks on break ticks, 63 ticks on `spear_standoff`'s contact-break, 3.3 to 7.6 m on travel at 300 ticks,
  and none at all (`inf`) for `file_major_reform_contrast`'s contact-break and later travel, and for every removed-by row with a base rate between 35% and 60%.

### Null calibration

`MELEE_DELTA_HEAD_RUN_OFFSET=K` with the same tree on both sides compares disjoint seeds of identical code.

### Clip list

`tools/ci/melee-outcome-delta.sh --derive-clips <tree> <out-dir>` runs every catalog clip once and prints those with any enemy contact.
Paste its output into `MELEE_CLIPS` when the catalog gains a fighting clip.

The script is not wired into CI: run it locally on any PR that changes melee dynamics and paste the summary into the PR.

## `perf/`

Before/after graphs of **computations per tick** -- the evidence a backend-only
performance PR ships alongside its post-improvement demo clip. Deterministic work
counts (`scripts/SimOps.gd`) rather than wall-clock time, so the two lines differ only
where the code did. `ops-before-after.sh` records both sides and draws the graph; see
[`perf/README.md`](perf/README.md) for the protocol and CLAUDE.md's "Backend-only
performance PRs" for when it's required.

## `ci/`

Small helpers invoked by GitHub Actions workflows.

- `upsert-pr-comment.sh <repo> <pr> <marker> <body> [label]` -- PATCH the existing
  marker-tagged PR comment if one exists, else POST a new one. Used by
  `.github/workflows/demo-video.yml` so its recorded-clip and "no clip applies"
  paths share one comment-upsert implementation. Needs `gh` authenticated via
  `GH_TOKEN`.
  Refuses a body over GitHub's 65,536-character comment limit with an error naming its size, rather than letting the API return a bare 422.

- `state-transcript-summary.sh <state-dir> <merged-json-out> <summary-md-out> [table-max-bytes]` --
  merge a demo's per-tick state snapshots into one JSON and render the PR comment's transcript table.
  Over the byte budget (default 45000), it keeps a head block and a tail block of rows, each about half the budget, and replaces the middle with one marker row.
