## Moving state from a flag into a cache inherits every invalidation of that cache

PR #1763's first fix for #1751 baked the about-face mirror into the slot assignment (file ids and the row and square pairings) and cleared the flag.
Review found that `formation_slots` drops that cache on a frontage resize, a ranks-closed narrowing, and any regiment-path casualty (a size mismatch).
Each of those falls back to an identity grid, so the flank swap was postponed, not removed.

- **Do:** before replacing a flag with cached state, grep every fallback that rebuilds the cache (`identity_assignment`, `file_ids_in_index_order`, the size and file-count guards) and make each one honour the state (here `_fallback_mirror_x`).

- **Don't:** enumerate only the flag's writers and stop.

(`Lacaedemon/sparta` PR #1763, 2026-10-09.)

## A hook in `set_current_order` also runs on state Battle wrote one line earlier

Battle's `ORDER_FRONTAGE_ONLY` branch calls `set_frontage(files, offset)` and then `set_current_order(...)`.
On PR #1763 a new bake in `set_current_order` negated the offset just written, so an anchored resize on an idle mirrored block widened the wrong way.

- **Do:** for any new side effect in `set_current_order`, grep Battle's write-then-order branches (`set_frontage`, `set_formation`, stance, nudge) and check the order of effects.

- **Don't:** assume `set_current_order` runs before the command's own state writes.

(`Lacaedemon/sparta` PR #1763, 2026-10-09.)

## A new post-state that carries momentum must be re-checked during it, not only at entry

PR #1762's rally halt (#1749) hands the flight speed to the idle coast.
Its terrain, enemy, and `retreat_bounds` checks ran only at the hand-off.
Review found that `_approach_velocity` stays near flee pace through the coast (a horse pulls up in about 30 m).
`UnitCombat.charge_multiplier` reads `_approach_velocity`, so an enemy arriving mid-coast would meet a charge bonus.
Two more findings had the same shape.
A speed-cap exemption tied to "until every body is at rest" outlived the pull-up and uncapped the whole reform.
A body acceleration raise applied in every direction, not only to braking.

- **Do:** scope a new state's exemptions to the physical phase they model (anchor speed above zero).

- **Do:** list what reads the carried quantity (approach velocity feeds the charge bonus), and re-check those readers during the state.

- **Don't:** gate a cap exemption on an "all bodies at rest" condition that friendly steering can keep false indefinitely.

(`Lacaedemon/sparta` PR #1762, 2026-10-09.)

## A rally hand-off coast changes DemoDefects' superphysical baseline

PR #1762 needed a `rally_halting` dump field and a flee-pace allowance in DemoDefects.
A suggested `max(cap, anchor speed)` allowance falsely flagged `morale_recovery`, where re-paired men keep about 110 wu/s while the anchor brakes well below that.

- **Do:** limit a DemoDefects allowance to the window the new state actually covers (here, the coast).

- **Don't:** widen an allowance to the anchor's speed, which individual bodies can exceed while re-pairing.

(`Lacaedemon/sparta` PR #1762, 2026-10-09.)

## A defect delta cannot see a defect `main` already has

The #1751 demo on PR #1763 passed all 13 verdicts and the dense delta reported no new defects.
The user still saw by eye that the full files stepped back about 0.39 m during the hold-ground re-square.
`main` does the same, because `SoldierBodies.couple()` drags the anchor toward a non-centred block's mean during the turn (#1774).
A delta against `main` is blind to that by construction.

- **Do:** when authoring a demo of a drill maneuver, add an absolute `expect` for what the drill says must not move (for example, full files hold position through a hold-ground re-square), and check it on `main` too.

- **Don't:** treat "no new defects against `main`" plus passing verdicts as evidence the clip shows correct drill.

(`Lacaedemon/sparta` PR #1763 and issue #1774, 2026-10-09.)

## Briefs: gate `tools/check.sh` behind the coordinator's review

In wave 7 the coordinator's briefs twice told a subagent to run `tools/check.sh` before the adversarial review (caught before the suite started).
A review round that finds anything invalidates that run, and the full suite is long (part 20 already raises its coverage timeout to 5400 seconds under load).

- **Do:** end every implementation brief and every fix-round message with "commit, report the full head SHA, and stop: no push and no check.sh until I say so", and send the check.sh go-ahead only after a review with no findings.

- **Don't:** fold "then run check.sh" into a fix-round message to save a round trip, even when the remaining findings look small.

(`Lacaedemon/sparta` PRs #1762 and #1763, 2026-10-09.)
