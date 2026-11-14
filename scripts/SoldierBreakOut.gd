class_name SoldierBreakOut
extends RefCounted
## What a routed man cornered by enemy bodies (SoldierCornered) does, a named variant
## (Unit.cornered). No source consulted (Xenophon, Polybius, Arrian) says whether a horseman caught
## inside enemy ranks cuts his way through or stands, so both are the sim's inference. STAND, the
## default: he stands where he is, faces the foe nearest him and strikes at whoever is in his reach
## until a way opens. CUT: he forces his way out where the foes round him stand thinnest, the
## opening nearest the way he wants to run, and strikes only the foe in his way.

enum Mode { CUT, STAND }

## How many ways round him a cornered man weighs, evenly spaced.
const WAYS: int = 16


## The way man `i` of `unit` forces out, from the foes he sees within twice his reach: of WAYS
## directions round him, the one with the fewest foe bodies in its sector (a half-width of half a
## way apart either side), and among those the nearest to `own`, the way he wants to run. A way
## shut within his reach by `grown` (impassable rects grown by a body radius) counts as no way at
## all, as rock shuts a way for SoldierCornered.
static func way_out(unit: Unit, i: int, own: Vector2, grown: Array[Rect2]) -> Vector2:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var look: float = 2.0 * unit.soldier_reach()
	var cos_half: float = cos(PI / float(WAYS))
	var counts := PackedInt32Array()
	counts.resize(WAYS)
	for k in range(WAYS):
		if PathField.inside_any_rect(pos + Vector2.RIGHT.rotated(TAU * k / WAYS) * unit.soldier_reach(),
				grown):
			counts[k] = 1 << 30   # rock: no way through
	for foe in SoldierCornered.foes_near(unit, pos, look):
		for p in foe._sim_soldier_pos:
			var to: Vector2 = p - pos
			var d: float = to.length()
			if d > look or d <= 0.0:
				continue
			for k in range(WAYS):
				if to.dot(Vector2.RIGHT.rotated(TAU * k / WAYS)) >= cos_half * d:
					counts[k] += 1
	var best: int = 0
	for k in range(1, WAYS):
		var better: bool = counts[k] < counts[best] or (counts[k] == counts[best] \
				and Vector2.RIGHT.rotated(TAU * k / WAYS).dot(own) \
				> Vector2.RIGHT.rotated(TAU * best / WAYS).dot(own))
		if better:
			best = k
	return Vector2.RIGHT.rotated(TAU * best / WAYS)


## Whether man `i` of `unit`, running along `way` (ZERO: standing), has a foe to strike: within
## his reach, and, while he forces his way out, in his way (within SoldierCornered's sector of it).
static func has_foe_to_strike(unit: Unit, i: int, way: Vector2) -> bool:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var reach: float = unit.soldier_reach()
	var cos_half: float = cos(SoldierCornered.SECTOR_HALF_ANGLE)
	for foe in SoldierCornered.foes_near(unit, pos, reach):
		for p in foe._sim_soldier_pos:
			var to: Vector2 = p - pos
			var d: float = to.length()
			if d <= reach and d > 0.0 and (way == Vector2.ZERO or to.dot(way) >= cos_half * d):
				return true
	return false


## The routed men of `unit` who stand cornered (their chosen way ZERO) strike the foes within their
## reach, and under CUT so does a man running with a foe in his way, as a fighting rank does
## (SoldierMelee.resolve_men). Returns whether any man struck, so the caller arms the next blow's
## cooldown.
static func fight(unit: Unit) -> bool:
	var men := PackedInt32Array()
	var cut: bool = unit.cornered == Mode.CUT
	for i in range(mini(unit._sim_flight_dir.size(), unit._sim_soldier_pos.size())):
		var way: Vector2 = unit._sim_flight_dir[i]
		if way == Vector2.ZERO or (cut and has_foe_to_strike(unit, i, way)):
			men.push_back(i)
	if men.is_empty():
		return false
	var defenders: Array[Unit] = []
	for i in men:
		for foe in SoldierCornered.foes_near(unit, unit._sim_soldier_pos[i], unit.soldier_reach()):
			if not defenders.has(foe):
				defenders.append(foe)
	SoldierMelee.resolve_men(unit, men, defenders)
	return true
