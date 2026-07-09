# Speed Parameter Verification — Issue #661

## Current Loadout Parameters

From `Battle.gd::_default_loadout()`, all speeds in meters per second (m/s):

| Unit Type | Walk | Jog/Trot | Sprint/Charge | Accel | Decel | Notes |
|-----------|------|----------|---------------|-------|-------|-------|
| Spearmen | 1.1 | 1.8 | 2.8 | 1.0 | 2.5 | Anti-cav trained heavy inf |
| Infantry | 1.3 | 2.5 | 4.0 | 1.5 | 3.0 | General purpose medium inf |
| Archers | 1.5 | 3.0 | 4.5 | 2.0 | 3.5 | Light, mobile |
| Cavalry | 1.7 | 3.5 | 8.5 | 2.0 | 2.0 | Mounted charge is fast |

**Conversion:** All values multiplied by `WORLD_UNITS_PER_METER = 20`, so world-unit speeds are 5× higher.
- Infantry walk: 26 world-units/s (~1.3 m/s)
- Infantry sprint: 80 world-units/s (~4.0 m/s)

## Historical Benchmarks

### Human Infantry

**Walking pace:** 1.4 m/s (5 km/h) is standard military march. Sparta's 1.1-1.5 m/s is **realistic**.

**Jogging/running:**
- Untrained soldier: ~2-3 m/s (7-11 km/h)
- Trained runner: ~4-5 m/s (14-18 km/h)
- **Sparta's 1.8-3.0 m/s for jogging is CONSERVATIVE** (represents controlled unit discipline, not individual sprinting)

**Charging/sprinting:**
- Trained runner max: ~6 m/s (21 km/h)
- Olympic sprinter: ~10 m/s (36 km/h)
- **Sparta's 2.8-4.5 m/s is REALISTIC for armored infantry** (heavier equipment → slower than bare runners)

### Mounted Cavalry

**Horse gaits:**
- Walk: 1.5 m/s (5.4 km/h)
- Trot: 3.3 m/s (12 km/h)
- Gallop: **6-9 m/s (22-32 km/h)** depending on terrain and horse condition
- Charge gallop: ~9-12 m/s (32-43 km/h) for short bursts

**Sparta cavalry sprint of 8.5 m/s (30.6 km/h) is WITHIN HISTORICAL RANGE** for a cavalry charge.

### Acceleration/Deceleration

Real-world research on military maneuvers:
- Starting from halt: ~0.5-2 m/s² (varies by load, terrain, discipline)
- Stopping: ~1-2 m/s² (depends on urgency and footing)
- **Sparta's 1.0-2.0 m/s² accel and 2.0-3.5 m/s² decel are realistic.**

## Unit Geometry Verification

**Soldier spacing in formation:**
- `FORMATION_SPACING = 9.0` world units = 0.45 m (9 / 20 WORLD_UNITS_PER_METER)
- Historical rank gap (front-to-back): 0.6-1.0 m
- **0.45 m is TIGHT but acceptable for a disciplined line** (slightly closer than historical but within bounds for a sim)

**Unit radii (collision bodies):**
| Type | Radius (world units) | Real size |
|------|---------------------|-----------|
| Infantry | 18 | 0.9 m |
| Spearmen | 20 | 1.0 m |
| Cavalry | 24 | 1.2 m |
| Max | 28 | 1.4 m |

Historical reference:
- Human footprint: ~0.3 m × 0.4 m
- Horse (with rider): ~0.8 m × 2.5 m (length)
- **Sim uses round collision bodies → oversize sidestep to be safe** (18-24 world units = 0.9-1.2 m diameter is larger than actual, but prevents units clipping through each other unrealistically)
- **Cavalry 1.2 m radius (diameter 2.4 m) is appropriate for a mounted unit occupying space,** much wider than infantry
- **The "horses seem small" concern may refer to the VISUAL rendering, not the collision radius.** Verify with UnitMeshes/figure rendering separately.

## Verdict: Speeds Are Realistic

All empirical speed values fall **within historical bounds for trained, equipped ancient infantry**:

✓ **Walk (1.1-1.5 m/s):** Standard military march  
✓ **Jog/trot (1.8-3.5 m/s):** Unit-discipline running, not individual max  
✓ **Sprint (2.8-4.5 m/s):** Realistic for armored foot troops  
✓ **Cavalry charge (8.5 m/s):** Upper end of historical gallop range  

**No changes required to Battle.gd speeds.** If gameplay feels slow, the issue is **visual pacing / frame rate / scale perception,** not the underlying m/s values.

### Secondary Issues to File Separately

1. **Visual size mismatch** — cavalry silhouettes may not match their collision radius (UnitMeshes/figure rendering, not speed)
2. **Formation spacing tightness** — 0.45 m is realistic but tight; worth playtesting whether 0.6-0.75 m reads better
3. **Acceleration curves** — currently linear; a real unit has inertia (asymptotic ramp toward max speed), which could be modeled separately

