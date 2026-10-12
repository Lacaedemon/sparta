## Melee outcomes are chaotic, so a per-clip check can't tell a regression from chance

The investigation for #1792 ran a control on main 45a9bb85.
It nudged each unit's facing by 0.0001 rad, once, at the unit's first melee snap.
That alone changed:

- whether the routers in `spear_standoff`, `file_major_reform_contrast` and `charge` escape or are cut down;
- when `showcase` uid 2 dies (60 ticks earlier);
- when `march_to_contact` breaks (tick 740 instead of 660).

So a change that touches melee dynamics can flip per-clip router and casualty outcomes whether or not it does harm.
The control covered one kind of nudge at one moment, so how far the effect reaches beyond it is not measured.
#1826 tracks building a several-seed or perturbed comparison to judge such changes instead.

- **Do:** before reading a single clip's changed router outcome as a regression, check whether a negligible perturbation of main moves it too,
  and report the mechanism you measured, not only the outcome.

- **Don't:** treat "no router breaks later than main on any clip" as a pass or fail gate for a change to melee dynamics.

(`Lacaedemon/sparta` #1792 and #1826, 2026-10-12.)

## Before adding hysteresis to a flag, list everything that reads it

PR #1822's (#1801) first version put a re-entry gap on `_in_enemy_contact` to stop a router's anchor flip-flopping.
That flag also gates physics.
`contact_soldier_indices` and `SoldierEnemyContact` resolve body contact only for units flagged in contact.
The separation rule in `Unit.gd` falls back to non-contact spacing.
So in `rout_rally` the router's bodies walked through its pursuer's while the router counted as out of contact.
The fix the PR shipped puts the gap on a separate anchor-only flag, and every physical reader still reads the unmodified one.

- **Do:** `git grep` every reader of a flag before changing when it turns on, and put behaviour-specific hysteresis on a new flag read only by the behaviour it fixes.

- **Don't:** add hysteresis to a shared state flag because the bug shows up in one of its readers.

(`Lacaedemon/sparta` PR #1822, 2026-10-12.)

## Narrow a fix to the cases that need it rather than exempting what it breaks

PR #1814's (#1806) first version lagged the slot grid behind every small facing change, and 36 clips changed.
One regression had a traced mechanism.
On the caracole's peel-back, the grid trailed the heading by 6 to 44 degrees, and `cycle_charge`'s troop never re-contacted its target.
Router outcomes shifted on several clips too, but those were per-clip, single-seed outcomes, which the previous section shows can be chance.
The author first proposed an exemption with a pre-existing cause for the caracole row.
Later measurement contradicted that cause, and #1820 was closed as a regression the PR itself had caused.
Each round narrowed the scope to what the issue needed: no lag in contact, then no lag for combat re-faces, then lag only on marches the player ordered.
The merged PR changes 6 clips, its other clips are bit-identical to main, and the issue stays open for the combat cases.

- **Do:** when a fix trips checks on clips outside its target, shrink its scope until those clips are bit-identical to main
  (a deterministic check, unlike comparing outcomes), and leave the rest of the issue open.

- **Don't:** exempt a new defect the change causes, or credit it to a cause the data contradicts.

(`Lacaedemon/sparta` PR #1814 and #1820, 2026-10-12.)
