## Formation spacing identity: slot-center pitch in metres, one axis, type presets

Spacing is **slot-center pitch** (the interval includes the man or horse),
not empty edge-to-edge air.
Asclepiodotus Tactics 4 measures right-shoulder to right-shoulder.
Passability is a **derived** gap: `center_pitch - half_extents`,
using the actual body (man/shield radius for infantry, horse radius for cavalry).
Do not invent a second stored scale for cavalry or for "close vs regular."

Infantry vs cavalry are **different presets on that same axis**,
not different metrics.
Foot default is isotropic synaspismos (0.45 m files and ranks).
Cavalry spawn anisotropic: 1.0 m files
(one horse-width, derived side gap ~0, knee-to-knee)
and 3.0 m ranks
(Aelian: horse length ~3x shoulder width;
Asclepiodotus 7.4: Greeks doubled the rider interval
so an 8-deep x 16-front block still looked square --
cavalry depth does not add othismos, and stacked horses panic).

`FORMATION_NORMAL` and `FORMATION_TIGHT` share the 0.45 m infantry floor
(`spacing_scale` 1.0).
They **do** fork combat (separation, missile, charge absorption, brace, containment).
Do not collapse the enums,
and do not gate file-corridor relief on `is_tight_formation()` --
Shield Wall / Testudo are tighter than both.
Gate the corridor on `file_clearance_wu() > 0`.

`FORMATION_LOOSE` is pyknosis (~0.9 m on foot),
not true open order (~1.8-2 m).
A cavalry-only option set
(a dedicated open-order pitch for turning/weapon-use,
separate from doubling the infantry scale)
is a larger change: until it lands,
Loose still multiplies both cavalry axes by 2.

The sim body is still a **circle** (`MARK_RADIUS` / `CAV_MARK_RADIUS`),
so rank clearance currently subtracts the same radius as file.
A horse AABB (length half-extent)
would bring default cavalry rank clearance near zero;
that is measurement fidelity on the same identity, not a new scale.

Regiment-level relief pass-through (`_separation_exempt`) is **not** file-gap opening.
Close-order files stay packed;
only an already-open derived gap may widen a lane.
Blocked relief through a locked interval is intended.

Player-facing labels are metres via `DistanceLegend.interval_label_text`
(centimetre precision -- `label_text` would print 0.45 as "0 m").
Anisotropic units read "1 x 3 m" (file then rank, ASCII x).
