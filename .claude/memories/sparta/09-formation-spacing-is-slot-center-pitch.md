## Formation spacing identity: slot-center pitch in metres, one axis, type presets

Spacing is **slot-center pitch** (the interval includes the man or horse),
not empty edge-to-edge air.
Asclepiodotus Tactics 4 measures right-shoulder to right-shoulder.
Passability is a **derived** gap: `center_pitch - half_extents`,
using the actual body (man/shield radius for infantry, horse radius for cavalry).
Do not invent a second stored scale for cavalry or for "close vs regular."

Infantry vs cavalry are **different presets on that same axis**,
not different metrics.
The authored floor is **Tight** (synaspismos):
0.45 m isotropic on foot,
cavalry 1.0 m files (one horse-width, derived side gap ~0, knee-to-knee)
and 3.0 m ranks
(Aelian: horse length ~3x shoulder width;
Asclepiodotus 7.4: Greeks doubled the rider interval
so an 8-deep x 16-front block still looked square --
cavalry depth does not add othismos, and stacked horses panic).

`FORMATION_TIGHT` is that floor (`spacing_scale` 1.0).
Keep Tight's combat/collision fork
(separation, missile, charge absorption, brace, containment).
`FORMATION_NORMAL` is pyknosis at 2x (~0.9 m on foot, 2 x 6 m on horse) --
the default fighting order.
`FORMATION_LOOSE` is true open order at 4x (~1.8 m on foot, 4 x 12 m on horse) --
marching and file-relief density, not pyknosis.
Do not collapse the enums,
and do not gate file-corridor relief on `is_tight_formation()` --
Shield Wall / Testudo are tighter than Tight.
Gate the corridor on `file_clearance_wu() > 0`.
Tight stays packed; Normal and Loose may widen.

Square and schiltron stay on the Tight floor
(synaspismos packing, isotropic at file pitch).
Shield Wall / Testudo squeeze below that floor (0.75x / 0.6x);
do not silently make them looser than Tight.

The sim body is still a **circle** (`MARK_RADIUS` / `CAV_MARK_RADIUS`),
so rank clearance currently subtracts the same radius as file.
A horse AABB (length half-extent)
would bring default cavalry rank clearance near zero;
that is measurement fidelity on the same identity, not a new scale.

Regiment-level relief pass-through (`_separation_exempt`) is **not** file-gap opening.
Tight files stay packed;
only an already-open derived gap may widen a lane.
Blocked relief through a locked interval is intended.

Player-facing labels are metres via `DistanceLegend.interval_label_text`
(centimetre precision -- `label_text` would print 0.45 as "0 m").
Anisotropic units read "1 x 3 m" (file then rank, ASCII x).
Square/schiltron captions are isotropic at file pitch
so they match the square grid, which omits rank.
