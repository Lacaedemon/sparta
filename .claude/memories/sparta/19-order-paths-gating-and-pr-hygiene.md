
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
