## A PR can revert merged `main` content through a perfectly clean merge -- trial-merge onto `main` before trusting a green board

The standing sync rules all assume the hazard announces itself as a conflict. It does not
have to. A commit that lands on a PR branch *after* `main` was merged in can undo that
merge's content, and the result then merges back onto `main` cleanly, with no conflict, no
red check, and no signal in the PR's own diff view -- which shows the PR against its base,
not what merging it would do to `main`.

**Concrete case:** on `Lacaedemon/sparta` PR #1194 (2026-08-07), `google-labs-jules[bot]`
pushed `870e199e` on top of a session's own `main`-sync commit. Its diffstat read as
ordinary deletions; what it actually did was revert every file the sync had brought in.
Trial-merging the PR head onto `main` produced **14 files changed, 77 insertions, 484
deletions**, undoing merged work from five PRs: #1199 (shield defense by defender skill,
across `scripts/Shield.gd` / `SoldierCombat.gd` / `Battle.gd` / `test_soldier_combat.gd`),
#1212 (`test_residual_melee_swirl_battle.gd`, 193 lines), #1210/#1208/#1205 (memory
entries), and #1214/#1215 (`GEMINI.md`, `.gemini/config.yaml`). Only `+24/-24` in
`scripts/SelectionManager.gd` was the PR's actual subject.

**Why the usual checks miss it.** `mergeable: MERGEABLE` / `mergeStateStatus: CLEAN` only
say there is no textual conflict. `gh pr diff` shows the PR against its merge-base. CI runs
on the PR head, where the reverted state is internally consistent and passes. Even
`git merge-base --is-ancestor <main-commit> <pr-head>` returns **true** for every reverted
commit, because the merge really is in the ancestry -- the revert sits on top of it. That
last one is the trap: the obvious ancestry check actively reassures you.

**The check that works** is a real trial merge in a throwaway worktree, then a diff against
`main`:

```bash
git worktree add --detach /tmp/mt origin/main
cd /tmp/mt && git merge --no-commit --no-ff <pr-head>
git diff origin/main --stat        # net effect on main; large deletions == revert
git merge --abort; cd - && git worktree remove --force /tmp/mt
```

Run it before merging any PR whose branch gained commits after a `main` sync -- especially
one pushed by a different agent, since a bot with a stale working tree can commit its whole
tree state and silently revert anything newer.

- **Do:** trial-merge onto `main` and read the net diffstat before merging a PR you did not
  drive end to end.
- **Do:** treat a large deletion count against `main` as a revert until proven otherwise.
- **Don't:** read `MERGEABLE`/`CLEAN`, a green board, or a true `--is-ancestor` result as
  evidence that merging preserves `main`'s content.

## `tools/check.sh chars` scans only `*.qmd` and `*.R` -- `docs/*.md` is outside every net

`check_chars` (and the `check / check-chars` CI job) is scoped to the website docs. A brand
new Markdown file under `docs/` can therefore land banned punctuation with every check
green. `CLAUDE.md`'s ASCII-punctuation rule covers *every* tracked source file including
`.md`, so the rule and its enforcement disagree, and the gap is invisible from CI.

Found on PR #1198 (2026-08-07): `docs/square-formation-design.md`, a new 238-line file
added by that PR, carried **33 em-dashes**, plus one on its added `PLAN.md` line. All
checks were green and the automated review did not flag them either. Because the whole file
is the PR's own added lines, these were in scope for that PR rather than grandfathered.

When editing or adding `.md` under `docs/`, check the added lines by hand:

```bash
git diff origin/main -- <paths> | grep "^+" | python -c "
import sys; d=sys.stdin.buffer.read().decode('utf-8')
print(sum(d.count(c) for c in u'\u2014\u2013\u201c\u201d\u2018\u2019\u00d7'))"
```

Scope the fix to lines the PR actually added: a whole-file replace on a pre-existing file
(`PLAN.md` has 55 other em-dashes) is the scope-creep the punctuation rule itself warns
against.

## `main` has no required status checks -- a red `require-review` does not block merging

Easy to assume the opposite from the check's name, and the assumption changes how urgently
a broken reviewer gets treated. Verified 2026-08-07:

```bash
gh api repos/Lacaedemon/sparta/branches/main/protection      #=> 404 Branch not protected
gh api repos/Lacaedemon/sparta/rules/branches/main --jq '[.[].type]'
#=> ["deletion","non_fast_forward","pull_request","copilot_code_review"]  -- no required_status_checks
```

A PR whose `claude-review` and `require-review` are both red still reads
`mergeable: MERGEABLE`, `mergeStateStatus: UNSTABLE`. So a reviewer outage removes review
*silently* rather than gating merges, which is the more dangerous shape: nothing stops an
unreviewed PR being merged, and the merge button gives no hint. Don't report a red review
check as a merge blocker without querying protection first.

Note the `copilot_code_review` ruleset in that list: per `pr-on-claim`, that means Copilot
is re-requested automatically on push, which is why an explicit request's pending entry
disappears moments after a `201`.

## A `claude-review` that dies at ~40s with `total_cost_usd: 0` is not necessarily quota

`fully-clean`'s zero-cost signature (`is_error: true`, `num_turns: 1`, `total_cost_usd: 0`,
short duration) genuinely covers quota exhaustion and expired credentials. It also covers a
third cause that never reaches the model at all: a **plugin-install failure**.

```
##[error]Action failed with error: Failed to install plugin 'ai-config@Morrison-Lab' (exit code: 1)
##[error]Claude review did not complete successfully and was not eligible for a stub-review retry
TOTAL_COST: 0.0000
```

Same cost, same rough duration, completely different fix -- and unlike quota it will never
clear on its own. Read the job's own `##[error]` lines before classifying by the fingerprint;
a retry-and-wait on this one waits forever.

**Root cause when it appeared (2026-08-07):** `Morrison-Lab/ai-config` commit `6dc0cb49`
renamed the marketplace `"name"` from `Morrison-Lab` to `morrison-lab`, authored 02:53Z but
only reaching `main` when ai-config#1238 merged at 05:32Z. A plugin ref resolves by the
marketplace's **declared name**, which is case-sensitive, so every consumer pinning
`ai-config@Morrison-Lab` broke. Sparta's own runs bracket the landing exactly: #1194's
review passed at 02:53:55Z, #1198's failed at 05:56:48Z. Tracked as ai-config#1246/#1248.

The authored-versus-landed distinction is the part worth keeping: a `git log` date on the
offending commit will predate the breakage by hours, which makes the timeline look
inconsistent until you check when it merged.

## A red `claude-review` can sit on top of a GENUINE, complete verdict --- read which STEP failed

The entry above classifies a review that never reached the model at all.
This is the opposite shape.
The model ran, produced a full verdict, and posted it, and the job still went red ---
because `claude-review` keeps going after the verdict-posting step, and a later step can
fail on its own.

`review / require-review` then fails as a pure consequence
(`##[error]Claude review job did not succeed (result: failure).`), so the board shows two
red review checks with a perfectly good "Ready for merge" comment sitting on the PR.

**Every fingerprint this file already documents points the wrong way here.**
It is not a stub, since a real `### Verdict` exists.
Not the concurrency race, since the conclusion is `failure` rather than `cancelled`.
Not the self-mod skip, since "Post a notice that self-review was skipped" is itself
`skipped`, which is what proves the guard did not fire.
And not the ~40s zero-cost signature --- the model step ran for over five minutes.

**The tell is the job's own STEP LIST, not any of those fingerprints.**
Read it and find which step actually failed.
When the failing step sits DOWNSTREAM of "Post review comment", the review itself
succeeded and the red check is reporting infrastructure noise about something else.
On the observed run exactly one step of 27 failed, one second after the verdict landed:

| # | step | result |
|---|---|---|
| 4 | Post a notice that self-review was skipped | skipped |
| 11 | Run Claude Code Review | success (310s) |
| 13 | Fail the check if the review did not complete (attempt 1) | success |
| 14-16 | stub-review retry | skipped |
| 20 | Post review comment | success |
| 21 | **Post cost comment** | **failure** |
| 24 | Re-assign reviewers after Claude finishes | success |

Two things in that table do work beyond naming the culprit.
Steps 14-16 being `skipped` rules out the stub-retry path, so the first attempt was
accepted on its own merits.
And step 24 succeeding shows the job kept going past the failure --- only the conclusion
flipped, which is why nothing else about the run looks wrong.

**The remedy is `rerun_failed_jobs`, exactly as for the transient link-checker failure
above --- not a code change, not a re-dispatch, and not a self-review fallback.**
A re-dispatch is actively wrong here: it starts a fresh review from scratch and can lose
the race to the `claude-review-<N>` concurrency group, where a re-run replays the same
job on the same head.
Confirmed transient by that re-run passing on the identical commit minutes later.

- **Do:** read the failing step's name before classifying a red `claude-review`, and treat
  a failure downstream of the verdict post as infrastructure rather than review.
- **Do:** re-run the failed jobs, then re-read the check runs to confirm.
- **Don't:** read a red `require-review` as "no verdict" --- it only ever mirrors
  `claude-review`'s result, so it carries no independent information.
- **Don't:** reach for the self-review fallback while a genuine verdict is already posted.

(`Lacaedemon/sparta` PR #1245, 2026-08-12: job 94049553955 posted a full "Ready for merge"
verdict and then failed on the cost-tally step alone.
`rerun_failed_jobs` on the same head turned both `claude-review` and `require-review`
green, and the cost comment posted normally.)

## A new player-facing GLOBAL state mutation needs a replay-recording check, not just a cosmetic-overlay one

`Replay`'s per-tick tracks (orders, camera, pointer, keys) each capture a specific,
already-anticipated kind of state. A genuinely NEW kind of mid-battle mutation -- one that
touches something outside any Unit's own snapshot fields and outside those four existing
tracks -- has no track to fall into by default, and nothing forces the question of whether
it needs one.

The concrete miss: a slow-motion hotkey (#1097) set `Engine.time_scale` live, with the
mechanism already verified (via a throwaway GUT probe) to scale the DELTA each physics tick
receives, not the tick frequency -- so a mid-battle change to it is exactly the kind of state
that alters simulation OUTCOMES, not just how the battle is drawn. It shipped with no
Replay track for it at all; caught only by review, not by the implementation, even though
the delta-scaling mechanism had already been confirmed empirically in the same PR.

**How to apply:** before shipping a new player-facing toggle/hotkey, ask explicitly: does a
saved-and-reloaded replay of a battle that used this feature reproduce the SAME simulation,
not just look the same? If the answer isn't obviously yes -- if the state lives outside a
Unit's own snapshot fields and outside the existing order/camera/pointer/key tracks -- it
needs its own tick-stamped Replay track (mirroring `_orders`' record/dispatch/rewind-cursor
shape), not a cosmetic one; `_camera_track`/`_pointer_track`/`_key_track` are all explicitly
documented as "never read by the simulation," which is the wrong shape to copy for state
that IS.

**Not cleanly algorithmatizable:** no static check can tell "this new global write matters
for determinism" from "this one doesn't" without understanding what the property actually
does -- it is a design-time question, not a decidable syntactic condition. Treat this
section itself as the check to run by hand on the next new global/live-state feature.

## A self-review comment naming "@claude" in prose can accidentally re-trigger the mention workflow

After three consecutive zero-cost `claude-review` failures (per the section above -- a
genuine hard SDK error, not quota), the documented fallback is to post a self-review and
move on. Writing the self-review's own opening line -- something like "the automated
`@claude` review job did not produce a verdict" -- puts the literal string `@claude` into
the comment body, and `claude.yml`'s `issue_comment` trigger does not distinguish a mention
used to REFER to the bot from one used to SUMMON it. The comment posts fine, and moments
later a second workflow run fires (`event: issue_comment`), attributed to whichever mention
pattern matched.

This is harmless when the run itself then fails the same zero-cost way (it did here, so
nothing further got posted) -- but it is not something to rely on. A run that succeeded
would dispatch a live agent against the PR with the self-review's own text as its prompt
context, which is not what posting a review summary is for.

**How to apply:** when writing a self-review comment (or any PR/issue comment) that needs
to refer to the bot by name rather than summon it, avoid the literal `@claude` token --
write "the Claude review job" or similar, or if the mention is unavoidable, break it up
(e.g. a code span: `` `@claude` ``) so it reads as a literal string rather than a mention.
Check `gh api repos/<owner>/<repo>/issues/<N>/comments --jq '.[-1]'` for a stray
"Picked up by workflow run" acknowledgment after posting a self-review, and read that run's
outcome before assuming nothing happened.

## Before fixing a finding by clearing state, list every OTHER caller of the function you are clearing it in

The narrow lesson --- implement exactly what a review asked for and no more --- has now
produced four regressions in this repo across two PRs, so the prose version is not enough
on its own. What actually catches it is one mechanical question, asked before the edit:

> Which other call sites reach this function, and does the state I am about to clear mean
> something different for them?

The failure shape is always the same. A review names a real defect ("cancelling an order
does not stop the unit"). The obvious fix is to clear the stale execution state. The
function that seems to own that state turns out to be **shared**, so the clearing lands on
callers the finding never mentioned, and their behaviour changes silently --- no conflict,
no failing test, nothing in the diff that looks wrong.

**PR #1125 (2026-07-28)** was the first instance: an unprompted extra reset added to
`Unit._start_promoted_move()` defeated the `ENGAGED_FRACTION_ABOVE` disengage guard,
contradicting the field's own doc comment, which states the opposite contract in as many
words.

**PR #1196 (2026-08-07)** produced three more, all from a single round-1 fix that added
four clears to `Unit._interrupt_current_order()`:

1. `_move_order_peak_engaged_fraction = 0.0` --- the *same field and same guard as #1125*,
   defeated again, from a different function one call earlier.
2. `target_enemy = null` / `support_target = null` --- the severe one.
   `_interrupt_current_order()` is reached from `set_current_order()`, which **every fresh
   order in the game goes through**, and `Battle._apply_order_cmd` writes those two fields
   immediately *before* calling it for the ATTACK, SUPPORT and relief-fallback branches
   (`Battle.gd` 2086-2091, 2096-2099, 2133-2136). So a fresh attack order on any non-idle
   unit had its own target nulled a moment after assignment, and `_update_current_order()`
   retired the order on the next tick. Ordering a busy unit to attack silently did nothing.
3. `SelectionManager.cancel_selected_order_at` applied one order-tree row index across every
   selected unit's own queue, while the tree it indexes is built from a single unit
   (`_hud.show_unit(_selected[0], ...)`).

**The check, concretely.** Before adding a clear/reset to a function in order to fix a
finding:

```bash
grep -n "_the_function_name(" scripts/*.gd        # every caller, not just the flagged one
git show origin/main:scripts/Unit.gd | sed -n '<range>p'   # what did it do BEFORE this PR?
```

If more than one caller reaches it, the clearing usually belongs in the *specific* caller
the finding is about, not in the shared function. In #1196 the fix was to move all four
clears out of `_interrupt_current_order()` and into `cancel_order_at()`, which is the one
caller with no incoming order to supply fresh state --- and to leave a comment at *both*
sites saying why the split exists, since the natural tidying instinct is to put them back.

**Two things that do not catch this.** CI stays green: the reverted or cleared state is
internally consistent, and the existing suite has no test for "a fresh order on a busy
unit". And a field's doc comment stating the contract does not prevent it either --- #1125
and #1196's first regression both contradicted a doc comment that said the opposite
explicitly. Only enumerating the callers, or a test that exercises the other caller, does.

**When you do fix it, prove the guard bites.** Re-introduce the clearing, confirm the new
test fails, then restore. Every guard added for the three #1196 regressions was verified
this way; without it a regression test is a guess about what it covers.

## `UnitCombat.register_casualties` never subtracts `soldiers` itself -- the caller must

Its own doc comment says exactly this ("Apply the consequences of `total` casualties
ALREADY subtracted from `u.soldiers`"), but it's easy to miss on a skim, since the
function DOES read `u.soldiers` (to decide annihilation) and DOES look like the natural
one-call way to "kill N soldiers." A call site that passes a live headcount without
subtracting it first has `u.soldiers <= 0` stay false forever, so the ANNIHILATED branch
(`u._die()`) never fires -- the unit keeps re-entering the same casualty-registration call
every subsequent tick if the caller's own trigger condition is still true, applying morale
erosion and dropping Fallen markers repeatedly with the unit never actually dying.

The two existing call sites both subtract first: `UnitCombat.take_casualties`
(`u.soldiers -= total` then `register_casualties(u, total, ...)`) and the original
`disengage_with_sacrifice` (`soldiers -= sacrifice_count` then the same call). A NEW call
site (#1041's rearguard-detachment lifetime timeout, in `Unit._physics_process`) missed
this and called `register_casualties(self, soldiers, null, 1.0)` with `soldiers` still
untouched -- caught immediately by
`test_rearguard_is_removed_after_its_lifetime_if_not_destroyed_first`, which timed out
waiting for `state == DEAD`. Fix: `var lost := soldiers; soldiers = 0;
UnitCombat.register_casualties(self, lost, null, 1.0)`.

**How to apply:** before adding a new `register_casualties` call site, grep for it first
and read its own doc comment, not just its name -- and always zero (or reduce) `soldiers`
yourself immediately before the call, in the same statement block.

## Editing a source file while a background `check.sh` is still running invalidates the
## run -- and can corrupt the `.godot/` import cache, not just the run's own results

The existing "never `git checkout` in a worktree while a Godot job is still running
there" entries above cover a branch SWITCH as a second writer. An in-place source EDIT
(via any tool, not just a checkout) is the same hazard: the running Godot process reloads
GDScript from disk as it goes, so editing `scripts/Unit.gd` mid-suite mixes old and new
content into whatever that run reports.

**What's new here, beyond "the run's results are unreliable":** a mid-run edit can leave
the gitignored `.godot/` cache itself in a state that produces wrong data on the NEXT,
otherwise-clean run too -- a fresh Godot process started well after the contaminated one
exited reported script errors at line numbers that didn't match the current file content
at all (`_spawn_rearguard_detachment` reported failing at line 1536; the function starts
at line 1196 on disk). Deleting `.godot/` (gitignored, regenerated by `--headless
--import`) and re-importing before the next run resolved it.

**How to apply:** never edit a file this session is actively testing while `Get-CimInstance
Win32_Process -Filter "Name LIKE '%Godot%'"` shows a live process -- that includes fixing a
finding from your own self-review mid-run, not just switching branches. If you catch
yourself having done it anyway, don't trust that run's output even if it exits 0 with no
errors: `rm -rf .godot`, re-import, and re-run clean before acting on anything it reports.
(`Lacaedemon/sparta` PR #1234, 2026-08-09: found and fixed a real test-fixture bug while a
background `check.sh` run was still going; discarded that run, wiped `.godot/`, and a
from-scratch re-run surfaced a genuine, different bug -- see the next entry.)

## A NEW code path reached from `enqueue_*`/`_apply_order_cmd` needs a repo-wide grep for
## every bare-`Battle` test fixture that could reach it, not just the file you're already
## editing

`test_disengage_with_sacrifice_maneuver.gd`'s own bare-`Battle` fixture (`BattleScript.new()`
with no `add_child_autofree`, so `@onready var _units` never resolves) was already fixed for
this exact reason earlier in the same PR. `test_selection_manager.gd` builds its OWN,
separate bare-`Battle` fixtures for its `SelectionManager`-dispatch tests (many of them,
across the file), and two of those tests dispatch `Shift+Ctrl+Down` /
`_issue_disengage_with_sacrifice()` through to the identical `enqueue_disengage_with_sacrifice`
code path -- so they hit the identical null-`_units` crash the moment the maneuver started
spawning a real sub-unit, and nothing about fixing the first file's fixture touched this one.

Both tests passed before this PR (the maneuver only ever mutated the ordering unit's own
fields) and crashed only once the maneuver started calling `_units.add_child()` -- so this
wasn't a pre-existing gap the diff exposed, it was a new crash the diff's own change caused
in a file the diff never touches.

**How to apply:** before considering a new `Unit`/`Battle`-spawning code path's test coverage
complete, `grep -rl` the whole `test/unit/` tree for whatever entry point reaches it (the
order-mode sentinel, the `enqueue_*` function name, the hotkey dispatcher), not just the test
file you already wrote or already fixed -- a sibling file's own bare-`Battle` fixture can reach
the same path through a completely different call chain (here: a hotkey dispatch test, not a
maneuver test). This is the same "even well-documented anti-patterns get re-violated" class
already in this file, recurring a third time on this exact fixture shape.
(`Lacaedemon/sparta` PR #1234, 2026-08-09: caught only by a from-scratch full-suite run, not
by the two test files the PR's own diff touched.)

## Mentioning Jules in a PR comment does not start a Jules dev round from this session's identity

The Jules bot (`google-labs-jules[bot]`) does not react to an @-mention posted
by this session, however the request is phrased.
Observed on PR #1227 (2026-08-13): a comment explicitly asking Jules to
iterate on its own Bolt PR (comment 5276108300) drew zero reactions, no
reply, and no push over several hours -- the branch head stayed at the
pre-comment commit until this session pushed its own work.

The likely mechanism (inferred, not verified against Jules's docs): comments
from an agent session post under the repo owner's `d-morrison` login, while
this repo's Jules tasks are started by a different account (`dem-extra1`) --
and Jules only acts on instructions from the account that owns its repo
connection, ignoring everyone else as a security gate.

**How to apply:** don't spend an ARDIA round posting or re-posting "Jules,
please address the review" comments and waiting -- there is no evidence any
number of them works from this identity.
Either surface to the user that a Jules round needs THEM to start a task
(from the Jules console, or a mention from the integration-owner account), or
implement the review findings directly on the bot's branch yourself, which is
the fallback that worked on #1227 (demo authored, loop-hoist folded in,
driven to a clean verdict, merged).

## Two spellings of a square root are not interchangeable -- `overlap_frac` amplifies the last bit

`Vector2.length()` computes `sqrtf()` at float32.
GDScript's global `sqrt()` takes and returns a GDScript `float`, which is a double,
so `sqrt(offset.length_squared())` widens the float32 sum and rounds the root in
double instead.
The two agree to about 1 ULP of float32 and disagree in the last bit -- which reads
as "algebraically identical, therefore interchangeable" right up until a battle
diverges.

What makes this sim unusually sensitive is where that bit lands.
`SoldierEnemyContact.accumulate` computes `overlap_frac = (min_dist - d) / min_dist`
for every touching pair, and at a shallow first-contact overlap `min_dist - d` is the
difference of two nearly-equal numbers.
That is catastrophic cancellation: a last-bit change in `d` becomes a large relative
change in `overlap_frac`, which feeds `SoldierCollision.enemy_contact_impulse`, so the
two runs' velocities part company on the tick contact is made and every later tick
compounds it.

`CLAUDE.md`'s backend-only-performance section already says "'Backend-only' is the
claim under review, not a licence to skip the clip".
This is the mechanism behind that stance rather than a second instance of it: the
claim fails here not because the rewrite was careless but because **the same value**
and **the same bits** are different claims, and only the second one keeps a replay
deterministic.
So a rewrite of a distance, an angle, a normalization, or any other quantity feeding
a subtraction of near-equals owes a bit-identity check, not a reasoning pass.

The cheapest such check is the one #1255 used: run the same scenario on the branch and
on the merge-base and compare the per-tick state hashes
(`DemoStateHash`/`DemoHashStream`, via `tools/demo/analyze_transcript.gd
--compare-hashes`), which reports the first diverging tick rather than a plausible-looking
"looks the same" verdict.

- **Do:** treat any change to how a physical quantity is COMPUTED as bit-affecting
  until a hash comparison says otherwise, even when the algebra is unchanged.
- **Do:** look specifically for a subtraction of near-equals downstream of the value
  you changed -- that is what converts a last-bit difference into a visible one.
- **Don't:** substitute `sqrt(v.length_squared())` for `v.length()`; they round in
  different precisions and this sim reads the difference.
- **Don't:** accept "same math, so same result" for a float path -- that argument is
  about the reals, and the sim runs on floats.

(`Lacaedemon/sparta` PR #1255, 2026-08-13: `9045331`'s predecessor `33abeda` made
exactly this substitution as a backend-only speedup; the divergence is what commit
`c60de6d` was written to fix.
The float32-versus-double mechanism is recorded in issue #1256;
PR #1257 separately verified against Godot's own 4.7-stable source that
`Vector2::length()` is `Math::sqrt()` over the identical sub-expression
`length_squared()` returns, with no widening between them, and re-checked it in-engine
with 2M probes.)

### A verification probe must name the precision domain, or it measures the rejected design

The entry above is the fact.
This is what the fact does to any probe written to CHECK it, and the failure is
worse than not probing at all, because it returns a confident **REFUTED** against
a design that is correct.

The mechanism is that the two spellings are not merely different --- one of them
is the one the codebase deliberately does not use.
So a probe reaching for the natural GDScript form, `sqrt(...)`, is computing in
**double**, which is the rejected path.
It is then comparing a double-precision result against a float32 threshold and
reporting the disagreement as a defect in the shipped code.
Every part of that run is real: the probe executes, the numbers are genuine, and
the verdict is about a computation nobody ships.

Nothing about the output says so, which is what makes it expensive.
A refutation reads as the strongest possible finding, so the natural response is
to reopen the design rather than to reread the probe --- and the probe is where
the error is.

State the domain in the claim itself, not in the code that tests it.
"`Vector2.length()` is monotonic in `length_squared()` across the band" names
float32 and is checkable; "the square root of the squared distance stays within
the band" names nothing and will be implemented in whichever precision the
language makes convenient.

- **Do:** write the precision domain into the claim, so a probe that drifts out
  of it is visibly answering a different question.
- **Do:** prefer a claim about the operation actually shipped (`Vector2.length()`,
  `length_squared()`) over one about the mathematical quantity it approximates.
- **Don't:** reach for global `sqrt()` in a probe verifying float32 behaviour ---
  it is a double, and it is specifically the spelling the entry above rejects.
- **Don't:** reopen a design on a single REFUTED verdict without re-reading which
  precision the probe ran in; that check costs one line and the reopening does
  not.

(`Lacaedemon/sparta` PR #1257, 2026-08-16: the first cut of the band's
verification specified claim 1 as a statement about the square root rather than
about `Vector2.length()`, implemented it with global `sqrt()`, and returned
REFUTED.
Re-specified as monotonicity of `Vector2.length()` against `length_squared()`,
the same 2M-probe run verified with 0 inversions and a worst-case margin of about
419 float32 ULP.)

## When a cheap test GATES an exact one, fix the PREDICATE, not the VALUE

The obvious repair for the entry above is to recompute the exact value on whatever
survives the cheap test -- take `offset.length()` again for pairs the squared
comparison let through.
That fixes the **value** and leaves the **predicate** wrong: a squared comparison is
still deciding WHICH pairs survive, and at the boundary it can disagree with the exact
test about that.
A pair the exact test would call touching can be dropped before the exact test ever
runs, and no amount of recomputing on the survivors recovers it.

The shipped fix makes the cheap test **one-sided** instead: `SQRT_SKIP_BAND` scales the
squared threshold so the guard only ever skips pairs the exact test would also reject,
and every pair inside the band still takes `d >= min_dist` unchanged.
That is what makes the pass bit-identical to the pre-skip version rather than merely
equivalent to it -- the cheap comparison never decides a pair's fate, it only decides
whether the square root is worth computing.

The general shape is worth carrying past this one function, because the repo is full of
cheap-test-in-front-of-exact-test pairs.
`SoldierSpatialHash.query`'s neighbourhood lookup is one, in this very loop -- it hands
`accumulate` a candidate set that the pair tests then filter exactly.
`analyze_transcript.gd --compare-hash-trees` is another, and its own docstring names it
as such: it is "website-demo-diff.yml's fast pre-filter", where a per-tick hash compare
decides which clips get the expensive field-level analysis.
In every such pair the cheap test is sound only if it is proven one-sided in the
direction that cannot lose a member.
Sizing its slack is then headroom rather than the argument -- see `SQRT_SKIP_BAND`'s own
doc comment, whose first version sized the band against a rounding gap and had to be
rewritten (#1256/#1257) once the one-sidedness was argued from monotonicity directly.

- **Do:** ask which pairs a new fast path REMOVES from consideration, separately from
  what value it computes for the ones it keeps.
- **Do:** state the direction the cheap test is allowed to err in, and make its slack
  large enough that the error can only fall that way.
- **Don't:** treat "the exact test still runs on the survivors" as proving equivalence
  -- that is a claim about the value, and the survivor set is the other half.
- **Don't:** tune a prefilter's slack until the observed outputs match; a band chosen
  that way is a bound nobody has argued, and the next input distribution moves it.

(`Lacaedemon/sparta` PR #1255, review rounds 2-4, 2026-08-13/14.)

## A bot push can drop what earlier REVIEW ROUNDS added, and the trial-merge check cannot see it

The `main`-revert entry above (PR #1194) says to trial-merge a bot-pushed head onto
`main` and treat a large deletion count as a revert.
That is the right check for the failure it describes and it is structurally blind to
this one, so the two need keeping apart rather than collapsing into "check Jules's
pushes".

On PR #1255, `google-labs-jules[bot]` pushed `9045331` mid-review, re-implementing the
same square-root skip from scratch.
It silently replaced the named `SQRT_SKIP_BAND` const with a bare `1.0001` literal, and
deleted `demos/demo.1255.json`.
Both had been added by that PR's own earlier review rounds -- so neither had ever
existed on `main`, and `main` had nothing to lose.
Measured against the merge-base `6427bb0`:

| comparison | diffstat |
| --- | --- |
| merge-base -> bad head `9045331` | 2 files, **7 insertions, 3 deletions** |
| merge-base -> good head `d243fb0` | 3 files, 37 insertions, 3 deletions |
| previous head `7ac2901` -> bad head `9045331` | 2 files, **3 insertions, 33 deletions** |

Three deletions against `main`, on a head that reads as an entirely ordinary
optimization.
The instrument that does catch it is in the third row: **diff the new head against the
PREVIOUS head**, which is the one comparison that can see content the branch used to
have.

The previous head is a SHA you already hold -- it is whatever your last round verified,
and the PR's own commit list has it if you did not write it down.
Note also that the loss here was not a behaviour change: the mechanism `9045331`
shipped was the same one, so a hash comparison, the tests, and CI would all have passed.
What went missing was a named constant, an explanatory comment, and a required demo
manifest -- exactly the class of thing review rounds add and nothing downstream
enforces.

- **Do:** diff a bot-pushed head against the head your last review round verified, not
  only against `main`.
- **Do:** re-check that this PR's own review-round artifacts are still present -- the
  demo manifest, named constants, the comments a finding asked for.
- **Don't:** read a small, plausible diffstat against `main` as evidence nothing was
  dropped; content added on the branch is invisible to that comparison by construction.
- **Don't:** treat this as covered by the #1194 trial-merge rule -- that one detects a
  revert of MERGED content, and this is a revert of REVIEWED content.

(`Lacaedemon/sparta` PR #1255, 2026-08-14: `9045331` at 00:04Z, restored by `d243fb0`
at 00:10Z.
Fourth `google-labs-jules[bot]` incident in this file, after #1176, #1194,
and #1227 -- the third where a Jules PUSH damaged content, since #1227 is the
same bot's non-response failure mode rather than a push, and the first whose
failure shape the existing checks miss.)

## A guard test's fixture goes vacuous when two DERIVED counts coincide by accident

This file already documents a guard test that is vacuous only under full-suite ordering (a
frame-keyed static cache serving it another test's data). Here is a second, unrelated mechanism
for the same outcome, and it bites in a SINGLE-test run where that one does not: the test asserts
that some value is still `X` rather than the `Y` the bug would have written, and the fixture
happens to make `X == Y`. Both branches then satisfy the assertion, so the test passes against the
bug and against the fix alike while reading as a precise regression guard.

It is specifically a hazard for a guard whose two sides are **derived** from the fixture rather
than written into it, because then nothing in the test spells either number out. `Unit`'s file
counts are the worked case: `_file_assignment_files` holds the line frontage, and the bug would
overwrite it with `UnitFormation.square_files(count)`. On the existing 60-man / 8-file fixture in
`test_reform_ranks.gd`, `square_files(60) = ceil(sqrt(60)) = 8` --- the same 8 --- so the guard
had nothing to detect. Rebuilding at 50 men / 10 files, where `square_files(50) = 8` cannot equal
10, made it discriminate.

**Assert the two counts differ as an explicit precondition, and prove the guard bites.** The
precondition is what caught this: the fixture's own `assert_eq(u._file_assignment_files, -1, ...)`
failed with `[8] expected to equal [-1]` and exposed that `seed_sim_soldiers()` had already dealt
an assignment, which is what led to noticing the coincidence at all. Then remove the guard and
confirm the failure names the right two numbers --- here `[8] expected to equal [10]`, which reads
as the square count displacing the line count and could not be produced by any other defect.

- **Do:** pick fixture numbers where the two derived counts provably differ, and assert that
  difference in the test as a precondition.
- **Do:** read a failing precondition as information about the fixture rather than an obstacle
  to edit past --- it is frequently reporting exactly this.
- **Don't:** trust a guard test whose two sides are derived and never spelled out, until you have
  seen it fail with both numbers visible in the message.

(`Lacaedemon/sparta` PR #1263, 2026-08-16:
`test_hold_ground_reform_leaves_a_squared_units_file_assignment_untouched`.)

## If local Godot version differs from project target -- check versions before diagnosing test failures

Godot binary major.minor version is a property of the local container/environment, not a global invariant. If the local binary major.minor differs from `project.godot`'s `config/features` (e.g. 4.6.x vs 4.7), vendored GUT v9.7.0 may fail to parse `AccessibilityServer` (a 4.7 singleton) and emit `SCRIPT ERROR` lines.

To check version compatibility in one command:
```bash
godot --version                       # or "$GODOT_BIN" --version
grep '^config/features=' project.godot
```

PR #1305 (closing #1271) added an explicit version check to `tools/check.sh`, which now compares the local binary version directly against `config/features` and fails fast with a version error if they mismatch. Therefore, any `FAIL test` returned by `check.sh` after #1305 is a real failure (not a hidden version mismatch).

