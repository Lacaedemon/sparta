## Melee outcomes are chaotic, so a per-clip check can't tell a regression from chance

The investigation for #1792 ran a control on main 45a9bb85.
It nudged each unit's facing by 0.0001 rad, once, at the unit's first melee snap.
That alone changed:

- whether the routers in `spear_standoff`, `file_major_reform_contrast` and `charge` escape or are cut down;
- when `showcase` uid 2 dies (60 ticks earlier);
- when `march_to_contact` breaks (tick 740 instead of 660).

Any change that touches melee dynamics therefore flips per-clip router and casualty outcomes somewhere in the catalog.
This holds whether or not the change does harm.
#1826 tracks building a several-seed or perturbed comparison to judge such changes instead.

- **Do:** before reading a single clip's changed router outcome as a regression, check whether a negligible perturbation of main moves it too. Report the mechanism you measured, not only the outcome.
- **Don't:** treat "no router breaks later than main on any clip" as a pass or fail gate for a change to melee dynamics.

(`Lacaedemon/sparta` #1792 and #1826, 2026-10-12.)

## Before adding hysteresis to a flag, list everything that reads it

PR #1822's (#1801) first version put a re-entry gap on `_in_enemy_contact` to stop a router's anchor flip-flopping.
That flag also gates physics.
`contact_soldier_indices` and `SoldierEnemyContact` resolve body contact only for units flagged in contact.
The separation rule in `Unit.gd` falls back to non-contact spacing.
In `rout_rally` the router's bodies passed through its pursuer's on 133 routing ticks, against 1 on main.
The merged fix put the gap on a separate anchor-only flag, and every physical reader still reads the unmodified one.

- **Do:** `git grep` every reader of a flag before changing when it turns on, and put behaviour-specific hysteresis on a new flag read only by the behaviour it fixes.
- **Don't:** add hysteresis to a shared state flag because the bug shows up in one of its readers.

(`Lacaedemon/sparta` PR #1822, 2026-10-12.)

## Narrow a fix to the cases that need it rather than exempting what it breaks

PR #1814's (#1806) first version lagged the slot grid behind every small facing change.
Across 36 clips this held routers in the melee, and it stopped `cycle_charge`'s caracole re-charge from landing.
Its author first proposed exemptions with a pre-existing cause for the new rows.
The review measured the opposite.
Each round narrowed the scope to what the issue needed: no lag in contact, then no lag for combat re-faces, then lag only on marches the player ordered.
The merged PR changes 6 clips, its other clips are bit-identical to main, and the issue stays open for the combat cases.

- **Do:** when a fix trips acceptance checks on clips outside its target, shrink the fix's scope until those clips are bit-identical to main, and leave the remainder of the issue open.
- **Don't:** exempt a new defect the change causes, or credit it to a cause the data contradicts.

(`Lacaedemon/sparta` PR #1814, 2026-10-12.)
