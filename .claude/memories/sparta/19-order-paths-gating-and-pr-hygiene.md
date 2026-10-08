
## Gate a sim fix to the exact case it targets

PR #1727 first re-paired men after any fold `reform_ranks` drops except an about-face.
The website demo diff flagged 6 changed clips and 2 candidate regressions.
`battle_ai_leaders` uid 3 read `shape_residual` 88.5 (merge-base 4.2), and `disengage_sacrifice_rearguard` uid 1 read 32.9 (merge-base 0).
A temporary `print` in `reform_ranks` (`Unit.gd`) showed the call firing on 68, 112 and 156 degree folds left by `_face_dir`'s snap-absorb.
Gating to a fold within 0.01 rad of +/-PI/2 made `cannae_scale`, `disengage_sacrifice_rearguard`, `knockback_focus` and `rout_rally` hash bit-identical to main.
CI then reported 1 changed clip, with no new defects.
The adversarial pre-push review had called the broad gate a nit, and it was documented instead of measured.

- **Do:** gate a sim fix to the exact case it targets, then instrument the call site and compare per catalog clip: dump each with `tools/demo/dump-state.sh <input> <last-tick> <dir>` on the branch and on main, then run `analyze_transcript.gd -- <branch-dump> --compare-hashes <main-dump>`.
  One tick suffices, because the hash stream covers every tick.

- **Don't:** write an "everything except X" gate, which reaches cases the tests never exercise, or document a gate's breadth as a nit instead of measuring it.

(`Lacaedemon/sparta` PR #1727, 2026-10-05.)

## Patch a PR description from its live text

CI inserts a marked demo section into the PR body, delimited by `sparta-demo` HTML-comment markers.
PATCHing the body from a draft written earlier erased that section on #1727, and only a later push's demo run restored it.

- **Do:** fetch the live body (`gh api repos/Lacaedemon/sparta/pulls/N --jq .body`), edit that text, confirm the marker count is unchanged, then `gh api -X PATCH ... -F body=@file`.

- **Don't:** PATCH a body rebuilt from an earlier draft.

(`Lacaedemon/sparta` PR #1727, 2026-10-05.)

## Include `lint` in local check runs

`tools/check.sh` has a `lint` target that mirrors CI's `check-gdlint.yml` with gdtoolkit 4.5.0.
A check list without it let a gdlint naming failure reach CI on #1730: trailing-underscore argument names such as `unit_`.
After `pip install gdtoolkit==4.5.0`, `gdlint.exe` may sit in the Python user Scripts directory, off PATH, on Windows.

- **Do:** add `lint` to the same `tools/check.sh` invocation, and verify it actually ran rather than skipped.

- **Don't:** treat a PASS on the other targets as covering style lint.

(`Lacaedemon/sparta` PR #1730, 2026-10-05.)

## Every `Unit.move_target` writer is order-derived

The writers found by `grep -n "move_target = " scripts/` (plain assignments, excluding the `_move_target` backing field) are:

- `Battle._apply_order_cmd`, at three sites.
- `Unit._start_promoted_move`, `_arm_withdrawal_turn`, `_finish_order_turn` and `_finish_wheel`, which advance `current_order` and its leaves.
- `Unit._commit_pending_reform`, the reform leaf.
- `Unit.disengage` and `Unit.disengage_with_sacrifice`.
- `UnitRelief` (the tired unit's retreat) and `UnitReinforce` (the reserve's rendezvous), both started by `Battle` from a relief or reinforce order.

The per-tick auto-advance toward a detected enemy goes through `_move_to` and never writes `move_target`.
That is why the order-outcome report (PR #1730) can hang off the setter without toasting for autonomous movement.

- **Do:** re-run that grep beside any claim about who writes `move_target`, and keep a new writer order-derived.

- **Don't:** add a writer for autonomous movement without changing the report gate.

(`Lacaedemon/sparta` PR #1730, 2026-10-05.)

## Commit message figures are immutable

On #1727 the commit message said the centre "stays within ~8 wu of the order line through tick 400", but the dump showed 13 wu (37 on main).
A reviewer caught it.

- **Do:** re-read every number in a commit message against the measurement output it came from before committing, and correct a wrong one in the PR description.

- **Don't:** quote a figure from memory or from an earlier run into a commit message.

(`Lacaedemon/sparta` PR #1727, 2026-10-05.)

## Run the adversarial pre-push review BEFORE `tools/check.sh`, not beside it

Every finding the adversarial review returns forces an edit,
and editing while `check.sh` runs is already ruled out
(part 07, "Editing a source file while a background `check.sh` is still running").
So running the two side by side throws the suite away whenever the review finds anything:
on PR #1737 two full `check.sh` runs were discarded this way.
Stopping the abandoned run is its own trap:
`TaskStop` ends the harness's background shell
but leaves the `check.sh` bash and GUT processes alive.
For a tree you started yourself, `taskkill /PID <check.sh pid> /T /F` ends it
(the classifier denied it once and allowed the retry),
then re-list the process table.
Part 05's item 5 still governs a stray process another agent started: do not kill it.

- **Do:** get the review's verdict on the committed head first,
  apply its findings, commit,
  then start `tools/check.sh` once on the final head.

- **Don't:** start the review and `check.sh` together to save wall-clock time.

(`Lacaedemon/sparta` #1733 / PR #1737 and #1731 / PR #1740, 2026-10-07/08.)

## Commit before mutation-testing; undo a mutant by its exact inverse

Reverting a mutant with `git checkout -- <file>` restores the last committed version of the whole file,
so it wiped an uncommitted fix on PR #1737.

- **Do:** commit the fix first, then mutate, and restore from that commit
  (or undo the mutation with its exact inverse edit).

- **Don't:** run `git checkout -- <file>` to un-mutate a file that holds uncommitted work.

(`Lacaedemon/sparta` PR #1737, 2026-10-07.)

## `Unit._quarter_turn_fold` is a record of net drill turns; every other fold write clears it

`Unit._quarter_turn_fold` holds the net turn of the QUARTER_TURN leaves
settled into `_formation_angle` since anything else last moved it,
so `reform_ranks` can re-pair a quarter-turn composed onto a residue fold.
Every other write to the fold clears it:
snap-absorb, engage re-face, a non-quarter drill,
a reform or its already-square early return,
the explicatio's quarter-fold transpose, and a rout.
A snapshot restore restores it alongside the fold.
Composed folds in the explicatio and about-face gates are still open (#1741).

- **Do:** make a new write to `_formation_angle` either add to `_quarter_turn_fold` or clear it,
  and say which in a comment.

- **Don't:** write `_formation_angle` without touching the record:
  a stale value re-pairs men through a fold that no longer measures a quarter.

(`Lacaedemon/sparta` #1731 / PR #1740, 2026-10-08.)

## `PathField` room cap: a real destination's room is measured per axis

`PathField._segment_blocked` caps each rect's margin at the room a REAL destination leaves,
so an order the clamp accepted stays reachable.
That room is `_grow_room`, which uses `Rect2.grow`'s own per-axis metric:
the grown rect is square-cornered, so a straight-line room grew the corner over a destination diagonal off it.
`_first_blocking_rect_index` uses the same metric.
Everything else keeps main's straight-line room (`_distance_to_rect`):
the start of every leg,
`next_step`'s corridor fallback (`_corridor_sightline_blocked`, whose target is a synthetic cell centre),
and the candidate sightlines, which are uncapped (`cap_to` false).
The start-room limitation is tracked in #1743.

- **Do:** measure a real destination's room with `_grow_room`,
  and leave the start, the corridor fallback and the candidate sightlines as they are.

- **Don't:** measure a destination's room in a straight line:
  off a hill corner it grows the rect over the destination, and every leg to it reads as blocked.

(`Lacaedemon/sparta` #1729 / PR #1738, 2026-10-08.)

## A cap with several caller classes names the class explicitly

`_segment_blocked`'s `cap_to` alone conflated a real destination with the corridor fallback's synthetic cell centre.
Before the corridor fallback was gated, a local catalog comparison changed 14 clips;
after gating it with `to_is_destination` and the named wrapper `_corridor_sightline_blocked`,
the same comparison changed 2, and CI's website demo diff changed 1.
So the fallback accounted for 12 of the 14 (inferred from the before/after difference).
This is a sharper case of "Gate a sim fix to the exact case it targets" at the top of this file.

- **Do:** name the caller class with a named helper (or a named argument) at the call site,
  so each class picks its own metric on purpose.

- **Don't:** leave a bare positional boolean at a call site to decide a metric:
  a tidy-up can flip it with the unit suite still green.

(`Lacaedemon/sparta` #1729 / PR #1738, 2026-10-08.)

## Stop chasing a "make it symmetric" review fix after its second regression

A review asked for the start room to be measured per axis too, the mirror image of the destination fix.
Two attempts each regressed a catalog clip:
measuring it on every leg stalled `campaign_deployment_gap`,
and measuring it on real-endpoint legs only left `funnel_lanes` never reaching IDLE.
The start room sets the whole leg's margin and decides whether candidate corners are accepted, so it is a separate change.

- **Do:** after the second regression, scope back to the issue's exact case and file the rest with both traces (#1743).

- **Don't:** try a third narrowing in the same PR.

(`Lacaedemon/sparta` #1729 / PR #1738, 2026-10-08.)

## Re-run the full catalog hash comparison after every metric change

The whole-catalog comparison is `website/tools/dump-demo-states.sh` on both trees, then `analyze_transcript.gd --compare-hash-trees`
(the per-clip recipe in "Gate a sim fix to the exact case it targets" is `--compare-hashes`).
On #1738 it caught both regressions above, neither of which the unit suite saw, and it showed the effect of the fallback gating.
A local 0.3 wu drift in `showcase` did not reproduce in CI's transcript.

- **Do:** re-run it after each change to a metric or gate, not once per PR,
  and confirm a sub-wu late-divergence row on CI's comment before treating it as real.

- **Don't:** treat a sub-wu late-divergence row seen only in a local run as a regression
  before CI's transcript shows it too; its cause was not established here.

(`Lacaedemon/sparta` #1729 / PR #1738, 2026-10-08.)
