## Use the dense defect delta for any sim change that alters clips

The regular defect delta samples every 60 ticks.
It missed three regressions on PR #1746 that the dense delta caught.
`tools/ci/website-demo-defect-delta.sh` runs the dense pass when `DEMO_DEFECT_DENSE_BASE_TREE` names the merge-base checkout (CI sets it in `website-demo-diff.yml`).
The dense pass samples every `DEMO_DEFECT_DENSE_STEP` ticks (default 2), from the divergence tick to the clip's end.
It is capped by `DEMO_DEFECT_DENSE_MAX_CLIPS` and `DEMO_DEFECT_DENSE_BUDGET_SEC`; clips past the caps fall back to the regular samples.

- **Do:** for a local check, export `DEMO_DEFECT_DENSE_BASE_TREE` before running the script, and read whether any changed clip fell back to the regular samples.

- **Don't:** accept a clean regular-cadence delta as proof a sim change introduced no defects.

(`Lacaedemon/sparta` PR #1746, 2026-10-09.)

## An `expect` claim must fail on `main`, and a hash compare is not a caption check

Three misses on PRs #1746 and #1752:

- A hash compare reporting "no new defects" does not show a clip still depicts its captioned event.
  The `morale_recovery` rally had moved past the clip's end, so the caption described something no longer on screen.

- Range expects are any-match, so a range claim proves only "at least once".
  Use a single-tick claim, or a position or `absent` claim, that fails on `main`.

- A claim pinning a state the unit spawns in passes before the change, so it cannot show the change.

- **Do:** run each new `expect` against the pre-change tree and confirm it fails there.

- **Do:** view the clip's own frames, or its state dump at the captioned tick, when a sim change shifts timing.

- **Don't:** pin a state the unit spawns in, or rely on a range expect to prove timing.

(`Lacaedemon/sparta` PRs #1746 and #1752, 2026-10-09.)

## Don't choose sample ticks by the verdict they produce

On PR #1746 a sample tick was dropped from the defect check because it read a pursuer regression as sustained.
Choosing samples by the answer they give turns the check into a rubber stamp.

- **Do:** fix a real regression, or record a measured `defect_exemptions` entry (format: `demos/charge_demo.defects.json`) and also name its tracking issue in the entry's reason.

- **Don't:** drop or move a sample tick because it reads badly.

(`Lacaedemon/sparta` PR #1746, 2026-10-09.)

## A stateless drift-free tie-break moves flips; it does not remove them

PR #1755 tried ranking funnel corners by cell centre, a stateless drift-free rule, measured it, and reverted it (the PR ships tests and a skip manifest).
Over the catalog, flips of 10 degrees or more were identical before and after: 65 funnel-to-funnel, 21 corridor-to-funnel and 16 corridor-to-corridor.
The ranking only moved each flip onto a grid-cell boundary.
The root cause is tracked in #1756.

- **Do:** count flips before and after a tie-break change over the whole catalog and report both numbers.

- **Don't:** assume a stateless ranking removes flipping because it removes drift.

(`Lacaedemon/sparta` PR #1755, 2026-10-09.)

## Make the caller class explicit in PathField, and let the catalog compare gate a broadening

`PathField.Leg {ORDER, CORRIDOR_CELL, CANDIDATE}` names the caller class of each leg.
In PR #1752 a broader "diverging leg" rule regressed `trapped_routing` and was reverted.
The limitation is tracked in #1754.
The catalog hash compare caught it.
Which leg the wider rule freed first was not traced.

- **Do:** key a path rule on the explicit `Leg` class, and run the catalog compare before widening one.

- **Don't:** merge a broadened path rule without the catalog compare.

(`Lacaedemon/sparta` PR #1752, 2026-10-09.)

## A new sub-phase inside ROUTING must guard every routing exit

PR #1746 added a rally brake inside ROUTING.
It broke escape, strength, trapped and stamina handling, because each of those is its own exit from the phase, and the brake was removed.
The follow-up is tracked in #1749.
This was the second regression class on the change.

- **Do:** list every way a router leaves or changes the phase before adding a sub-phase, and test each.

- **Do:** after the second regression class, scope back to the issue's exact case and file the rest.

- **Don't:** keep patching exits one at a time inside the same PR.

(`Lacaedemon/sparta` PR #1746, 2026-10-09.)

## Briefs: name the whole `tools/check.sh` target list, defaults included

A wave brief with a hand-written target list dropped `markdown`.
CI then failed `check-new-line-breaks` and the list-item splice check (#1759).
An explicit target list replaces the defaults, so there is no "defaults plus" token.

- **Do:** in a brief, give the literal command with the default targets restated plus `lint` and `patch_coverage` in one invocation, e.g. `tools/check.sh validate test chars comments units file_length shell_tests markdown lint patch_coverage` (the default set is `DEFAULT_CHECKS` in `tools/check.sh`).

- **Do:** under heavy machine load, set `SPARTA_CHECK_COVERAGE_TIMEOUT=5400` (default 2700 seconds), and prefer CI's coverage on the same head if it still times out.

- **Don't:** hand-enumerate a shorter list from memory.

(`Lacaedemon/sparta` PR #1759, 2026-10-09.)

## "Does not close #N" still closes #N

GitHub parses closing keywords without reading negation.
A PR body on #1746 saying "Does not close #N" would still have closed #N on merge.

- **Do:** write "Refs #N" for an issue the PR must leave open.

- **Don't:** put a closing keyword (close, fix, resolve) next to an issue number you want kept open, even negated.

(`Lacaedemon/sparta` PR #1746, 2026-10-09.)
