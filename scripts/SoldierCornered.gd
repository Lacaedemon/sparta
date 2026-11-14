class_name SoldierCornered
extends RefCounted
## A routed man with no way to run turns and fights. He is cornered when the way he wants to
## run, and the ways to either side of it, are each shut within his weapon's reach: by
## impassable ground, or by an enemy body, with a foe in reach. He then stands, faces the foe nearest
## him and strikes with the men beside him at his unit's cadence (fight), and runs again once he
## looks round and finds a way open (SoldierLookRound).

## Half the width of a direction's sector, in radians: ahead, left and right each cover a
## quarter-turn, so the three cover everything but the way he came.
const SECTOR_HALF_ANGLE: float = PI / 4.0
## How far a body may step past its read spread in a tick; a solver margin, tuned in wu.
const SPREAD_PAD: float = 10.0

static var _spread_frame: int = -1
static var _spreads: Dictionary = {}   # foe unit -> [body count, spread] for _spread_frame


## Whether man `i` of `unit`, who wants to run along `own`, is cornered: ahead, left and right of
## `own` are each shut within his reach (Unit.soldier_reach) by `grown` (impassable rects grown by
## a body radius) or by a body of an enemy unit, and a foe stands within his reach. `seen` is what
## he perceives (SoldierFlight.perceived); with no foe in reach he is not, however rock shuts him.
static func is_cornered(unit: Unit, i: int, own: Vector2, seen: Dictionary,
		grown: Array[Rect2]) -> bool:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var reach: float = unit.soldier_reach()
	var dirs: Array[Vector2] = [own, own.orthogonal(), -own.orthogonal()]
	var shut: Array[bool] = [false, false, false]
	for k in range(3):
		shut[k] = PathField.inside_any_rect(pos + dirs[k] * reach, grown)
	if seen["nearest_unit"] == null or float(seen["nearest_distance"]) > reach:
		return false
	var cos_half: float = cos(SECTOR_HALF_ANGLE)
	for foe in foes_near(unit, pos, reach):
		for p in foe._sim_soldier_pos:
			var to: Vector2 = p - pos
			var d: float = to.length()
			if d > reach or d <= 0.0:
				continue
			for k in range(3):
				if to.dot(dirs[k]) >= cos_half * d:
					shut[k] = true
	return shut[0] and shut[1] and shut[2]


## Enemy units of `unit` with a body that could lie within `reach` of `pos`: alive, with bodies,
## and their position no farther than `reach` plus their farthest body from it (_spread, read
## once a frame per unit and body count, padded by SPREAD_PAD for the bodies that step after).
static func foes_near(unit: Unit, pos: Vector2, reach: float) -> Array[Unit]:
	var out: Array[Unit] = []
	if not unit.is_inside_tree():
		return out
	for group in ["units", "routers"]:
		for o in unit.get_tree().get_nodes_in_group(group):
			var foe: Unit = o as Unit
			if foe == null or foe.team == unit.team or foe.state == Unit.State.DEAD \
					or foe._sim_soldier_pos.is_empty():
				continue
			var bound: float = reach + _spread(foe)
			if foe.position.distance_squared_to(pos) <= bound * bound:
				out.append(foe)
	return out


## How far a body of `foe` stands from its position, read once a frame and body count and padded
## by SPREAD_PAD.
static func _spread(foe: Unit) -> float:
	var frame: int = Engine.get_physics_frames()
	if frame != _spread_frame:
		_spread_frame = frame
		_spreads.clear()
	var count: int = foe._sim_soldier_pos.size()
	var known: Variant = _spreads.get(foe)
	if known != null and int(known[0]) == count:
		return float(known[1])
	var far_sq: float = 0.0
	for p in foe._sim_soldier_pos:
		far_sq = maxf(far_sq, foe.position.distance_squared_to(p))
	var spread: float = sqrt(far_sq) + SPREAD_PAD
	_spreads[foe] = [count, spread]
	return spread


## The cornered men of a routed `unit` (those whose chosen direction is ZERO) strike the foes
## within their reach, as a fighting rank does (SoldierMelee.resolve_men). Returns whether any
## man stood to fight, so the caller arms the next blow's cooldown.
static func fight(unit: Unit) -> bool:
	var men := PackedInt32Array()
	for i in range(mini(unit._sim_flight_dir.size(), unit._sim_soldier_pos.size())):
		if unit._sim_flight_dir[i] == Vector2.ZERO:
			men.push_back(i)
	if men.is_empty():
		return false
	var defenders: Array[Unit] = []
	for i in men:
		for foe in foes_near(unit, unit._sim_soldier_pos[i], unit.soldier_reach()):
			if not defenders.has(foe):
				defenders.append(foe)
	SoldierMelee.resolve_men(unit, men, defenders)
	return true
