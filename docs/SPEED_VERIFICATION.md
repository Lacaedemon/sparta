# Speed Parameter Verification — Issue #661

## Current Loadout Parameters

From `Battle.gd::_default_loadout()`, all speeds in meters per second (m/s)
(verified line-by-line against the dict literals in the source, which is the
single source of truth — this table is not hand-maintained separately):

| Unit Type | Walk | Jog/Trot | Sprint/Charge | Accel | Decel | Notes |
|-----------|------|----------|---------------|-------|-------|-------|
| Spearmen | 1.1 | 1.8 | 2.8 | 1.0 | 2.5 | Anti-cav trained heavy inf |
| Infantry | 1.3 | 2.5 | 4.0 | 1.5 | 3.0 | General purpose medium inf |
| Archers | 1.5 | 3.0 | 4.5 | 2.0 | 3.5 | Light, mobile |
| Cavalry | 1.7 | 3.5 | 8.5 | 2.0 | 2.0 | Mounted charge |

**Conversion:** every `*_mps`/`*_mps2` value is multiplied by
`WORLD_UNITS_PER_METER = 20.0` and `SPEED_SCALE = 1.0` (`Battle.gd`), so
world-unit speeds are exactly 20× the m/s figures above and `SPEED_SCALE`
does not currently rescale anything (it's a global multiplier hook, left at
its identity value). Infantry walk: 26 world-units/s (1.3 m/s); infantry
sprint: 80 world-units/s (4.0 m/s).

## Historical Benchmarks (cited)

### Human infantry — walking and running

- **Military march pace.** Roman legionaries' "military pace" (recruit
  standard) covered 20 Roman miles in 5 summer hours under a ~20.5 kg pack —
  about 5.9 km/h (1.6 m/s); the veteran "full pace" was faster still. In
  practice, a marching column sustained roughly 4–5 km/h (1.1–1.4 m/s) for
  hours, with short bursts to 6–7 km/h. Source:
  [Loaded march — Wikipedia](https://en.wikipedia.org/wiki/Loaded_march);
  [Banda Arc Geophysics, "Marching Roman Legionaries"](https://www.bandaarcgeophysics.co.uk/arch/Roman_legionary_marchingV2.html).
  **Sparta's walk speeds (1.1–1.7 m/s) sit inside this historical band.**

- **Jogging / running, modern reference points.** A trained soldier's sprint
  standard (unarmored short bursts) is commonly benchmarked at 100 m in 12 s
  (≈8.3 m/s) or 60 m in 8 s (≈7.5 m/s); an untrained adult sustains a jog around
  8–10 km/h (2.2–2.8 m/s) and can sprint 12–16 km/h (3.3–4.4 m/s) briefly.
  Source: [Spotter Up, "The Soldier's Ideal Speed"](https://spotterup.com/the-soldiers-ideal-speed/);
  [Marathon Handbook, "Average Human Sprint Speed"](https://marathonhandbook.com/average-human-sprint-speed/).
  **Sparta's jog (1.8–3.5 m/s) and sprint (2.8–4.5 m/s) are both well below an
  individual soldier's true sprint capability** (7.5–8.3 m/s). That gap is
  defensible — these values represent a whole *formation* holding a line
  while moving, not one runner's max effort — but it means the earlier draft
  of this document overstated the case by calling sprint "realistic for
  armored foot troops" outright. It is realistic **as a formation-cohesion
  speed**, not as an individual's top speed; the two are different
  quantities and shouldn't be compared as if interchangeable.

### Mounted cavalry

- **Horse gaits.** Averages: walk ≈7 km/h (1.9 m/s), trot ≈13 km/h (3.6 m/s,
  wide range), canter 16–27 km/h (4.4–7.5 m/s), gallop **40–48 km/h
  (11.1–13.3 m/s)**, with short sprints by racing/quarter horses reaching
  65–88 km/h (18–24.5 m/s). Source:
  [Horse gait — Wikipedia](https://en.wikipedia.org/wiki/Horse_gait).
  **Correction to the original draft:** Sparta's cavalry "sprint" of 8.5 m/s
  (30.6 km/h) is **not** "the upper end of the historical gallop range" — a
  true gallop averages 40–48 km/h, nearly 1.5× faster. 8.5 m/s instead falls
  **between the canter and gallop ranges** (faster than a 16–27 km/h canter,
  well short of a 40–48 km/h gallop) — closer to a fast canter than to any
  gait actually called a gallop. Whether that's the right in-game value is a
  gameplay-balance question (a full 40+ km/h charge might be unplayable at
  this map/camera scale) rather than a factual one — but the earlier
  "verdict" claim was wrong and is corrected here.

### Acceleration/deceleration

No single authoritative source gives m/s² figures for a formed unit
(individual short-sprint studies measure 0-to-top-speed time, not a
disciplined line's collective accel/decel, and the two aren't equivalent).
Sparta's 1.0–2.0 m/s² accel / 2.0–3.5 m/s² decel are a plausible order of
magnitude for a walking-to-jogging transition, but this document does not
have a citation backing the specific figures the way the walk/gallop numbers
above do — flagged as an open question rather than asserted as verified.

## Unit Geometry Verification

**Soldier spacing in formation:**
- `FORMATION_SPACING = 9.0` world units = 0.45 m (`scripts/Unit.gd`).
- The Hellenistic phalanx had **three** density tiers, not two, and it's easy
  to conflate the middle one with the tightest: **open order** (~1.8–2 m/man),
  **close order** / *pyknosis* (~0.9–1 m/man — this is Polybius's "3 feet"
  figure for the phalanx in battle order), and **synaspismos** ("locked
  shields", ~0.45 m/man), explicitly the *tightest* of the three, used only
  under exceptional pressure (a frontal cavalry charge or heavy missile fire).
  Source: [Phalanx — Wikipedia](https://en.wikipedia.org/wiki/Phalanx);
  [Fordham Ancient History Sourcebook, Polybius on the legion vs. the
  phalanx](https://sourcebooks.fordham.edu/ancient/polybius-maniple.asp)
  (the Polybius translation there describes the 3-foot close-order figure but
  does not itself use the word "synaspismos"). Roman legionary spacing needed
  to be looser than even close order (~6 feet / ~1.8 m) to leave
  sword-and-shield room.
  **Correction to a previous draft of this document:** 0.45 m is not "about
  half the tightest historically attested spacing" — that comparison
  mislabeled the 0.9 m *close-order* (pyknosis) figure as synaspismos.
  Synaspismos, the tier that is actually tightest, is 0.45 m/man — Sparta's
  `FORMATION_SPACING` **matches** it. The real, smaller discrepancy is that
  Sparta uses this exceptional, high-pressure spacing as the unit's *only*
  formation density, where history treats it as a rare, temporary stance
  rather than the standing default — worth noting, but a materially different
  (and much smaller) claim than "half the historical minimum."

**Unit radii (collision bodies):**

| Type | Radius (world units) | Real size |
|------|---------------------|-----------|
| Infantry | 18 | 0.9 m |
| Spearmen | 20 | 1.0 m |
| Cavalry | 24 | 1.2 m |
| Max | 28 | 1.4 m |

A human footprint is roughly 0.3 m × 0.4 m and a horse-with-rider occupies
roughly 0.8 m × 2.5 m (length); round collision bodies necessarily oversize a
human silhouette to avoid unrealistic clipping, and 0.9–1.2 m diameter is a
reasonable compromise for that purpose. The cavalry radius (1.2 m) being
wider than infantry (0.9 m) correctly represents a mounted unit's greater
footprint. **The "horses seem small" concern in #661 is a rendering/visual-art
question (silhouette scale in `UnitMeshes`), not a collision-geometry one** —
this document only verifies the physics radii, which are internally
consistent; the visual mismatch needs a separate look at the sprite/mesh
assets themselves.

## Verdict

Most of Sparta's movement parameters check out against cited historical and
physiological benchmarks — walking pace matches military march rates, and
unit jog/sprint speeds are a defensible (if conservative) proxy for a
formation's cohesion-limited pace rather than an individual's sprint. One
of the two spacing/speed concerns raised in the issue turns out to already
match the tightest historical tier once the terminology is applied
correctly; the other is a real, citable discrepancy:

1. **Formation spacing (0.45 m) actually matches synaspismos, the
   *tightest* attested Hellenistic-phalanx tier** — not "about half the
   tightest historically attested spacing" as an earlier draft of this
   document claimed (that draft mislabeled the looser 0.9 m *close-order*
   figure as synaspismos). The real, smaller discrepancy: Sparta applies
   this exceptional emergency stance as the unit's only/default density,
   where history used it briefly under extreme pressure rather than as a
   standing formation.
2. **Cavalry charge speed (8.5 m/s / 30.6 km/h) sits between a canter and a
   true gallop** — faster than the 16–27 km/h canter range, well short of
   the 40–48 km/h gallop range. The earlier draft of this document asserted
   it was "the upper end of the gallop range"; corrected here.

Neither is fixed in this PR: changing either value is a gameplay-balance
change (formation width/spacing math, unit collision spacing, and relative
unit speeds all ripple from these constants) that needs its own playtesting
pass, not a drive-by edit alongside a verification writeup. See the tracked
follow-up issues below. The third original concern — cavalry visual size —
is a rendering question this document's physics-radius check can't settle
either way; also tracked separately.

### Follow-up issues filed from this verification

- [#719](https://github.com/Lacaedemon/sparta/issues/719) — Sparta's
  default formation spacing matches the exceptional synaspismos tier
  rather than the standing close-order tier — consider whether the
  *default* density should loosen toward close order (~0.9 m/man), with
  synaspismos-tight spacing reserved for a specific defensive stance.
- [#720](https://github.com/Lacaedemon/sparta/issues/720) — cavalry charge
  speed sits between a canter and a true gallop — reconsider `sprint_mps`
  for cavalry (or document why the slower value is intentional for
  playability at this scale).
- [#721](https://github.com/Lacaedemon/sparta/issues/721) — cavalry
  visual/silhouette size vs. collision radius (rendering, not physics) —
  separate from anything this document verifies.
