## Leading tabs vs. Read separator tab hazard -- Edit tool `old_string` matching

When copying text from Read output, Read's `NNNN\t<content>` separator tab is visually indistinguishable from a file's own leading indentation tab. An accidental extra leading tab (or missed tab) in `old_string` causes "String to replace not found in file". `sed -n 'N,Mp' <file> | cat -A | sed 's/\^I/[TAB]/g'` is a fast way to inspect exact tab counts when an Edit target fails to match despite visual appearance.

**Historical Note (Line Endings):** `Lacaedemon/sparta` PR #981 (2026-07-18) previously documented mixed CRLF/LF line endings and instructed sessions to split multi-line Edit anchors on `Battle.gd`. On 2026-07-29 (PR #1177), `.gitattributes` added `* text=auto eol=lf`, normalizing all repository files to LF across all checkouts. Standing instructions to split multi-line anchors for CRLF reasons are obsolete; only the leading-tab hazard remains active.

## `tools/check.sh`: a wrapping check needs a dedicated result key to short-circuit its wrapped check safely

A check that internally reuses another check's expensive work (`check_patch_coverage`
calling `check_coverage` so both don't independently re-run the full GUT suite) creates
a trap for any THIRD check that wants to reuse the same work: don't key the reuse
decision off the wrapping check's own overall pass/fail, because "the wrapping check's
own gate failed" and "the underlying operation it wrapped failed" are different
questions, and only the second one is safe to propagate.

**Concrete case (PR #990, closes the `test`/`coverage`/`patch_coverage` double-run):**
`check_test`'s short-circuit originally read `get_result coverage`/`get_result
patch_coverage` directly to decide whether to skip a redundant `test` run. But
`patch_coverage`'s PRIMARY, intended failure mode is its own coverage PERCENTAGE
landing below target -- not a suite problem at all, and the single most common way for
`patch_coverage` to legitimately fail. Reading its overall `fail` result as "the suite
must also be broken" wrongly reported `test` as failed on a perfectly clean run --
exactly the common case, since CLAUDE.md's own recommended invocation runs `test` and
`patch_coverage` together. `check_coverage`'s own overall result has the same problem
from a different angle: a clean suite run followed by a failed `coverage/lcov.info`
write (the post-run hook's `push_error()` doesn't fail the Godot process) still makes
`check_coverage` return non-zero, again for a reason that says nothing about `test`.

**Fix:** `check_coverage` now records the GUT suite's own health under a dedicated
internal key (`_suite_health`, never surfaced in the printed summary since that loop
only iterates the top-level requested `checks` array) at the exact point the suite run
itself is known clean -- separate from, and set BEFORE, the function's own final
return value (which still depends on the lcov write succeeding). `check_test` reads
`_suite_health` instead of `coverage`'s/`patch_coverage`'s own result. This works
correctly regardless of which top-level check reached `check_coverage` first
(`run_check` calling it directly for a requested `coverage`, or `check_patch_coverage`
calling it internally as its own reuse path) since `set_result` always updates the
same key.

**How to apply:** any time you're tempted to short-circuit check B by reading check A's
overall pass/fail/skip result, first ask whether A's own gate (a threshold, a
post-processing step, anything beyond "did the expensive shared operation succeed")
can fail independently of that operation. If so, the shared operation needs its own
result key that only the operation's own outcome writes to -- not A's summary result,
which conflates the operation with A's own additional judgment on top of it.

**Verifying a check.sh logic fix without a full ~18-min Godot re-run:** when a fix is
purely bash control-flow (case statements, `set_result`/`get_result` calls) with zero
change to the actual Godot/GUT invocation, extract just `set_result`/`get_result` plus
the changed case statement into a small standalone throwaway script (no `main "$@"` at
the bottom to guard against -- check.sh has none, so sourcing it runs the whole thing),
seed `RESULT_NAMES`/`RESULT_STATUSES` by hand for each relevant scenario, and assert
the short-circuit's return code. This proves the LOGIC correctly without paying for a
real suite run every iteration; reserve an actual `tools/check.sh test coverage`
invocation (or trust CI's own real run on the pushed PR) for confirming the Godot
invocation itself still behaves once the logic is settled.

## Composite-action CI refactors: `workflow_dispatch` a path-filtered/tag-gated workflow to verify it before merging -- but read its full job list first

A CI-critical refactor (e.g. extracting shared Godot/GUT setup steps into
`.github/actions/setup-godot-project/action.yml`, PR #989) touches workflow files that
a normal PR's own CI often can't exercise: `benchmark.yml`/`demo-video.yml` are
path-filtered to sim/game files (a docs-only or CI-only PR never triggers them) and have
**no `workflow_dispatch:` trigger at all** -- a PR that doesn't happen to touch their path
filters can't spot-check them by any means short of a real trigger.
`publish-site.yml`/`refresh-benchmark-baseline.yml`/`release.yml` only run on
`push: branches: [main]`, `schedule`, or `push: tags: v*` respectively (never on a
plain `pull_request`), but all three DO have `workflow_dispatch:` -- that's the way to
verify the refactor actually works in real CI before merging, rather than shipping it
untested and finding out at the next real trigger (a tag push, for `release.yml`, is
an especially expensive place to discover a broken composite-action call).

**But check what the workflow's LATER jobs do before dispatching -- not every
workflow with a `workflow_dispatch` trigger is side-effect-free to run manually.**
`release.yml` is genuinely safe: its own header comment states a dispatch run builds
every artifact "without touching a release," and its "Publish to the GitHub Release"
step is explicitly gated `# Only on a version tag` -- confirmed both in prose and in
the actual `if:` condition before dispatching. `publish-site.yml` is NOT safe the same
way: its `publish` job (the live GitHub Pages deploy) is gated only by `needs:
[demos]` + `if: always()` -- no trigger-type condition at all -- so a `workflow_dispatch`
run deploys to the live site exactly the same as a real `push: branches: [main]` would.
Dispatching it to spot-check the composite-action call crossed into "modifying public
content" territory without recognizing it up front; caught mid-run (only the `demos`
job had started) and cancelled before the `publish` job's turn came up.

**How to apply:** before `gh workflow run`-ing an unfamiliar/rarely-manually-triggered
workflow to spot-check a change, read its full job list and look specifically for a
deploy/publish/release job's own gating condition (or lack of one) -- don't infer
safety from the workflow's general purpose or from one job's own header comment
without checking the actual `if:`. If a dispatched run's job list shows something that
could reach a live-effect step with no confirmed gate, cancel it (`gh run cancel`)
before that job starts and ask before re-dispatching.

## `tools/check.sh`'s comments/units/patch_coverage steps are diff-scoped -- commit before running them, not after

`check_comments`/`check_units`/`check_patch_coverage` all compute
`git diff --no-color -U0 "$(git merge-base HEAD "$base")" HEAD -- '*.gd'` (or a
narrower glob) -- a diff against **HEAD**, not the working tree. Running the bundled
`tools/check.sh validate test chars comments units patch_coverage` invocation against
**uncommitted** changes (reasoning "verify before I commit") means these three steps
compare HEAD against itself and find nothing to check -- they silently print a clean
pass ("No GDScript changes in this diff") without having examined the actual edits at
all. Only `validate`/`test`/`chars` are disk-based and give real signal in that case.

This cost one delegated agent roughly two hours and ~1M tokens in one session: real,
working code sat as an uncommitted diff for two full turns while the agent repeatedly
re-ran the bundled check (each pass ~15-20 min) against it, never noticing three of
the five requested checks were no-ops. Caught only because the orchestrating session
noticed the mismatch directly (`git log`/`git status` showed no commits and no
uncommitted changes despite two turns of claimed work) and asked why.

**How to apply:** commit (even a rough, not-yet-polished draft) before running the
bundled check, not after -- re-commit/amend once the check's own findings are
addressed. When briefing a subagent to implement-and-verify a feature in this repo,
say this explicitly in the brief. If an agent (or you) burns much more wall-clock than
a diff's size would justify, check `git log`/`git status` directly before trusting
"still verifying" -- it's a fast, decisive way to catch this class of problem.
(`Lacaedemon/sparta` PR #999, 2026-07-19.)

**A subtler variant of the same mistake: running the check against uncommitted edits
when a PRIOR commit's diff is already on the branch doesn't fail loudly at all --
it silently reports against the stale prior commit instead.** The "no GDScript changes
in this diff" message above only fires when HEAD has no diff against the base AT ALL
(a brand-new branch with nothing committed yet). Mid-PR, after several review-fix
rounds, HEAD already has a real diff from earlier commits -- so re-running the bundled
check against a NEW uncommitted edit (a further review-fix, made without committing
first) doesn't produce an obvious "nothing to check" signal. It just silently
evaluates the OLD diff (as of the last commit) and reports plausible-looking but
WRONG line numbers/coverage percentages for code that no longer matches what's on
disk -- much harder to notice than the "no changes" case, since nothing looks broken
at a glance. Caught only by directly reading the file at the reported line number and
finding it didn't match the reported content. **How to apply:** treat "commit before
running the bundled check" as absolute, not just for a check's very first run on a
branch -- re-verify with `git status --short` immediately before EVERY invocation of
`tools/check.sh comments/units/patch_coverage`, not just the first one in a PR's
review-iteration loop, especially when working through several rapid review-fix
rounds where committing can get skipped in the rush to re-verify quickly.
(`Lacaedemon/sparta` PR #1063, 2026-07-23: a review-fix round for #1047 ran the
bundled check against an uncommitted `UnitCardTray.gd` edit; the report named a
"missing" line whose reported content, when checked, was `_on_placement_toggled`'s
body from the OLD committed diff, not anything in the actual uncommitted edit.)

## Benchmark check reports PASS regardless of content -- and the baseline goes stale for a whole week after any PR with an accepted cost increase

`benchmark.yml`'s own posted comment can show a real regression (`:warning: Regressed
beyond the 20% threshold`) while `gh pr checks`/the GitHub check conclusion still
reports the job as **PASS** -- this is deliberate (the threshold is "a human call, not
an auto-block"), but it means the check's own green color carries **zero** signal
about whether there's a real finding to read. Always fetch and read the actual posted
comment body (`gh api repos/.../issues/<N>/comments --jq '...sparta-benchmark...'`),
never trust the check conclusion alone, for this specific check.

Separately: `tools/benchmark/baseline.json` is refreshed only by a **weekly schedule**
(`refresh-benchmark-baseline.yml`), not on every `main` push. When a PR's own cost
increase is investigated and accepted as a legitimate, deliberate consequence of a new
feature (not a bug -- e.g. a costlier maneuver firing more often by design), merging it
does NOT refresh the baseline immediately. Every subsequent PR then shows a **false**
"regression" against the now-stale, pre-merge baseline until the next weekly refresh
(or a manual `workflow_dispatch` of that workflow) runs. Before spending time
investigating a benchmark-regression finding as if it were new/PR-specific, check
whether `main` gained an accepted cost increase since `baseline.json`'s own header
comment date -- if so, the "regression" is very likely just baseline staleness, not
something the current PR's own diff caused. (Sequence observed 2026-07-19: PR #922's
moving-wheel maneuver accepted a ~38.8% mean-tick-time increase as an intended cost of
the feature; PRs #995 and #999, merged shortly after, each showed a near-identical
~35-40% "regression" against the same pre-#922 baseline, attributable to neither PR's
own code.)

**A third case, distinct from both above: a genuine same-machine before/after comparison
settles whether a flagged regression is real, when the change is too small to plausibly
cause it and the baseline isn't stale.** CI's baseline is CI-runner-relative and can't be
reproduced locally byte-for-byte, but a LOCAL before/after comparison on the SAME machine,
SAME seed, SAME scenario sidesteps that -- it doesn't need to match CI's absolute numbers,
only to show whether the PR branch is faster/slower than its own merge-base:
```sh
GODOT_BIN=... SPARTA_BENCHMARK_WARMUP_TICKS=60 SPARTA_BENCHMARK_TICKS=300 \
  bash tools/benchmark/run-benchmark.sh   # on the PR branch
git checkout <merge-base-sha>             # detached HEAD; safe when no Godot job is running
GODOT_BIN=... SPARTA_BENCHMARK_WARMUP_TICKS=60 SPARTA_BENCHMARK_TICKS=300 \
  bash tools/benchmark/run-benchmark.sh   # same scenario, same seed, same machine
git checkout <pr-branch>
```
(`SPARTA_BENCHMARK_WARMUP_TICKS`/`_TICKS` at 60/300 match `benchmark.yml`'s own CI-tuned
window, not `BenchmarkRunner`'s local 120/600 defaults -- match CI's window for the
comparison to mean anything.) On PR #1009 (three float instance-field reads added to
`Unit.gd`/`FarTierRules.gd` -- no plausible mechanism for a real slowdown), CI reported a
25.7%/29.2% regression labeled "CI-runner-noisy -- a human call, not an auto-block"; the
local comparison showed the PR branch **faster** (mean 28.9ms vs merge-base's 32.4ms) on
identical inputs, conclusively confirming pure runner noise rather than tracking down a
phantom regression in code that couldn't have caused one. This is the concrete instance of
`baseline.json`'s own documented ~20% swing between functionally-identical runs (see its
`_comment`, citing #755) -- when a flagged regression's magnitude is in that same ~20-30%
band AND the diff has no plausible causal mechanism, suspect noise first and verify this
way rather than assuming the label is wrong or right without checking.

## File-major casualty reflow: verifying "which file stays shallow" needs de-rotation into local frame, and beware odd/even parity between remainder and file count

Two lessons from independently re-verifying PR #995's own file-major-reform demo and
authoring a follow-up demo for PR #999's AUTO mode, worth keeping in mind for ANY
future formation-geometry verification via `dump-state.sh`:

1. **Bucketing `soldiers_full.slots` by raw world-space x is unreliable once a unit's
   facing has rotated even slightly** (an engage-turn, a maneuver in progress) --
   de-rotate each soldier's position into the unit's own local frame first
   (`ang = atan2(facing.y, facing.x) + pi/2`, then rotate `(pos - unit.position)` by
   `-ang`) before bucketing by file. Skipping this makes a perfectly clean 7-file
   layout look like 13+ noisy buckets once facing drifts even a few degrees off-axis.
2. **When the live soldier count's remainder (`count mod files`) and the file count
   itself have OPPOSITE parity (one odd, one even), the partial rank's soldiers sit on
   HALF-file-spacing offsets, not aligned with the full-frontage grid at all** -- this
   is `UnitFormation.block_slots`' own documented behavior for a partial rank whose
   count/frontage parity differs, and it applies to `file_major_block_slots`' fully-
   populated files as a residual layout artifact too. A naive de-rotated bucket-and-
   snap-to-nearest-file-spacing analysis can misattribute which column looks
   "shallow" in this specific case (a genuinely rare accident of exact soldier counts,
   not a bug) -- if a quick verification script gives a confusing/inconsistent
   "shallowest file" reading, check the remainder/file-count parity before assuming
   the underlying feature is broken. The *decisive* proof for this mechanism should
   always be a dedicated GDScript test asserting on the persistent per-soldier file
   array directly (`test_file_major_reform_battle.gd`,
   `test_auto_reform_mode_battle.gd`), not a demo clip eyeballed or bucketed after the
   fact -- a demo just needs to show the feature existing and applying, and its
   caption should say so explicitly when a specific seed's counts hit this parity
   case rather than overclaiming a precise per-file numeric proof it can't actually
   support. (`Lacaedemon/sparta` PR #995/#999, 2026-07-19.)

## `SoldierBodies.step()` and `couple()` both independently recompute `soldier_world_slots` every tick -- a pre-existing redundancy a costlier code path can expose as a benchmark regression

`Battle`'s per-tick soldier-layer pipeline runs `step_all_sim_soldiers` (calls
`SoldierBodies.step()` per unit) to completion for every unit, THEN separately runs
`couple_all_sim_soldiers` (calls `SoldierBodies.couple()` per unit) -- two full passes
over every unit, and both `step()` and `couple()` independently call
`unit.soldier_world_slots(unit.soldiers)`, recomputing the exact same result a second
time with nothing in between that could have changed it (nothing mutates a unit's
position/facing/formation state between the two passes finishing/starting). This
redundancy predates any specific feature and applies to BOTH row-major and file-major
reflow -- but `file_major_reform`'s own per-call cost (an extra O(soldiers) pass in
`UnitFormation.file_major_block_slots` vs. the historical single-pass `block_slots`)
made the existing 2x-redundant computation expensive enough to surface as a real,
measured 45.2% CI benchmark regression on PR #995.

**Fix pattern, not a general cache:** rather than caching `soldier_world_slots`
broadly (risky -- any OTHER caller that mutates position/facing mid-tick in a way not
yet audited could read stale data), scope the fix narrowly to the two specific call
sites: `SoldierBodies.step()` stashes the slots it already computed
(`Unit._step_slots_for_couple` / `_step_slots_for_couple_valid`), and `couple()`
consumes-and-clears that single-use handoff instead of recomputing, falling back to a
fresh computation if the handoff is missing or size-mismatched. Verified this dropped
the regression from 45.2% to 4.3% against the same CI baseline.

**When a new/costlier code path triggers a benchmark regression, check for a
pre-existing redundant-computation pattern like this BEFORE assuming the new code
itself needs optimizing** -- the new code's own cost may be fine in isolation; it's
often just exposing an existing 2x (or more) waste that was previously too cheap to
notice. (`Lacaedemon/sparta` PR #995, 2026-07-19.)

## Orchestrating multiple Godot-touching agents in parallel worktrees: the shared-process hazard bites BETWEEN agents, not just between manual sessions -- and self-checking via `tasklist` is not by itself sufficient

Sparta tolerates only one Godot process running anywhere on the machine at a time
(shared `user://settings.cfg`, keyed by project name, not path -- see the "shared
ACROSS worktrees" entries above). Those entries already document the hazard for a
single human/session switching contexts; it recurs identically, and more easily,
when an orchestrating session dispatches SEVERAL background subagents that each
own their own worktree and each independently run `tools/check.sh`. Worktree
isolation prevents FILE-level collisions; it does nothing for this PROCESS-level
one.

**What actually went wrong, concretely (GII session, 2026-07-19/20, two
subagents -- one fixing #979, one implementing #1014):** the orchestrator
launched both agents' Godot-heavy verification work without serializing them.
Two full sets of `check.sh` processes ended up running concurrently for real
(confirmed via `Get-CimInstance Win32_Process -Filter "Name LIKE '%Godot%'"`
showing two distinct console+engine PID pairs at two different `CreationDate`
timestamps). Both runs had to be discarded and redone.

**The self-checking discipline that ultimately worked, after two false
resolutions:**
1. A bare `tasklist //FI "IMAGENAME eq ...console.exe"` snapshot is not enough
   evidence on its own -- it can't distinguish a genuinely separate second agent's
   process from (a) a parent/child console+engine pair from ONE process (misread as
   "two"), or (b) a brief gap between SEQUENTIAL Godot sub-invocations within a
   single `check.sh` script (validate exits, then test/coverage starts fresh a few
   minutes later -- misread as "the whole script finished" when only one phase
   did). Both misreads happened in this session, in both directions -- once
   trusting a stale "cleared" signal too early, once nearly discarding a
   perfectly good result because of a wrong-time check.
2. **The decisive tool is `Get-CimInstance Win32_Process -Filter "Name LIKE
   '%Godot%'" | Select ProcessId, ParentProcessId, CreationDate, CommandLine`**
   (not plain `tasklist`, not `Get-Process`) -- it gives the parent/child
   relationship (rules out the console/engine misread) and the exact
   `CreationDate` (lets you correlate a PID pair against a specific agent's own
   push/commit timestamp instead of guessing from clustering).
3. **A subagent that already has a background check running should verify the
   claim independently before acting on an orchestrator's "it's clear, go
   ahead" or "it collided, stop" message** -- in both directions. One subagent
   caught the orchestrator's premature "exited" signal by re-querying itself
   and correctly kept waiting; another caught a genuinely-overlapping process
   the orchestrator had missed. Neither blindly trusted the other party's
   claim, and that's what actually prevented a THIRD contaminated run.
4. **A run that genuinely overlapped with another process is not automatically
   worthless** -- check the actual OUTPUT for internal coherence (specific
   line-numbers/counts tied to files the diff actually touches; a real GDScript
   parse error or garbled/nonsensical numbers is the actual contamination tell,
   e.g. scrambled keybinding values) before discarding a result just because
   the timing was bad. The documented corruption failure mode (shared
   `settings.cfg` keybinding scramble, a coverage report reflecting a stale
   test set) is specific and detectable; a coherent, diff-relevant result that
   merely ran during an overlap window is not automatically suspect.
5. **Killing a stray/colliding process is a destructive action the harness's
   own permission classifier blocks** (`Stop-Process`/`taskkill`, from either
   the orchestrator or a subagent) -- don't try to work around that block.
   Prevention (serialize launches) is the only real lever available; cleanup
   after the fact requires waiting the process out, not killing it.

**How to apply, as an orchestrator dispatching 2+ Godot-touching agents:**
never assume worktree isolation is sufficient and let them self-serialize by
individually checking `tasklist` -- that's exactly the mechanism that produced
both misreads above. Instead, actively coordinate turns yourself: hold every
agent but one, verify with `Get-CimInstance` (not `tasklist`) that the machine
is genuinely clear, release exactly one agent, wait for ITS OWN completion
report (not an external process-exit guess, which is unreliable across a
multi-phase script), then release the next. The lesson from this session
isn't "check less" -- both agents' own diligence in re-verifying rather than
blindly trusting a claim is what actually avoided a third wasted run -- it's
"check with the right tool, at the moment closest to the actual action, and
let each party verify independently rather than trust-and-proceed."
(`Lacaedemon/sparta`, GII+mwc session, 2026-07-19/20, PRs #1020/#1024.)

## A new per-soldier render-easing value needs its OWN trigger in `_process`'s refresh gate, not just the existing ones

When adding a new eased (never-snap) per-soldier render value -- mirroring the
existing `_render_alpha`/`ROUTING_ALPHA` idiom -- don't assume the existing
`Unit._process()` refresh gate (`_render_dirty or facing changed or state ==
FIGHTING or instance-count drift`) will keep calling `_refresh_flock_render`
often enough for the NEW value to finish easing. Those four conditions are
tuned for what they already cover (body movement, turning, combat, casualty
compaction) and have no reason to correlate with an unrelated timer's own
decay.

**Concrete case:** the prone-soldier render fix (`_render_prone_progress`,
easing a soldier's fallen-pose transform/tint instead of snapping) initially
relied on those four existing conditions alone. `_render_dirty` is set ONLY
when a soldier body's velocity exceeds `SoldierBodies.REST_SPEED` -- a
knockback's initial impulse sets it (so the ease correctly *starts*), but the
body settles to near-zero velocity well before `_render_prone_progress`
finishes converging, and once the unit's own `state` drops out of `FIGHTING`
(immediate, no linger) none of the four conditions fire again. Result: the
ease froze mid-transition -- a soldier permanently stuck half-fallen/half-risen
-- which is a WORSE visible defect than the original instant-snap bug the fix
set out to solve. This is the same "inert number" failure class as the
`_current_speed`/coasting bugs above, just on a different field. Caught by
`claude-review`, not by the original implementation or its own tests (which
called `_refresh_flock_render` directly, bypassing `_process`'s gate entirely,
so the frozen-forever path was never exercised).

**Fix pattern:** add a dedicated boolean (`_prone_easing_active`) set by the
easing function's OWN per-soldier loop (`still_easing = true` whenever
`progress != target` for any soldier), read as an additional OR-condition in
`_process`'s gate. `move_toward` clamps exactly to the target once within
range, so the flag reliably goes false on convergence -- no risk of getting
stuck true from float drift.

**Test gotcha this surfaced:** a test that exercises the easing function
directly (`u._refresh_flock_render(delta)` in a loop) proves the MATH is
right but does NOT prove `_process` actually keeps calling it -- write a
second test that drives the fix through `_process` itself with every OTHER
gate condition deliberately held inactive (state != FIGHTING, `_render_dirty`
false, no facing change, no instance-count drift), so the new trigger is the
only thing making it advance. And when staging that test, remember the
kickoff itself needs a real trigger too: directly setting the underlying sim
field (`_sim_prone[i] = 1.0`) with no accompanying `_render_dirty`/velocity
pulse never starts the ease in the first place (in real play, a knockback's
own velocity always provides that first kick) -- call the easing function
once directly to simulate that one real-world kickoff tick, THEN loop
`_process` alone to prove the *continuation* works with nothing else active.
(`Lacaedemon/sparta` PR #1054, 2026-07-23.)

## Grep your OWN new comments for issue-number citations before every commit, not just after `check.sh` catches it

CLAUDE.md's "Comments: no issue-number references" rule is well-documented,
but self-checking against it is easy to skip when writing a fix's own
explanatory comments (especially ones that narrate *why* a bug happened,
which naturally wants to reference "the issue this fixes"). In one session,
`tools/check.sh comments` caught this same self-inflicted mistake three
separate times across three different PRs (#1051, #1053, #1054) -- each
time costing a full extra `check.sh` cycle (15-20 min for the coverage-
instrumented suite) purely to re-discover something a 5-second grep would
have caught immediately after writing the comment.

**How to apply:** after writing any new/edited comment block explaining a
fix's root cause (the kind of comment most likely to want to say "this is
what issue #N was about"), grep the diff yourself before committing:
`git diff --cached | grep -E '^\+.*#[0-9]{2,4}\b'` (or just re-read what you
wrote with this rule specifically in mind) -- don't rely on `check.sh`'s
`comments` check to be the first line of defense; treat it as the last-resort
safety net, not the primary catch.

## `gh pr merge --delete-branch` failing locally with "'main' is already checked out" is benign in a session worktree -- the merge itself still lands

`gh pr merge <N> --squash --delete-branch`, run from a session worktree (not
the primary checkout), can fail with `failed to run git: fatal: 'main' is
already checked out at '<primary-checkout-path>'` -- this is `gh`'s own
post-merge convenience step trying to switch the LOCAL checkout to `main`
(exactly the hazard this file's own "never checkout main in a worktree"
entries already warn about), not a failure of the merge itself. The remote
merge (and `--delete-branch`'s remote branch deletion) completes before that
local step runs, so it always succeeds regardless of the error message.

**How to apply:** after seeing this error, don't retry or investigate the
merge -- just verify directly (`gh pr view <N> --json state,mergedAt`, and
the closing issue's `state`/`stateReason`) and proceed to the normal
post-merge tidy (`git fetch origin --prune`; don't touch the local `main`
branch in this worktree at all, matching the existing convention of never
checking it out here). Hit twice in one session (PRs #1051 and #1054,
2026-07-23), both simple confirms-and-moves-on once checked.

## A "PR Status Report" review reply can be a stub in disguise -- restating old context instead of independently re-checking the current diff

Adds a specific symptom to the existing stub-review family already
documented above: a re-review triggered right after a fix push can come back
formatted as a "PR State / Is Draft / Prior Claude Review" status summary --
quoting the EARLIER finding and the author's OWN follow-up commit message
almost verbatim -- rather than an independent line-by-line re-check of
whether the fix actually resolves the finding. It still carries a
plausible-looking structure and doesn't obviously read as empty the way
"Test content line." does, so it's easy to mistake for a genuine re-verdict
at a glance.

**How to apply:** when a review reply mostly restates PR metadata/history
you already know (title, description, "yes it was reviewed before, here's
what happened") rather than tracing the specific code change against the
specific finding, treat it the same as any other stub: don't accept its
implicit "looks fine" as a verdict. One manual re-dispatch
(`gh workflow run claude-code-review.yml -f pr_number=<N>`) is usually
enough to get a genuine fresh pass that explicitly traces the fix (verified:
the second dispatch on the same PR produced a real line-by-line
verification and an explicit `### Verdict`). (`Lacaedemon/sparta` PR #1054,
2026-07-23.)

## A Control anchored to a corner with a KNOWN fixed size should set explicit offsets, not `.position=`

`scripts/HUD.gd`'s own `_settings_panel_raise()` doc comment (renamed from
`_info_panel_raise()` by the same PR this entry describes) documents that
`.position=` on an anchored Control "just works" ONLY because it's set once
during `_ready()`, before the CanvasLayer's real viewport size is
established (so `anchor * parent_size == 0` at that moment) -- and warns that
calling it again later, once the real size is baked in, silently shoves the
Control far off-screen. There's a SECOND, distinct trap in the same
territory: setting `.position=` once at `_ready()` time, then ALSO setting
`custom_minimum_size` on the same Control right after, for a corner anchor
where BOTH the width and height are already known up front (not
content-derived).

**Concrete case:** moving the unit card tray from center-bottom to
bottom-right (#1049), the new build code mirrored the `_ctrl_bar`/
`_legend_panel` pattern -- `set_anchors_preset(PRESET_BOTTOM_RIGHT)`, then
`.position = Vector2(-14, -14)`, then `custom_minimum_size = Vector2(500,
0)` -- and the tray ended up rendering almost entirely OFF the right edge of
the screen, with only a ~15-20px sliver visible; confirmed via a direct
screenshot, not caught by any unit test (GUT's headless dummy renderer
never surfaces a rendered-position bug like this -- see the "How to apply"
note below). The `_ctrl_bar`/`_legend_panel` precedent this pattern
was copied from never sets an explicit `custom_minimum_size` on the
anchored Control ITSELF (only on a child, or not at all) -- they rely
entirely on the Control's own natural content size, which `.position=`'s
"resolve against size-0-at-_ready()-time" trick tolerates because there's
no OTHER competing size assignment landing after it.

**Fix:** for a corner-anchored Control whose full size is known up front
(a fixed-width tray, a fixed-size panel), set `offset_left`/`offset_right`/
`offset_top`/`offset_bottom` explicitly instead of `.position=` +
`custom_minimum_size` -- exactly the pattern the settings/info panels
already use elsewhere in `HUD.gd`. Explicit offsets are unambiguous
regardless of assignment order or when the CanvasLayer's real viewport size
becomes available; `.position=` is only safe when nothing else touches the
Control's size afterward.

**How to apply:** before copying the `.position=`-based corner-anchor
pattern to a NEW Control, check whether that Control also needs an
explicit `custom_minimum_size` (or any other size-affecting property) set
after the position -- if so, use explicit offsets instead. And always
confirm a new/moved HUD panel's ACTUAL on-screen position with a real
screenshot (a throwaway tool scene + `--rendering-driver opengl3`, per
"Throwaway tool-scene screenshots" in `.claude/skills/sparta-demos/SKILL.md`) before considering
a layout change done -- a GUT test asserting anchor/grow-direction
properties (as `test_hud_layout.gd` does) proves the CONFIGURATION is
correct but says nothing about where the Control actually renders.
(`Lacaedemon/sparta` PR #1057, 2026-07-23.)

## When moving a HUD panel to a new corner, re-check its collision footprint against EVERY other panel, not just the one obvious neighbor

Rearranging where panels sit (#1049: distance legend, info panel, settings
panel, and unit tray each moved to a different screen margin) can introduce
TWO independent kinds of new collision that are easy to miss by only
reasoning about the panel you're actively moving:

- **A panel you moved now shares a corner with something that was already
  there.** Moving the distance legend to top-left put it directly on top of
  the frame-rate counter's DEFAULT corner (`Settings.fps_corner` defaults to
  `FPS_CORNER_TOP_LEFT`, chosen specifically because nothing else lived
  there -- a comment in `Settings.gd` said so explicitly, and went stale the
  moment the legend moved in without anyone updating it). This wasn't the
  legend's own move breaking something about ITSELF -- it broke a completely
  different, unrelated feature's implicit assumption about that corner
  being free.
- **A panel's own growth/reach calculation doesn't account for a NEW
  neighbor sharing its column/row.** The info panel's `grow_vertical =
  GROW_DIRECTION_BOTH` symmetric-growth budget (`_info_panel_available_height()`)
  was computed purely against the raw screen edges, with no reference to
  the settings panel (bottom-left) or legend (top-left) now sharing its
  same `offset_left = 14.0` column. A tall enough stat sheet could grow
  down into the settings panel or up into the legend -- confirmed
  mathematically (not just eyeballed) by an existing test that already
  exercised a 200-line stat sheet pinning to the (wrong) 680px ceiling.
  Fixed by having the growth-budget function actively query each
  sibling's live footprint (`_legend_panel.position.y +
  get_combined_minimum_size().y`, `_settings_panel.get_combined_minimum_size().y
  + _ctrl_bar_clearance()`) rather than a screen-edges-only constant.
  A similar tray-vs-control-bar collision (the control bar reaches far
  enough from screen center at the default 1280px width to overlap the
  bottom-right tray) was ALSO found this same way -- by direct screenshot,
  not by reasoning about the numbers ahead of time.

**How to apply:** after any HUD panel reposition, don't just verify the
moved panel's own rect looks right -- grep the file for every OTHER
Settings-driven or dynamically-sized element (default corners, growth
budgets, raise/lower clearances) and ask whether it implicitly assumed the
old layout. A real before/after screenshot (not just a description of the
intended positions) is what actually catches these -- both collisions in
this PR were found by a human/reviewer looking at an actual rendered frame,
not by static code review of the anchor math. (`Lacaedemon/sparta` PR
#1057, 2026-07-23.)

## A throwaway (non-GUT) Godot process also contaminates the real `settings.cfg` -- not just GUT test runs

The existing "Settings.gd setters persist to the REAL user://settings.cfg
in tests" entry above covers GUT test runs calling a `Settings.*` setter.
The SAME contamination happens from a throwaway tool-scene script (`godot
--rendering-driver opengl3 res://tools/demo/_shot_*.tscn`, per the
screenshot-capture recipe) that directly sets `Settings.show_unit_card_tray
= true` (or any other setter) to force a UI element visible for a
screenshot -- it's a REAL game process, not a sandboxed test run, so the
setter's own `_save()` call writes straight to the actual
`user://settings.cfg` on disk, exactly like a real play session would.

This bit silently: a `show_unit_card_tray defaults to false` GUT test
started failing in a LATER, unrelated check.sh run, with no connection
visible in the test's own diff -- root-caused only by remembering an
earlier screenshot-capture step in the SAME session had set that setting
directly. (`Lacaedemon/sparta` PR #1057, 2026-07-23.)

**How to apply:** after running ANY throwaway tool scene that touches
`Settings.*` (directly, or indirectly via a UI interaction the scene
simulates) for a screenshot or manual verification, delete
`user://settings.cfg` (path is machine-specific -- see the "shared ACROSS
worktrees" entries above for how to find it) before trusting the NEXT
`tools/check.sh test`/`patch_coverage` run's results, or diff the file's
`show_*`/`tray_row_order_placement`/etc. values against known defaults
first. Prefer avoiding the setter path entirely when the scene doesn't
need real persistence: mutate whichever downstream field the setter would
have set instead (e.g. call `hud._sync_unit_card_tray_visibility()` after
setting `Settings.show_unit_card_tray` inside `Settings._loading = true` /
`= false` guards, matching the pattern `test_hud_unit_card_tray.gd`
already uses to force a known starting state without persisting it).

## A two-pass same-seed determinism test needs the tree PAUSED across `add_child`, or the two passes start one body-step out of phase

A GUT test that instantiates `scenes/Battle.tscn` **twice** with the identical
seed/scenario (to prove the sim is deterministic -- no leaked global static,
no stray RNG draw) can still see the two passes' per-tick state diverge by a
sub-pixel amount at the same tick number, even with every known global sim
static (`PathField.active`, `SoldierEnemyProximity`, etc.) correctly reset
between passes. The cause isn't a leaked static at all: whether
`_on_soldier_tick` (which steps the soldier bodies) fires on the SAME frame
as the first `_physics_process` call (which advances `_tick`) is a startup
phase race against the engine's own node-ready scheduling -- so one pass can
get a body-step and a tick-increment on the same frame while the other gets
them a frame apart, leaving the two passes permanently one body-step out of
sync relative to `_tick` even though both started from byte-identical state.

**Fix:** pause the tree, `add_child(_battle)`, await one `physics_frame` (the
armies spawn; nothing steps while paused -- `_physics_process` doesn't run at
all under pause, and the soldier tick early-returns), then unpause:

```gdscript
get_tree().paused = true
add_child(_battle)
await get_tree().physics_frame   # spawn the armies; nothing steps while paused
get_tree().paused = false
```

This gives both passes a single shared start line -- the unpause, not
whatever frame `add_child` happened to land on -- so the tick-increment and
body-step both begin in lockstep in both passes. Apply this any time a test
needs two (or more) `Battle` instances, run sequentially or otherwise, to
produce genuinely comparable per-tick state -- not just the lockstep A/B
sim-hash instrument this was found for, but any future test built the same
way. (`Lacaedemon/sparta` PR #1068 / issue #1067, 2026-07-24: diagnosed with
a throwaway per-unit diagnostic comparing body-step counts against `_tick`
across the two passes, not guessed.)

## Formation slot assignment is by ARRAY INDEX -- a recurring bug family, not a one-off

`UnitFormation.block_slots` maps soldier index `i` to grid cell `i` (`file = i % files`,
`rank = i / files`). Nothing in the reform path solves an assignment problem: there is no
nearest-slot pairing, no angular pairing, no minimum-travel matching anywhere. So any
reshape that changes `files` reassigns most soldiers to distant cells, and they walk there
under the normal bounded-arrival body steering -- physically correct motion toward a
geometrically arbitrary destination.

This has now produced the same visible defect four separate times. The first three were
each diagnosed and fixed only for their own maneuver; the fourth is still open: #541 (about-face swapped soldier identities, 0/40 held
position), #668 (countermarch reform swapped soldiers to the opposite flank rather than
just reversing rank order), #802 (target-slot reassignment cadence), and #1146 (the
NORMAL -> SQUARE reform: 28% of soldiers cross the centreline, mean travel 33.8 wu, about
2x the greedy-nearest-slot optimum, on a block only 90 wu wide once squared).

**Before assuming a given reshape is safe, check whether its path has its own pairing
logic or falls through to raw index order.** `Unit.formation_slots()` is the dispatcher.
The square branch is bare `block_slots(...)`. The file-major branch preserves a persistent
per-soldier file (`_sim_soldier_file`), which is the one real identity-preserving
mechanism in the file -- and it is deliberately OFF for squares, on the stated grounds
that `formation_files()` recomputes continuously as casualties shrink the live count so
there is no stable file to preserve. That rationale is sound for CASUALTY REFLOW and does
not transfer to a DELIBERATE RESHAPE, which is a discrete one-off event where a pairing
could be computed once and held. Don't let the docstring's reasoning talk you out of
checking the reshape case.

The right primitive already exists unused for this purpose:
`UnitFormation.sort_indices_by_angle()` pairs soldiers to ring slots by angle about the
centroid, described in its own docstring as lining up "each live defender with the ring
slot nearest its own actual side of the block" -- currently wired only into engaged-soldier
selection, not into any reform's slot assignment. #547 (explicit per-soldier slot
ownership) would subsume the whole family.

Verification technique for any fix here is the per-index, local-frame comparison described
under "The identity checks are real, but they are blind DURING a reshape" in
`.claude/skills/sparta-demos/SKILL.md`. The scan's identity metrics do exist and work, but they only judge a
SETTLED block -- and every one of these bugs reaches a correct end state by a wrong route,
which is why all four instances were caught by eye rather than by a check.

## One selector, two questions: reach answers "who can strike", geometry answers "whose body is shoved"

`Unit.engaged_soldier_indices()` derives its depth from `engaged_ranks()`, which scales with
the regiment's own WEAPON REACH. That is the correct answer to the question it exists for --
a spear phalanx really does project six ranks of points into contact, and all six deal and
take blows. It is the wrong answer to a question about BODIES, and reusing it for one is a
recurring trap: a sixth-rank spearman strikes past five ranks of his own men without anything
touching him.

The failure only becomes visible when a block is SHALLOWER THAN ITS OWN REACH DEPTH. A 40-man,
9-file spear regiment is 5 ranks deep against an engaged depth of 6, so every soldier lands in
the tier and any "the rest of the block is the unengaged bulk" assumption silently evaporates.
`SoldierBodies.step()` had exactly that assumption baked in -- an engaged body drops the march
feed-forward and is re-paired onto a canonical target slot, both meaningful only RELATIVE to a
bulk still tracking the formation's own slots. With no bulk left, every body free-floats under
continuous contact impulses while its slot identity is globally re-sorted by lateral position,
so rank/file order churns indefinitely instead of recovering (soldiers visibly sliding sideways
through a sustained melee).

Fixed by `body_tier_soldier_indices()` / `body_tier_ranks()`: same gate, same geometry, but
depth = how many ranks one body DIAMETER spans at this formation's own rank pitch (1 at the
standard 0.45 m pitch; 2 for SHIELD_WALL/TESTUDO, which compress below a body width; 1 for
cavalry's roomy 3.0 m pitch). Derived from constants the soldier layer already scales off, so
no tuned number.

**How to apply:** before consuming `engaged_soldier_indices()` in a NEW caller, ask which
question that caller is really asking. If it is about physical contact, crowding, or body
motion -- not about who can land a blow -- it wants a geometry-derived depth, and it needs its
own selector. This is the same class of bug PR #1137 fixed one layer over (a combat selector,
`is_engaged()`, silently gating physical collision), so it has now bitten twice; expect a third
site. Note also that two tuned alternatives were tried and rejected on measurement first --
"leave one rear rank as bulk" barely moved the churn, and "cap at half the block depth" fixed
one unit but not the other -- only the geometry derivation landed symmetrically.

## Capping a selection must narrow WITHIN the meaningful candidate set, never re-select over the whole population

When adding a size cap to a selection that already computed a MEANINGFUL candidate set, apply
the cap to that set. Falling back to a fresh ranking over the whole population is a different
answer, not a smaller one.

Concretely: `Unit._select_near_front_indices()`'s Square/Schiltron branch computes `threatened`
(soldiers with an enemy actually in reach). A first cut handled the capped case by falling
through to `UnitFormation.live_perimeter_indices()`, which ranks purely by distance from the
block's own centroid -- i.e. the corners -- with no reference to enemy position at all. For a
pressed square that is the ORDINARY case, not an edge case (a 100-soldier square caps around
`ceil(sqrt(100)) = 10` while a one-sided press typically threatens 30-40), and it returns
soldiers with nothing near them while dropping soldiers genuinely in contact -- inverting the
selection's own meaning and breaking the body-tier subset engaged-tier invariant.

Fixed with `UnitFormation.most_exposed_among(positions, candidates, target_count)`: ranks by
exposure WITHIN the candidate set, centroid still taken over the whole block (the subset filters
who may be picked, it does not move the middle). `live_perimeter_indices` delegates to it, so
there is one heap selection rather than two copies.

**How to apply:** any time a bounded and unbounded caller share a selection function, check that
the bounded path returns a SUBSET of what the unbounded path would. If it can return something
the unbounded path would never return, the cap is re-selecting rather than narrowing. Caught by
review, not by the implementation or its first test -- see the vacuous-test entry below for why
that test did not catch it either.

## A guard test can be vacuous ONLY under full-suite ordering -- single-test runs can hide it

The standing habit of reverting a fix to prove its test bites has a failure mode worth naming:
the test can fail correctly in a SINGLE-TEST run and still pass in a FULL-SUITE run, because a
frame-keyed static cache served it another test's data. So "I reverted and it failed" is not
sufficient evidence unless the revert was run the same way CI runs it.

Concretely: a new test for the square capping path above passed against the reverted fix in a
full `test_unit.gd` run, while failing correctly when selected alone. Root cause was the already
documented hazard above -- `SoldierEnemyProximity` is keyed by `Engine.get_physics_frames()`, so
a synchronous test inherits whatever grid the previous test built, and the enemy this test
staged was never in it, leaving `threatened` empty and the capped branch unreached. Adding
`SoldierEnemyProximity.reset()` made it fail against the bug in BOTH modes (4 failures, indices
33/43/44/54, matching an independent probe's prediction of exactly 4 leaked soldiers).

**How to apply:** run the revert check the way CI runs the suite, not just with `-gunit_test_name`.
A guard that only bites in isolation is not a guard. Also add a positive sanity assertion that the
branch under test is genuinely reached (here `assert_gt(melee.size(), u.body_tier_cap(n))`), so the
test cannot quietly go vacuous later when geometry or constants shift. Note this hazard's own
`reset()` rule was ALREADY documented in this file and still got missed while writing a fresh
test -- treat "does this test construct fixtures that a frame-keyed cache reads?" as a checklist
item on every new test, not a thing to recall.

