## Routing units early-return in `_physics_process` -- merge-isolated

In `scripts/Unit.gd`, `_physics_process` takes an **early return** for a routing
unit:

```gdscript
if state == State.ROUTING:
    _process_rout(delta)
    if state != State.DEAD:   # timer expired: rallied (IDLE) or shattered
        _separate()           # routers still shoulder past anyone in their path
    return
```

Routers run only `_process_rout` + `_separate` and skip the entire normal path:
`_think`, `_tick_intermixing`, morale/fatigue/cohesion ticks, and all the
movement/re-facing/formation logic below the return.

**Merge implication.** When resyncing the routing/rally branch (#460, #434)
against a `main` that landed new movement features -- engage/attack re-facing
(#402/#476), file doubling (#373), anti-cav square (#487), shielded close order
(#485) -- git auto-merged `Unit.gd`/`Battle.gd` cleanly, and the auto-merge was
**also semantically correct**: those features all live in the `_think`/movement
path routers never reach, so they can't interact with rout/rally state.

General rule: a state that early-returns from `_physics_process` (ROUTING, DEAD)
is isolated from any feature added to the normal think/movement path, so a clean
git auto-merge of the two branches is usually clean semantically too. Still run
the full suite (`tools/check.sh test`) to confirm -- that's the real signal.

## `_check_victory` counts routers in play (last-unit rally)

`scripts/Battle.gd`'s victory check no longer counts only fightable units.
PR #495 (closes #493) replaced the `_team_units(0).size()` /
`_team_units(1).size()` counts in `_check_victory()` with a boolean helper:

```gdscript
func _team_in_play(team: int) -> bool:
    for group in ["units", "routers"]:
        for node in get_tree().get_nodes_in_group(group):
            var u = node as UnitRef
            if u != null and u.team == team:
                return true
    return false
```

`_check_victory()` ends the battle only when `not _team_in_play(0)` /
`not _team_in_play(1)`. A **routing** unit has left the `"units"` group for
`"routers"` (`Unit._rout()` → `add_to_group("routers")`) but is still on the
field and may rally, so it keeps its team **in play**. Before #495, losing the
last fightable unit ended the battle instantly and froze the router mid-rout.

- **The rally window is bounded**, so waiting on routers can't stall the outcome:
  each rout resolves (rally→IDLE or shatter→removed) within `ROUT_TIME`.
- **No AI change was needed.** The enemy AI advances on `_team_units(0)` (the
  `"units"` group only), so it already halts when the last player unit routs --
  don't add a separate "halt" hook.
- **Known gap, tracked in #504:** `_report_campaign_result()` still counts
  survivors with `_team_units(0).size()`, which EXCLUDES still-routing units.
  Pre-existing. If you touch campaign accuracy, reuse `_team_in_play` /
  union `"units"`+`"routers"` there too.

## Render-only cosmetic overlay pattern

**Superseded for the shield-wall/testudo/square case by #753:** the owner
decided the schematic overlay this pattern originally shipped
(`scripts/UnitShields.gd`, added by #486/#487/#623) was the wrong call for
those stances specifically -- since #534 already restructures the real
soldier-block geometry per formation (a tight edge-to-edge grid for shield
wall/testudo, a real outward-facing square for orbis/schiltron), drawing a
second schematic on top duplicated what the physical soldier positions
already show, in tension with the "no top-down gimmicks" philosophy at the
top of this file. #753 removed `UnitShields.gd` and its call site entirely;
these formations are now read purely from the soldiers' own positions. The
pattern below is kept as a still-valid recipe for a genuinely different
future case (an effect the soldier positions truly can't convey on their
own), not as a template to reach for reflexively -- check whether the real
per-soldier geometry already tells the story before adding a schematic
overlay on top of it.

When a PR is purely **"show an existing sim state on screen"** that the
soldiers' own positions can't already convey, build it as a **render-only
overlay** so it never touches sim/combat/formation code and stays
conflict-free with the many in-flight PRs that DO touch that code.

**The pattern (mirrors `UnitSprites` / the emblem/flag chrome):**

1. **Pure geometry helper** in its own `class_name` script (e.g. the former
   `scripts/UnitShields.gd`, removed by #753 -- see the pattern in
   `scripts/UnitSprites.gd` instead for a still-live example). Static funcs taking plain shape inputs
   (frontage/ranks/spacing/mark_r) returning local-frame polygons -- a function of
   block shape ONLY, nothing reads or writes the sim. Directly unit-testable and
   replay-safe. Keep block geometry consistent with the formation grid:
   half-width `= (files-1)/2 * spacing`, half-depth `= (ranks-1)/2 * spacing`,
   front rank toward **-Y** (local forward), files span X -- same frame
   `UnitFormation.slots` / the emblem use.
2. **A `draw(u, body, dark, lite)` dispatcher** that switches on the state
   (`u.formation_mode`) and is a **no-op** for every other value.
3. **`Unit._draw` calls it** inside a `draw_set_transform(Vector2.ZERO,
   facing.angle() + PI*0.5, Vector2.ONE)` … reset sandwich, so the overlay
   **rotates with facing and scales with the block** for free. Size off the live
   formation shape (`UnitFormation.frontage` / `ranks_for`), not the bare
   `RADIUS`. Use the team-tinted `body_c/dark_c/lite_c` already computed in
   `_draw`.

**LOD decision -- differs from the emblem.** The centre emblem hides at figure LOD
(`if not _detailed_lod`) because the per-soldier silhouettes carry the type. A
shield overlay does the OPPOSITE: draw it at BOTH mark and figure LOD, because
the raised/overhead shields are exactly what the individual figures don't show.
Put the overlay OUTSIDE the `if not _detailed_lod` guard and note why.

**Coverage gotcha.** The pure geometry helpers get covered by GUT tests, but the
draw-only `draw()` / `_draw_*` funcs don't -- `codecov/patch` fails on them.
Calling `unit._draw()` directly from a test errors ("Drawing is only allowed
inside this node's `_draw()`"). Instead drive it the way the engine does: add the
unit to the tree, set the stance, `queue_redraw()`, and
`await get_tree().process_frame` twice -- that runs `_draw` under the real draw
notification and covers the dispatch.

## `record-demos.sh` DEMOS conflicts are ADDITIVE -- keep both rows

`website/tools/record-demos.sh` holds a `DEMOS=( ... )` bash array, one row per
demo clip. Every feature PR that adds a website demo appends a new row at the end.
When two such PRs land, git conflicts on the adjacent lines:

```
<<<<<<< HEAD
  "rout_rally|demos/inputs/rout-rally-recover.json|30|300|640|input"
=======
  "testudo_under_fire|demos/inputs/testudo-under-fire.json|30|300|640|input"
>>>>>>> origin/main
```

This is an **additive** conflict, not a genuine either/or. Resolve by keeping
**both** rows -- each PR's demo should survive. Don't pick a side.

Distinct from the `demos/demo.json` conflict (below / CLAUDE.md), where you keep
only YOUR PR's version because that file names the single clip CI posts for the
PR in hand. `record-demos.sh` is the persistent website catalog, so both entries
stay.

## `website/tactics.qmd` same-mechanic conflicts are a DEDUP, not additive

`website/tactics.qmd` (and `how-to-play.qmd`) conflicts differ from the
`record-demos.sh` additive case above. When two PRs document the **same mechanic**
from different angles, git shows a big block conflict, but the right resolution is
a **semantic dedup**, not "keep both sides".

Concrete case (PR #495 last-unit-rally vs main's #460 rout-rally): both rewrote
the "Morale & routing" section and each added rally prose + a demo video.
Resolution that worked:

- **Intro paragraph** -- keep the richer of the two, drop the thinner one.
- **Bullets** -- keep the general-mechanic bullets ("A routing unit can rally" /
  "shatters instead"), DROP your own now-redundant duplicate of that same
  explanation, and KEEP only your PR's *unique* angle (the last-unit case: "the
  battle isn't over while a side is only routing").
- **Demo videos** -- this IS additive: keep BOTH `<figure>` blocks (general
  mechanic first, then the specific case), each in its own ` ```{=html} ` fence.

Rule of thumb: two docs describing the same feature → merge into one coherent
narrative (general mechanic once, then each PR's distinct implication); two *media
embeds* → keep both. Read the merged section end-to-end afterward to confirm it
doesn't say the same thing twice. `&mdash;` in figcaptions is an HTML entity, so
it passes `tools/check.sh chars` (only literal curly quotes / en-em dashes fail).

## This repo runs sessions in `.claude/worktrees/` -- edit the worktree path

A Sparta session's working dir is often a git **worktree**
(`…\sparta\.claude\worktrees\<name>`), separate from the main checkout
(`…\sparta`). A feature branch created in the worktree is checked out **there**,
while the main checkout stays on `main`.

**Hazard (easy to hit twice):** Read/Edit/Write using the *main-checkout*
absolute path (`…\sparta\scripts\…`) edits files on the `main` branch, NOT the
worktree's feature branch. Then tests run from the worktree silently see none of
the changes (a new test file isn't discovered; `git status` in the worktree is
clean while the main checkout shows the edits).

**How to apply:**
- Do **all** file operations on the **worktree path**
  (`…\.claude\worktrees\<name>\…`), matching where the branch is checked out.
  Bash cwd already resets to the worktree -- keep tool paths consistent with it.
- If edits don't seem to take effect, run `git status --short` in **both** the
  worktree and the main checkout to find where they landed.
- To move stray edits from the main checkout onto the worktree branch:
  `git stash push -u` in the main checkout, then `git stash pop` in the worktree
  (the stash is shared via the common `.git`). `-u` includes untracked files.
- **`gh` commands are cwd-sensitive the same way.** Running `gh pr create` from
  the main checkout (on `main`) fails with `must be on a branch named differently
  than "main"`, even though the feature branch is pushed -- `gh` reads the current
  directory's checked-out branch. Run `gh pr create` (and branch-scoped
  `git push`) from the **worktree** dir.

**A second, distinct hazard: reusing a PR branch name for a NEW worktree when a
`wave5-*`-style dispatch worktree already has it checked out.** This repo's
wave-based backlog sweeps leave many named worktrees behind
(`.claude/worktrees/wave5-<slug>`), each tracking one PR's branch -- they don't
get cleaned up until the PR merges and someone runs a sweep. If a later task
(e.g. resolving a fresh merge conflict on that same PR) creates a *second*
worktree for the same branch instead of reusing the existing one, git can
silently repoint the shared branch ref out from under the first worktree
rather than refusing outright -- the first worktree then shows a wall of
spurious modified/deleted files (not real data loss, just its checked-out
files diffing against the ref's new tip). Always `git worktree list | grep
<branch>` before adding a new worktree for a PR branch; if one already exists,
reuse it (`git fetch` + `git reset --hard origin/<branch>`) rather than adding
a second on the same name.

**Recovery if it already happened:** the first worktree's checked-out files are
not lost -- they're just diffing against the branch ref's new tip. Don't try to
merge or reconcile the two worktrees' contents. Pick the worktree that actually
has the commit you want to keep, confirm it with `git log --oneline -1` in
each, then `git worktree remove` the stale one and `git fetch` + `git reset
--hard origin/<branch>` in the survivor so both git's ref and the working tree
agree again. (Hit on PR #626, 2026-07-03.)

**A third, distinct hazard: the assigned `.claude/worktrees/<name>` directory
can look like a worktree without actually being one.** The section above
assumes the session's working directory is a genuine `git worktree` -- but a
harness-assigned path under `.claude/worktrees/` isn't guaranteed to have had
`git worktree add` actually run for it. Symptom: the directory has **no
`.git`** file/folder of its own, and it's **absent from `git worktree list`**
run from the main checkout -- every `git` command issued from inside it just
walks up the directory tree and finds the main checkout's `.git`, so it's
silently operating on the SAME shared repository as the main checkout and
every *other* branch checked out there, not an isolated copy.

**Why this is dangerous, concretely:** checking out a second branch from
inside this fake "worktree" (`git checkout -b other-branch origin/main`)
switches the ONE shared checkout's active branch -- it does not create an
independent working tree. Any other work in flight on the branch that was
previously checked out (your own later commands, or a delegated subagent
mid-task) silently has its working-directory files yanked out from under it.
The subagent doesn't error -- it just ends up running against whatever branch
is now checked out, which can be a completely different (even pre-refactor)
version of the code, and the resulting output can look plausible without
being about the branch it was asked to investigate.

**How to apply:**
- Before checking out a second branch or delegating a subagent to do file/git
  work, verify the working directory is real: check for a `.git` entry
  (`ls -la .git`) and cross-check `git worktree list` from the main checkout
  path -- the assigned directory should appear in that list. If it's absent
  and has no `.git`, treat it as a plain subdirectory of the main checkout,
  not an isolated worktree.
- If it's fake and you need to work on more than one branch concurrently
  (e.g. driving several PRs at once, or delegating parallel implementation
  agents), create genuine isolated worktrees yourself:
  `git worktree add .claude/worktrees/<slug> -b <branch> origin/main` (or
  point at an existing remote branch instead of `-b` + `origin/main` to
  continue one). Do this from whichever path IS the real main checkout.
- Only ever have ONE branch checked out at a time in a fake/shared path. If
  you must switch, finish and push (or stash) whatever's in flight there
  first -- don't assume "it's just a directory switch" is harmless.
- A subagent given a directory to work in has no way to know it's fake unless
  told to check -- if you suspect this hazard might be live (concurrent
  branch work in the same session), tell the subagent explicitly to verify
  its own working directory is a real worktree before trusting its output, or
  give it a directory you've already confirmed with `git worktree add`
  yourself. (Hit on PR #831, 2026-07-13: `.claude/worktrees/gii-ffdb93` -- the
  session's assigned directory -- had no `.git` and didn't appear in `git
  worktree list`; checking out a second branch there for a concurrent PR
  silently switched the one shared checkout away from PR #831's branch mid-
  investigation by a delegated subagent, which only caught the problem
  itself by noticing `scripts/Order.gd` was missing the tree fields it
  expected and re-pinning its own investigation to an explicit `git worktree
  add ... 443972a`.)

## GII / multi-session scope -- unclaimed issues, own worktree only

GII (grab issues iteratively) means picking up **unclaimed** open issues -- no
existing PR, no in-progress branch. Do NOT continue another session's in-progress
PRs as part of the GII loop; those belong to their own sessions.

- Before grabbing an issue, verify no open PR covers it (`gh pr list` and check
  `headRefName` / body for "Closes #N").
- If all remaining unclaimed issues are blocked or too large, surface that to the
  user rather than hijacking in-progress PRs.
- **Never use another session's worktree** (one you did not create in this
  session). Each session owns its worktrees. If a branch is already checked out in
  a different worktree, create a fresh worktree from the remote branch in a new
  location or ask the user. Editing files in another session's worktree or its
  main-repo checkout is off-limits.

(The concrete rules here are Sparta-multi-session-specific; the general
"check for a prior claim before starting" rule lives in ai-config.)

**Post-merge tidy: never `git checkout main` (or `checkout -B main origin/main`)
inside a session worktree -- the `-B` form silently bypasses git's
already-checked-out-elsewhere guard and double-checks-out `main` against the
primary checkout.** The plain `git checkout main` correctly refuses when the
primary checkout holds `main`, but a scripted fallback like
`git checkout -q main || git checkout -qB main origin/main` (with stderr
swallowed) lands on the `-B` path, which re-points the shared `main` ref and
checks it out here anyway. Both worktrees then claim `[main]` in
`git worktree list`, and the next `git pull` in the session worktree moves the
shared ref out from under the primary's working tree -- the primary then shows a
wall of phantom staged diffs (the just-merged PR's changes, reversed), exactly
the stale-files symptom of the branch-repoint hazard above, with no error
anywhere. Recovery: move the session worktree onto a new branch
(`git switch -c <next-branch>`), then in the primary restore ONLY the
phantom-diff files (`git restore --staged --worktree <files>` -- not a blanket
`reset --hard`, which would clobber unrelated local state like untracked files
or uncommitted work). Prevention: after a merge, don't "return to main" in a
session worktree at all -- fetch and branch the next task's branch directly off
`origin/main` (`git switch -c <branch> origin/main`), leaving `main` itself to
the primary checkout. (Session `gii-ffdb93`, 2026-07-16: post-#919 tidy ran the
fallback form, double-checked-out `main`, and the primary showed nine phantom
staged reversals of #919's own files until restored.)

**With no next task queued yet, `git checkout --detach origin/main` is the
safe substitute for "branch off origin/main."** The prevention above assumes
a next branch is already known; when a session merges a PR and has nothing
queued next, detaching to `origin/main`'s tip (rather than creating and
switching to a real `main` branch ref, OR leaving the worktree sitting on the
now-merged, about-to-be-deleted branch) tidies the worktree without touching
any branch ref at all -- a detached `HEAD` isn't a branch, so it can't collide
with the primary checkout's own `main`. `git branch -d <merged-branch>` then
deletes cleanly (the branch is no longer checked out anywhere). Confirm the
detached tip really is the merge by checking the commit message names the PR
(`git log --oneline -1`) -- a squash merge lands as a new commit on `main`, so
`origin/main`'s tip is exactly that commit, not an ancestor relationship you'd
need `--is-ancestor` to confirm.

**Post-merge tidy: `git worktree remove` on your OWN currently-active worktree
can partially succeed and leave an empty, orphaned directory -- this is
harmless, not data loss.** After a PR merges, running `git worktree remove
.claude/worktrees/<name>` from the main checkout while THIS session is still
running inside that worktree (its Bash tool cwd pinned there) can fail with
`Permission denied` at the final `rmdir` step, but only *after* it already
deleted every file inside -- Windows won't let git remove the directory itself
while some process (the harness's own shell for this session) still holds a
handle to it. Symptoms: `git worktree list` no longer shows the entry (git's
`.git/worktrees/<name>` admin metadata IS removed), but
`Test-Path <dir>`/`ls` on the physical path still returns true because the
now-empty directory shell lingers. Confirm nothing was lost by checking
`git branch --list <branch>` (the branch itself is untouched by `worktree
remove` -- delete it separately with `git branch -d` once it no longer shows
in `git worktree list`) and `git log`/`gh pr view` to confirm the merge
actually landed on `main` before treating this as anything other than cleanup
succeeding by 99%. Don't attempt a forced re-remove or `rm -rf` on the
directory from within the same session -- it can't remove its own lock, and
the leftover empty directory is inert; it'll clean up naturally once the
session ends. Also: once this happens, do not try to Read/Edit/Write any file
inside that worktree path again this session -- the files are actually gone,
not just inaccessible; switch every subsequent file operation to the main
checkout's absolute path instead. (Session `gii-ffdb93`, 2026-07-13: `git
worktree remove ".claude/worktrees/gii-ffdb93"` for the just-merged PR #824
emptied the directory but left it registered as `Test-Path`-true; branch
`design/atomic-order-queue` was still present and cleanly `git branch -d`-able
afterward.)

When the next AI session reviewing a PR cites a "CLAUDE.md rule" to justify a
requested change, check that the rule's exact wording actually appears in
*this repo's* `CLAUDE.md` -- not just in the harness's own baseline style
defaults, which read similarly but aren't written into this file. PR #420's
reviewer cited "one short line max -- never write multi-line comment blocks" as
a CLAUDE.md rule; it isn't in sparta's `CLAUDE.md`, and the codebase's own
convention (e.g. `Settings.gd`) wraps explanatory comments across 2-3 lines.
Rebutting with that distinction is fine -- verify the citation, don't just comply.

## `git worktree remove` needs `--force` on a worktree containing a submodule

When a repository vendors a git submodule (historically `.ai-config` in sparta),
any `.claude/worktrees/<name>` worktree with it checked out
refuses the plain removal:
`fatal: working trees containing submodules cannot be moved or removed`.

This is a FLAT REFUSAL, not a dirty-tree complaint --
the worktree can be perfectly clean and still hit it.
It is distinct from the two failure modes already documented above:
the partial success that leaves an empty, orphaned directory,
and the fake worktree whose directory has no `.git` of its own.

**`--force` is the whole fix, and it is one command.**

```bash
git worktree remove --force <path>
```

git's own `git-worktree` docs say so under `remove`:
"Unclean worktrees or ones with submodules can be removed with `--force`."
Only `git worktree move` refuses a submodule worktree unconditionally;
`remove` accepts `--force` exactly as it does for an unclean tree.

Measured on git 2.37.2.windows.2, against a throwaway worktree with
`.ai-config` checked out: the plain form exits 128 with the error above,
and `--force` exits 0, deletes the directory,
and drops the entry from `git worktree list` with no prune needed.

Verify disposability before forcing, since `--force` is the point of no
return: `git status --short` comes back empty and
`git merge-base --is-ancestor <head> origin/main` returns true.
An empty `git rev-list origin/main..<head>` is the same fact in another
form, so run one or the other rather than both.

- **Do:** reach for `--force` as soon as a routine sweep reports this error.
- **Do:** verify disposability first -- `--force` discards without asking.
- **Don't:** read the refusal as "the worktree is busy" -- nothing holds it.
- **Don't:** conclude `--force` is refused without running it.
  The plain refusal's wording says nothing about what `--force` does,
  and a hand deletion plus `git worktree prune` is a longer road to the
  same place.

(2026-08-05, a local working-directory cleanup sweep:
7 of 8 worktrees were removed normally by `git worktree remove`;
`gii-mwc-4b00e5` refused with this error alone,
was verified clean with 0 unique commits and an ancestor of `origin/main`,
and was cleared via PowerShell `Remove-Item` plus `git worktree prune`.
That hand deletion was unnecessary: `--force` was never attempted,
and this entry originally asserted from that omission that it "does not
help".
Review challenged the claim against git's own docs, and the measurement
above -- run afterwards, on a purpose-built submodule worktree -- confirmed
the reviewer was right.
The reusable lesson is the narrower one:
a refusal message describes the command you ran,
not the flag you did not try.)

## A stub-review retry's recovered verdict posts under `github-actions`, not `claude`

When auditing a PR's true review status, don't filter comments by
`author.login == "claude"` alone -- a comment matching that filter can be a
stale earlier verdict, while the actual final verdict was posted under a
**different** identity and gets silently missed.

**Why:** the repo's `claude-code-review` workflow has a stub-review retry path
(gha#185/#218 -- the first attempt runs to completion but posts no `### Verdict`
line). When the retry recovers, it posts its result via a plain `gh pr comment`
step running under the workflow's default token, which attributes the comment
to **`github-actions[bot]`**, not `claude[bot]`. The original (stubbed or
successfully-verdicted) attempt posts natively as `claude[bot]`. So a PR's
comment history can contain an OLD `claude[bot]` "Needs more work" alongside a
NEWER `github-actions[bot]` "Ready for merge" -- and a check that only looks for
the `claude` login finds the stale one and misses the real, current verdict.

**How to catch it:** don't filter by a specific bot login at all. Pull every
comment (`gh api repos/<owner>/<repo>/issues/<N>/comments`), sort by
`created_at`, and read the actual last one -- or grep the full comment list for
`### Verdict` and take the latest match, regardless of author. Also check
`gh pr checks <N>` timing against the comment timestamps: a `review /
claude-review` / `review / require-review` run that completed **after** the
`claude[bot]` comment's timestamp is a strong signal a newer verdict exists
somewhere, even if the obvious author filter doesn't surface it.
(`Lacaedemon/sparta` PR #647, 2026-07-04 -- the agent's own "fully clean, Ready
for merge" report was correct; a first-pass verification that filtered by
`author.login == "claude"` found only the stale "Needs more work" comment and
nearly contradicted a true report.)

## `claude-code-review.yml` auto-fires on every PR again (re-enabled #1122, was off #1051-#1122)

PR #1062 (issue #1061, 2026-07-23) removed `.github/workflows/claude-code-review.yml`'s
`pull_request:` trigger, on the reasoning that GitHub Copilot code review (enabled
repo-wide via the `main` branch ruleset's `copilot_code_review` rule) already reviews
every PR automatically, making an automatic Claude pass redundant. Issue #1122
(2026-07-27) reversed that call at the user's direct request -- the `pull_request:`
trigger (`types: [opened, synchronize, ready_for_review, reopened]`) is back, so a fresh
PR again gets an automatic `claude[bot]` review comment, in addition to Copilot's.

**What this means for ARDI going forward:** a fresh PR gets BOTH an automatic Copilot
review and an automatic Claude review -- check both (`gh pr view <N> --json reviews` and
`gh api repos/<owner>/<repo>/pulls/<N>/comments`, per the "Re-check for latest review
findings" convention) rather than assuming only one fired. All of this file's and
ai-config's stub-review / "do the review yourself when @claude doesn't produce a verdict"
handling still applies to Claude's automatic pass, same as before it was ever disabled.
`claude.yml`'s own re-dispatch-after-push mechanism and a manual
`gh workflow run claude-code-review.yml -f pr_number=<N>` both still work as before --
useful for an ad-hoc re-review after a push, since `synchronize` already re-fires
automatically now.

If this ever needs disabling again, PR #1062's diff (`git show 17fab72a`) is the exact
prior workflow-config change to reference.

**A PR that edits `claude-code-review.yml` (or a workflow file the review action reads)
gets no inline Claude review at all -- by design, not a stub.** The `review/claude-review`
job still runs and reports `pass`, but posts a run annotation instead of a review comment:
"PR #N edits `.github/workflows/claude-code-review.yml` -- skipping self-review (the action
401s on workflow validation until merged; it runs after merge)." **The exact mechanism is
unconfirmed** (not verified against `d-morrison/gha`'s own implementation) -- the plausible
read is that GitHub only lets the review action validate against the workflow version
already on the base branch, so a PR changing that same file can't be validated pre-merge and
the action detects this and defers review to post-merge instead of failing or posting a
stub -- but that's inference from a single annotation, not a confirmed cause. Regardless of
the exact mechanism, don't treat the skip as a broken/stub review needing a manual
re-dispatch (per the existing stub-review handling above) -- check the run's own annotations
(`gh run view <run-id>`) before assuming a self-review is missing for the usual reasons.
(`Lacaedemon/sparta` PR #1123, 2026-07-27.)

**The corollary, and it is the dangerous half: that self-skip means a PR which BREAKS the
review config gets no review OF that breakage -- so on a PR editing `claude-code-review.yml`,
a fully green board is the WEAKEST assurance available, not the strongest.** The skip fires
before the config is exercised, so a broken `plugins:`/`plugin-marketplaces:` ref sails
through with `review / require-review` itself reporting `pass`. The failure then lands on the
NEXT PR opened, where that same required check dies at plugin install and blocks the whole
repo. Nothing on the introducing PR points at it.

This is not hypothetical: PR #1176 (a Jules-authored one-line `distance_squared_to`
micro-optimization) carried a commit that changed `plugins: ai-config@Morrison-Lab` back to
`ai-config@d-morrison`, whose own message described it as *"fixes a Claude plugin marketplace
reference bug"* -- inverted, since the marketplace declares `"name": "Morrison-Lab"` (see the
account-move entry below). It reverted #1172 and would have reintroduced #1171, making every
subsequent PR unmergeable. All 14 checks were green, and the comment block *directly above the
changed line* already warned against exactly that value, error string included. Three failures
had to stack for it to get that far: the bot's inverted "fix", the self-skip suppressing the
only reviewer that would have caught it, and Copilot simultaneously quota-exhausted.

**How to apply.** Treat any diff touching `claude-code-review.yml` as review-exempt by
construction and hand-verify it, no matter how green CI is or how plausible the commit message
sounds. Concretely, diff the file against the **merge-base**, matching this file's own
convention for every other diff-scoped check (the `codecov/patch`-gap and `check.sh`
diff-scoping entries) -- not against `origin/main`'s tip:

```bash
git diff "$(git merge-base HEAD origin/main)" HEAD -- .github/workflows/claude-code-review.yml
```

That distinction is load-bearing rather than pedantic here. `main` has itself moved on this
exact file (#1172 landed the `d-morrison` -> `Morrison-Lab` fix there), so a tip diff on any
branch forked before that reports a spurious "revert" of the marketplace ref for a branch that
never touched the workflow at all -- noise shaped exactly like the anomaly this entry teaches
you to hunt. The natural response to that false alarm is to "fix" a file the PR never touched,
which is what would *create* a real self-skip condition out of nothing.

For a plugin/marketplace ref, then check it against the marketplace's own live declared name
rather than reasoning from the URL (the ref resolves by declared name; the URL still resolves
via GitHub's transfer redirect and so tells you nothing):
`gh api repos/<owner>/ai-config/contents/.claude-plugin/marketplace.json --jq .content | base64 -d`.

Best outcome when the workflow edit is unrelated collateral (as here): drop it entirely. The
file then becomes byte-identical to `main` and falls out of the PR's diff, which retires the
skip condition -- confirmed on #1176, where the review went from a 6s skip to a genuine 11m
run and verdict on the very next push. That **narrows** the older "cannot verify itself" note
in the account-move section below rather than retiring it, and the distinction matters: when
the edit is collateral, dropping it restores review; when the edit *is* the fix (#1172 itself),
dropping it would delete the very thing being verified, so that note still holds in full --
confirm on the next PR's run. (`Lacaedemon/sparta` PR #1176, 2026-07-29.)

**Copilot's own review can also fail closed, not just Claude's.** Copilot's review comment
can read `Copilot was unable to review this pull request because the user who requested the
review has reached their quota limit.` -- repeatedly, across many pushes. This is a distinct
failure mode from Claude's own quota-skip message, but the same handling applies: it's not an
approval, don't wait on it, self-review or manually dispatch Claude instead.

**A second, quieter Copilot failure mode: zero seats provisioned, which produces total
silence rather than a quota-refusal comment.** Requesting Copilot review
(`POST .../requested_reviewers -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`) can
return `200` with the reviewer already absent from `requested_reviewers` in the same
response --- and after that, no check run, no comment, no review, no legacy commit status
ever appears, even after 15+ minutes. This is *not* the same as the quota-refusal case
above: that one at least posts a comment explaining the refusal, which is itself proof the
request reached Copilot. Total silence with no artifact of any kind is the tell for a
different cause --- no Copilot seat exists for the org to act under at all. Confirm
directly rather than guessing between the two:

```bash
gh api "orgs/<org>/copilot/billing" --jq '{total: .seat_breakdown.total, setting: .seat_management_setting}'
```

`Lacaedemon` returns `{"total": 0, "setting": "unconfigured"}` --- zero seats, so the
`copilot_code_review` branch ruleset's `review_on_push: true` has nothing to dispatch to,
and an explicit request silently no-ops the same way. Treat this exactly like the
quota-refusal case for handling purposes (not an approval, self-review instead), but don't
conflate the two when explaining *why* --- one is "Copilot looked and declined", the other is
"Copilot was never in a position to look." (`Lacaedemon/sparta` PR #1229, 2026-08-09.)

**A manual `gh workflow run "Claude Code Review" -f pr_number=<N>` dispatch can silently run
against `main`'s ref instead of the PR branch and post NO comment at all -- a distinct, quieter
failure than the documented stub-review pattern.** The run itself reports `success` (all three
jobs green), and every run so far has carried a `The process '/usr/bin/git' failed with exit
code 128` annotation regardless of whether it actually posted a review -- that annotation is
benign, expected noise, not a sign anything went wrong. The real tell is the run's own
`head_branch`: a manually-triggered run that resolves to `main` (rather than the PR's actual
branch) reviews nothing PR-specific and produces no comment, even on `success`. Meanwhile, this
repo's automated re-dispatch mechanism (`claude.yml`'s push-triggered re-dispatch, attributed to
`github-actions[bot]`) fires its OWN `workflow_dispatch` correctly scoped to the PR's real branch
-- and if a manual dispatch is still in flight when it queues, the `claude-review-<N>` concurrency
group cancels the manual one in favor of it (`Canceling since a higher priority waiting request
for claude-review-<N> exists`). **How to apply:** after pushing, check `gh run list
--workflow="Claude Code Review"` for a run whose `head_branch` matches the PR's actual branch
before manually dispatching -- the automated re-dispatch usually beats you to it within a minute
or two. If you do dispatch manually and it lands on `main` with no resulting comment, that's the
signal to just wait for (or re-dispatch and confirm) a run scoped to the real branch, not to
suspect the PR itself. (`Lacaedemon/sparta` PR #1070, 2026-07-27.)

## Verify an issue's own stated root cause empirically before implementing its proposed fix

A well-written bug issue with specific code references (line numbers, a named mechanism,
a plausible-sounding causal chain) is still a hypothesis, not a verified fact -- even when
it was clearly written after real investigation. Before implementing the issue's own
"fix direction," reproduce the bug live and confirm the ACTUAL code path taken matches the
diagnosis, rather than trusting the write-up and jumping straight to the proposed fix.

**Why this matters:** issue #724 diagnosed a swirling-formation bug as `_face_for_action`'s
"already turning" branch never settling (its re-target-every-tick logic defeating
`_advance_turn`'s tight arrival epsilon). The fix direction (a positional deadband before
re-targeting) was specific, well-reasoned, and referenced real line numbers. Implementing
it and running the exact reproduction (`demos/inputs/all-out-attack.json` via
`tools/demo/dump-state.sh`) showed **zero change** in output vs. unpatched `main` -- a
temporary debug print in `_face_for_action` revealed `_engage_turn_target` was NEVER
non-zero across the whole 300-tick window the bug manifests in. The offset stayed under 1°
the entire time, so every tick took the *small*-offset instant-snap branch (`_face_dir`),
never the branch the issue diagnosed and the fix targeted. The real mechanism turned out to
involve the raw **position** itself arcing (not just facing), with soldier counts and
frontage essentially frozen throughout -- ruling out the issue's own "third instance of the
same hazard family" framing and pointing at `_press_into()`/`_separate()` instead.

**How to apply:** before implementing a fix a reviewer or issue author proposed (yours or
someone else's), run the issue's own reproduction command (or write an equivalent
`dump-state.sh`/live-battle trace) against the UNMODIFIED code first, and instrument the
specific branch/variable the diagnosis claims is at fault. Confirm that variable's state
actually matches the story before spending effort on the proposed fix -- a `git stash` +
re-run diff (patched vs. unpatched output, byte for byte) is a fast, decisive way to catch
a fix that silently does nothing. This is the same "never assume; always verify" principle
`preferences.md` states generally, applied specifically to a bug's root-cause narrative,
not just its resolution status.

## After implementing a fix, verify it actually engages the reported bug's real code path

The entry above ("verify an issue's own stated root cause empirically") covers checking the
DIAGNOSIS before implementing. This is the companion check AFTER implementing: a fix can be
logically correct for the code path you touched, compile, pass its own new unit tests, and
still leave the originally-reported bug completely unfixed -- because the real-world scenario
that triggers the bug turns out to route through a DIFFERENT code path than the one the fix
covers. Passing tests for the path you fixed proves nothing about whether that's the path
the bug actually takes.

**Concrete case:** issue #1072 diagnosed the Fallen casualty-heap VFX spawning at a stale
formation-geometry location instead of the dying soldiers' live position, and named
`SoldierMelee.reap()`'s per-soldier casualty path as the fix point (PR #1074). The first
implementation threaded the dying soldiers' exact live centroid through that path, added
passing unit tests, and looked done. Only building an actual before/after visual proof (the
same technique the issue's own investigation used -- rendering the exact reported reproduction
script at the exact reported tick, on `main` vs the branch) revealed the two frames were
**pixel-identical** -- the fix had zero effect on the reported scenario. Root cause:
`SoldierMelee.reap()` is only reached once a unit's engaged-tier latch has set
(`Unit.is_engaged()`), which requires at least one PRIOR tick of `state == FIGHTING` (the
latch, `tick_engaged()`, runs after `_think()` in the same physics step) -- so the VERY FIRST
strike after fresh contact always falls through to the regiment-formula fallback path
instead. Every one of the reported scenario's three casualty events was exactly that first-
strike case; the per-soldier path the fix touched never fired at all for this bug. Required a
second fallback tier (anchoring on the unit's own live soldier bodies when exact per-death
data isn't available, instead of the stale formation geometry) to actually fix the reported
case -- see the follow-up entry below for how even THAT fallback still needed a further round
of the same lesson, and how the whole mechanism was eventually redesigned away.

**How to apply:** before considering a fix complete, reproduce the ORIGINAL reported scenario
(not just a hand-built unit-test fixture) and confirm observably that the previously-buggy
behavior no longer occurs -- a real before/after comparison (frame diff, state dump, or
equivalent), not just "my new tests pass." If a before/after comparison shows NO difference
at all where a real behavioral change was expected, that's a strong signal the fix's code
path isn't the one actually exercised by the report -- instrument the specific branch/gate
(`is_engaged()`, a feature flag, an early return) to find out which path really fires before
assuming the fix needs to be bigger, smaller, or different. A unit test built around your own
mental model of "how the bug happens" inherits that same blind spot; only a reproduction of
the ORIGINAL report is immune to it. (`Lacaedemon/sparta` issue #1072, PR #1074, 2026-07-25.)

### Follow-up round: the same lesson recurred, then a design pivot to bottom-up physics

The Fallen-heap saga above didn't end with PR #1074. A separate demo (`spear-standoff.json`,
from PR #1075, an unrelated attack-cadence change) still showed casualties "appearing out of
nowhere" after #1074 merged -- the user caught this directly by eye. Investigating it surfaced
TWO further lessons on top of the one above, both worth carrying forward:

1. **The same "verify against the real scenario" lesson bit a SECOND time, on the fallback
   tier itself.** #1074's second-tier fallback (anchoring on the unit's live soldier bodies
   when no exact per-death data exists) averaged the WHOLE regiment -- a real, provable flaw
   (a unit test with a deliberately split formation showed the average landing in the gap
   between two clusters). The obvious fix was to bias that average toward the soldiers
   nearest the attacker instead. But re-verifying against the ACTUAL `spear-standoff` demo
   (not just the constructed unit-test case) showed the fix changed NOTHING for that specific
   scenario -- the block wasn't spread into separate clusters at the casualty tick, so the old
   whole-block average and the new near-attacker-biased average came out nearly identical.
   The fix was still logically correct and worth keeping (proven by the isolated test), but it
   was not what was actually causing the visible symptom in the reported case. **How to
   apply:** even a fix built specifically IN RESPONSE to a "verify the real scenario" lesson
   still needs that same verification applied to itself -- don't let fixing one instance of the
   lesson exempt the next fix from it.
2. **What actually explained the demo's symptom was a THIRD, distinct mechanism**: `Fallen.gd`
   already documented (in its own doc comment) that the heap is deliberately stationary once
   spawned, "fading into the ground as the fight moves on." A charging formation can advance
   far enough in under a second to visibly leave a CORRECTLY-spawned heap behind -- confirmed
   by comparing the unit's own `soldier_summary.centroid` at the death tick against 40 ticks
   later (a ~40-world-unit advance in ~0.6s). This was filed as its own issue (#1076) rather
   than fixed unilaterally, since "should a cosmetic death-mark track the living formation" is
   a genuine design question, not a bug -- then closed once the user confirmed directly that a
   fallen soldier's mark should reflect where it died, not follow the survivors afterward
   (the intended behavior all along, once the OTHER two issues were actually fixed).

**The design pivot.** Asked directly what the "heap" mechanic even was, and on hearing the
explanation, the user's call (echoing "remember: no top down abstractions") was to eliminate
the whole "compute one representative point per casualty event, then scatter a synthetic
pattern of marks around it" design outright -- not just keep patching which point gets chosen.
PR #1078 replaced it: every dying soldier now gets its own mark at its own real live position
(exact positions from `SoldierMelee.reap()` when available; the real positions of the nearest
live soldiers to the attacker as a fallback when not). No more averaging, no more golden-angle
fake scatter. This is a DIRECT instance of this file's own "Standing design philosophy:
bottom-up physics, no top-down gimmicks" section (above) -- previously stated and applied only
to gameplay/combat mechanics (knockback, collision, morale), but it turned out to apply just
as cleanly to a purely cosmetic rendering system: an aggregate-and-scatter VFX is the same
shape of top-down shortcut as a flat combat modifier, just one layer further from gameplay.
**How to apply:** when a cosmetic/rendering system is accumulating fallback tiers and
special-case math to approximate "where did this event actually happen," consider whether the
underlying real per-entity data (already computed, already available) can be shown directly
instead of being reduced to one synthetic representative point -- the direct version is often
BOTH simpler and more correct than the aggregate one, on this codebase's own terms.
(`Lacaedemon/sparta` issues #1076/#1077, PRs #1078, 2026-07-25.)

## A "matches the issue's own framing" fix can be completely inert for the actual reported symptom -- verify with the SAME artifact the report used

Building on the entries above: PR #1137 (closing #1129, reporting infantry visibly walking
through each other in the site's showcase clip) started by fixing exactly what the linked
issue described -- NORMAL formation's zero containment margin (a real gap #1118 deliberately
left open). Implementing it, testing it, and even doing a live-battle probe render made it
LOOK like the fix worked. But a direct before/after render of the ACTUAL reported artifact
(`demos/showcase.json`, tick 600, unmodified vs. fixed) came back **pixel-identical** -- the
exact same "zero effect" signal the Fallen-heap case above already documents. Root cause,
found only by then tracing WHY the probe render differed from the real artifact: the showcase
demo's player units were on a plain MOVE order with no attack target, which this repo's own
`_think()` deliberately treats as "disengage" -- the units never entered `state == FIGHTING`
at all, so `is_engaged()`-gated `engaged_soldier_indices()` (which the containment margin
widens) never fired for them regardless of any margin value. The real fix needed a second,
deeper layer: decoupling PHYSICAL collision from combat state entirely
(`Unit._in_enemy_contact`, a pure-proximity flag).

**How to apply:** when a reported bug names a specific mechanism/issue, and a fix matching
that framing "looks right" (passes new tests, even improves a HAND-BUILT reproduction), still
render the SAME artifact the bug report itself pointed at (not a look-alike scenario you
construct) before declaring it fixed. A hand-built probe scenario inherits your own mental
model of the bug -- same blind spot the entry above names -- and can pass even when the real
artifact wouldn't. (`Lacaedemon/sparta` issue #1129, PR #1137, 2026-07-27.)

## Widening a validated is_engaged()-OR-proximity gate to an ADJACENT function isn't automatically safe -- position-anchor code has its own sensitivity

PR #1137 decoupled several functions from combat-state-only gating (`is_engaged()`) to
`is_engaged() OR _in_enemy_contact` -- a pure-proximity flag -- so a "disengaging" unit's
soldier BODIES still physically resist an enemy even though the unit itself never fights.
This worked cleanly for `SoldierEnemyContact.accumulate`, `_separate()`'s enemy branch, and
the new `contact_soldier_indices()` selection: full test suite green, no regressions.

Applying the IDENTICAL pattern to `Unit.position_anchor_indices()` / `near_front_soldier_
indices()` (the selection `SoldierBodies.couple()` anchors a regiment's `position` on)
looked like the natural, structurally-identical next step -- and #783/#784 already
established the exact real-world need (a fighting regiment's charge "rides through" a braced
line because `couple()` dilutes its resisted front rank's signal over the whole unengaged
block; the same dilution applies to a merely-in-contact-not-fighting unit, unfixed). It
compiled, passed `validate`/`comments`/`units`/`chars`, and even a quick isolated live-battle
unit test. Only running the FULL test suite (specifically `test_collision_knockback_battle.gd`,
a live 900-tick showcase-scenario regression guard) revealed it hung INDEFINITELY (reproduced
with a 90s timeout in isolation, never completes; the same test normally runs in ~17s).

**How to apply:** two functions sharing the SAME surface pattern (a combat-state gate, a
near-front selection) are not interchangeable in risk just because the fix mechanism looks
identical. `Unit.ANCHOR_RANKS`' own doc comment already documents a history of subtle
swirl/instability regressions from narrowing this SPECIFIC selection's DEPTH; widening WHICH
UNITS qualify for it turned out to be an untested new axis on that same sensitive surface,
not a safe copy of a pattern proven elsewhere. Before extending a validated fix to an
adjacent function, specifically re-run any LIVE, LONG-RUNNING (not just isolated/short)
regression tests that already exist for that function's own subsystem -- a hang can hide
behind every fast/isolated check passing. Reverted rather than root-caused under time
pressure; tracked as issue #1136 for whoever investigates further with per-tick
instrumentation.

## Even well-documented anti-patterns get re-violated under complexity/time pressure -- a targeted pre-push grep still pays for itself

PR #1137's first review round found 5 real findings -- two of which are mistakes THIS FILE
already documents in detail before this PR even started: the asymmetric
`maxf(self_reach, candidate_reach)` contact-check convention (see "A symmetric 'is X near Y'
contact check" below) and the `demos/demo.json` shared-file-is-a-perennial-merge-conflict-
point / use-a-per-PR-numbered-manifest convention (see "record-demos.sh DEMOS conflicts are
ADDITIVE" above and CLAUDE.md's own demo-authoring section). Both got violated anyway,
despite being demonstrably already in front of the session (they were even cited correctly,
from memory, elsewhere in the SAME session's own reasoning, just not cross-checked against
the specific lines being written).

**How to apply:** having read a memory file once earlier in a session is not the same as
re-checking it at the moment of writing the specific code it warns about. For any PR
touching `SoldierEnemyContact`/`_separate`/proximity-style contact checks, or any PR
touching `demos/demo.json`, grep this file for the relevant section NAME right before the
final push (not just recall it from earlier context) -- a 10-second grep is cheaper than a
full review round. (`Lacaedemon/sparta` PR #1137, 2026-07-27.)

**A third recurrence, this time against a cross-repo (ai-config) rule rather than a
sparta-local one:** `pr-on-claim.md`'s "Run that `requested_reviewers` POST as the sole
(or last) command in its Bash call" was loaded in context, and #1241's very first Copilot
request (issued right after `gh pr create`) already followed it -- a single, unpiped,
unchained call. `hooks/no-unreviewed-pr.py` still reported "no SUCCESSFUL reviewer request
follows" for #1241 (and #1239) at the next Stop check. Re-requesting for #1239 in a
combined call -- `POST | head -3`, then two chained `gh pr view` verification reads for
both PRs in the same Bash call -- is a clear instance of the rule's own named tell ("a pipe
added purely to trim the output"), and the guard fired again with the identical message.
Only reissuing BOTH POSTs as fully isolated calls (bare command, no pipe, nothing chained
after it) cleared the guard. Exactly why the first, genuinely clean #1241 request didn't
already satisfy it is unconfirmed -- possibly the guard's discharge window doesn't reach
back past an intervening non-conforming call, possibly something else; this records the
observed sequence and the fix, not a verified mechanism.
**How to apply:** don't assume a clean, isolated reviewer-request call earlier in a session
keeps discharging the guard for a PR you touch again later -- if the guard fires, re-issue
the POST as its own isolated call right then, even if you believe an earlier request for
the same PR was already correct. (`Lacaedemon/sparta` PRs #1239/#1241, 2026-08-10.)

## A freshly-constructed test Unit defaults to morale 100 -- routing tests can auto-rally instantly

`Unit.gd`'s `morale` field defaults to `100.0`. A GUT test that constructs a bare `Unit`
via `Unit.new()` and immediately calls `_process_rout()` to test rout/flee behavior can hit
`_process_rout`'s own auto-rally check (`morale >= RALLY_MORALE_THRESHOLD and _can_rally()`)
on the very first call -- `_can_rally()` trivially returns true in an isolated unit test
(full soldier strength, and `UnitTargeting.nearest_enemy_to` finds nothing since no enemy
Unit exists in the scene), so the unit rallies immediately regardless of what the test
meant to observe. Either set `u.morale = 0.0` (or another value below
`RALLY_MORALE_THRESHOLD`) before the first `_process_rout()` call, or set `u._shattered =
true` if the test wants a flee-forever unit that never rallies at all. Also call the real
`u._rout()` first if the test depends on `_rout_timer` being armed (`ROUT_TIME`) -- a unit
that never went through `_rout()` has `_rout_timer == 0.0`, so `_process_rout`'s own
"timer ran out" branch fires on the very first call, which look like a rally/shatter
outcome from the fix under test rather than from the unarmed timer.
(`Lacaedemon/sparta` PR #730, 2026-07-10.)

## `PathField.active` is a global static -- reset it around any isolated-unit test touching movement/routing

`PathField.active` (a `static var`) persists across GUT tests within the same run, not just
within one test function. A test that constructs a bare `Unit` and calls `_process_rout()`
or `_move_to()` directly (bypassing a live Battle scene) gets different behavior depending
on whether some EARLIER test in the same run left a real `PathField` instance active -- if
so, the pathfinding branch runs instead of the simpler straight-line-flee/move branch,
which can silently change which code path the test is actually exercising. Save and restore
it around the test, the pattern already used in `test_routing_terrain_pathfinding.gd`:
```gdscript
var old_pf: PathField = PathField.active
PathField.active = null   # (or a specific PathField, if the test needs terrain)
...
PathField.active = old_pf
```
Do this in any new isolated-unit test that calls a `Unit` method sensitive to
`PathField.active`, not just tests that are themselves about pathfinding.

## A new stance's derived cap can invert the baseline it's supposed to exceed -- check the full input range, not just a weak test case

When a new order-mode/stance introduces its own derived cap or multiplier computed from
geometry or other per-unit inputs (not a flat constant), verify across the REALISTIC RANGE
of those inputs that the derived value can't fall below an existing baseline constant it's
meant to exceed. A test that only exercises a narrow/weak scenario can pass while the
general claim in its own assertion message is false for stronger inputs elsewhere in the
range.

**Concrete case:** PR #736 (knockback focus) added `SoldierCombat.clear_line_speed_cap()`
-- the default "just clear the line" push-distance cap, `sqrt(2 * body_accel *
clear_distance)` -- intending "trade damage for a much bigger push-back." But for realistic
front-depth pairings (`Unit._front_depth()`'s own `attack_range * 0.5` cap bounds
`clear_distance` to roughly 26-48 wu), the geometric formula tops out around 39.5-53.67
wu/s, BELOW the ordinary attack's `KNOCKBACK_SPEED_MAX = 60.0` -- so a strong/charging
landed hit got shoved LESS far by the stance's own default variant than a plain attack
already pushes it, the opposite of the stated design. The included test
(`test_knockback_focus_pushes_the_defender_back_harder_than_a_normal_attacker`) asserted
this generally ("even at the default 'clear the line' setting") but only exercised a weak,
no-charge 12-soldier scenario where the normal-attack impulse never approached the cap, so
it passed despite the inversion. Caught by a `claude[bot]` review pass, not by the original
implementation or its own test.

**Fix pattern:** floor the derived cap at the baseline it's meant to exceed
(`maxf(KNOCKBACK_SPEED_MAX, clear_line_speed_cap(...))`, extracted as its own pure function
`knockback_focus_clear_line_cap()` so the floor is directly unit-testable) rather than using
the raw geometric formula alone. Add tests at BOTH ends of the input range: one proving the
floor binds where the raw formula would undercut the baseline, one proving it doesn't clip
a case where the raw formula already exceeds the baseline.

**How to apply:** when reviewing (or writing) any new per-unit derived cap/multiplier that's
framed as "at least as strong as / bigger than" an existing baseline, don't trust a single
weak-case test to prove that framing -- compute (or test) the derived value at the edges of
the realistic input range and confirm it never crosses below the baseline it's supposed to
dominate. (`Lacaedemon/sparta` PR #736, 2026-07-11.)

## A prior PR's own claimed verification can be wrong even after merge

The existing "verify an issue's own stated root cause empirically" memory above covers a
not-yet-merged issue's hypothesis. It extends to a **merged, review-clean PR's own claims**
too: don't cite one as describing the current codebase state just because it merged with a
passing review -- spot-check the actual reproduction before trusting it.

**Concrete case:** #743 (merged) claimed, with specific before/after position values, that
it fixed the coast-to-stop bug (residual `_current_speed` decaying while `position` sits
frozen), and its own review rounds confirmed it. The claim didn't reproduce against the
actually-merged commit: `dump-state.sh` on `main` still showed `position` pixel-frozen while
`current_speed` ramped down. Root cause: `UnitCombat`'s "spend the charge" strike-resolution
reset zeroed `_approach_velocity` on the exact tick a unit's last enemy died -- the SAME tick
the idle-coast guard started reading it for a travel direction -- a case #743's own tests
never exercised (they set up `_approach_velocity`/`facing` directly, never went through a
real combat kill). Fixed in #747 by falling back to `facing` in that specific
zero-velocity/nonzero-speed anomalous state.

**How to apply:** before citing a merged PR's demo/description as proof of current behavior
(e.g. when deciding whether a design-philosophy note still needs a "check whether X has
merged" hedge, or when building on top of a mechanism a recent PR claims to have fixed),
re-run its own reproduction against the current `main` rather than trusting the PR body.
This is cheap (`dump-state.sh` against the PR's own demo input) and catches exactly this
class of gap: a fix that works in the narrow scenario its own tests constructed, but not in
the real path the bug actually occurs on.

## Regiment position is a pure function of body positions

As of #749, `Unit.position` (the regiment's own kinematic point) is not an independently-
controlled value the soldier bodies chase -- it's continuously re-derived FROM the bodies.
`SoldierBodies.couple()` runs every tick, computes the drift between the soldier bodies'
actual centroid and their formation-slot centroid, and slides `position` a bounded fraction
of that drift (`FOLLOW_RATE`, capped at `MAX_FOLLOW_SPEED`) toward the bodies. This runs
**unconditionally** -- for every unit, every tick, regardless of order state.

**Consequence:** a unit with NO move order (including one under `ORDER_HOLD`, or simply
idle) can still visibly move if its soldier bodies get physically displaced by something
else -- enemy-contact impulses, knockback, a failed brace. This isn't a bug or a "unit
trying to move" -- it's the intended emergent behavior of the "no top-down gimmicks"
philosophy above: a real line hit hard enough to yield ground would physically cede that
ground, not teleport back to a fixed spot. Before #749, `MAX_FOLLOW_SPEED` was 80 (a mild
drift, largely invisible); #749 raised it to 300 specifically so this coupling could win
against genuine contact resistance, which also makes any body displacement (including from
unrelated causes) far more visible than before.

**How to apply:** when a "stationary" or `HOLD`-ordered unit appears to drift in a demo or
state dump, don't assume its order/state logic is misfiring -- check whether its soldier
BODIES are being displaced (contact physics, knockback, a facing/grid change dragging slot
targets) and whether `couple()` is just honestly reporting that drift back up to `position`.
(`Lacaedemon/sparta` PR #749, 2026-07-11.)

