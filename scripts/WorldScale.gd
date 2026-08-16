class_name WorldScale
## World scale: sim/world units per metre. The single source of truth.
## A leaf script with zero preloads, so ANY script -- including Unit.gd,
## which cannot preload Battle.gd (the documented Unit<->Battle preload
## cycle) -- can preload it without creating a cycle. Deliberately NOT an
## autoload: autoload members are not constant expressions, and this value
## exists precisely so `const` initializers elsewhere can fold
## `<metres> * WorldScaleRef.WU_PER_M` at parse time.

const WU_PER_M := 20.0
const M_PER_WU := 1.0 / WU_PER_M


## Convert an authored metric length to world units, for the cases a `const`
## initializer can't cover: a per-TYPE value read from a data table, converted once
## when that type is built (LoadoutRegistry's interned Weapon instances). Same
## multiplication a const initializer folds, just at type-construction time rather
## than parse time -- so it belongs here, in the boundary file whose whole point is
## the scale, rather than as a stray conversion in the type's own script.
##
## NOT for runtime state: sim geometry stays world units end to end, and a conversion
## in a per-tick path is the hot-loop cost docs/units-convention.md exists to prevent.
static func m_to_wu(metres: float) -> float:
	return metres * WU_PER_M
