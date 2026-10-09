## Use the dense defect delta for any sim change that alters clips

The catalog-cadence defect delta missed three regressions on PR #1746 that a 2-tick dense delta caught.
`tools/ci/website-demo-defect-delta.sh` takes `DEMO_DEFECT_DENSE_BASE_TREE` (the merge-base checkout) and compares changed clips tick by tick.

- **Do:** set `DEMO_DEFECT_DENSE_BASE_TREE` and run the dense delta for every sim change that moves a clip's state.

- **Don't:** accept a clean catalog-cadence delta as proof a sim change introduced no defects.

(`Lacaedemon/sparta` PR #1746, 2026-10-09.)

## An `expect` claim must fail on `main`, and a hash compare is not a caption check

Three separate misses on PRs #1746 and #1752 (2026-10-09):

- A hash compare reporting "no new defects" does not show a clip still depicts its captioned event.
  The `morale_recovery` rally had moved past the clip's end, so the caption described something no longer on screen.
- Range expects are any-match, so a range claim proves only "at least once".
  Use a single-tick claim, or a position or `absent` claim, that fails on `main`.
- A claim pinning a state the unit spawns in passes before the change, so it cannot show the change.

- **Do:** run each new `expect` against the pre-change tree and confirm it fails there.

- **Do:** view the clip's own frames (or its state dump at the captioned tick) when a sim change shifts timing.

- **Don't:** pin a state the unit spawns in, or rely on a range expect to prove timing.

## Don't choose sample ticks by the verdict they produce

On PR #1746 a sample tick was dropped from the defect check because it read a pursuer regression as sustained.
Choosing samples by the answer they give turns the check into a rubber stamp.

- **Do:** fix a real regression, or record a measured `defect_exemptions` entry (see `demos/charge_demo.defects.json`) naming its tracking issue.

- **Don't:** drop or move a sample tick because it reads badly.

(`Lacaedemon/sparta` PR #1746, 2026-10-09.)

## A stateless drift-free tie-break moves flips; it does not remove them

PR #1755 ranked funnel corners by cell centre, a stateless drift-free rule.
All 65 catalog flips stayed, relocated onto grid lines.
A stateless rule flips wherever its inputs cross a threshold, so only state (hysteresis) removes flips; that is tracked in #1756.

- **Do:** count flips before and after a tie-break change over the whole catalog and report both numbers.

- **Don't:** claim a stateless ranking eliminates flipping because it removes drift.

(`Lacaedemon/sparta` PR #1755, 2026-10-09.)

## Make the caller class explicit in PathField, and let the catalog compare gate a broadening

`PathField.Leg {ORDER, CORRIDOR_CELL, CANDIDATE}` names the caller class of each leg.
A broader "diverging leg" rule regressed `trapped_routing` and was reverted (#1754).
The catalog hash compare is the gate that caught it.

- **Do:** key a path rule on the explicit `Leg` class, and run the catalog compare before widening one.

- **Don't:** infer the caller class from geometry ("this leg diverges") in a rule that several callers share.

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

## Briefs: use the default `tools/check.sh` set plus `lint` and `patch_coverage`

A wave brief with a hand-written check list dropped `markdown`.
CI then failed `check-new-line-breaks` and the list-item splice check (#1759).
Under machine load the coverage run needs a larger cap: set `SPARTA_CHECK_COVERAGE_TIMEOUT=5400` (the default is 2700 seconds).

- **Do:** write "the default `tools/check.sh` set plus `lint` and `patch_coverage`" in a brief, and add the timeout variable when several suites run at once.

- **Don't:** hand-enumerate check names in a brief; the list goes stale.

(`Lacaedemon/sparta` PR #1759, 2026-10-09.)

## "Does not close #N" still closes #N

GitHub parses closing keywords without reading negation.
A PR body on #1746 saying "Does not close #N" would still have closed #N on merge.

- **Do:** write "Refs #N" for an issue the PR must leave open.

- **Don't:** put a closing keyword (close, fix, resolve) next to an issue number you want kept open, even negated.

(`Lacaedemon/sparta` PR #1746, 2026-10-09.)
