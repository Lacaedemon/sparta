class_name SoldierLookRound
extends RefCounted
## A routed man looking round (SoldierFlightStep, once a reaction time): he chooses his way from
## what he perceives (SoldierFlightWay.choose). With a foe within his reach and no way open he is
## cornered, and turns to that foe to fight (SoldierCornered). Rock alone never corners him: he
## sees it, and runs the open way nearest the one he wants, so he backs out of a dead end and
## goes round a hill or a wall rather than into it.

## The turns off his wanted way he tries, nearest first, in radians.
const TURNS: Array[float] = [PI / 4.0, PI / 2.0, 3.0 * PI / 4.0, PI]


## Man `i` of `unit` looks round on `frame`; `grown` is the impassable ground grown by a body
## radius. Writes his chosen way to Unit._sim_flight_dir (ZERO: he stands and fights).
static func look(unit: Unit, i: int, frame: int, grown: Array[Rect2]) -> void:
	var seen: Dictionary = SoldierFlight.perceived(unit, i, frame)
	var own: Vector2 = SoldierFlightWay.choose(unit, i, seen["threat"], grown)
	var foe: Unit = seen["nearest_unit"]
	if foe != null and SoldierCornered.is_cornered(unit, i, own, seen, grown):
		var to_foe: Vector2 = foe._sim_soldier_pos[seen["nearest_index"]] - unit._sim_soldier_pos[i]
		if to_foe.length_squared() > 0.0:
			unit._sim_soldier_facing[i] = to_foe.normalized()
		own = Vector2.ZERO
	else:
		own = way_round_rock(unit, i, own, grown)
	unit._sim_flight_dir[i] = own


## `own` when no rock lies along it as far as man `i` can see (Unit.sight_range); else the way
## nearest it that is clear that far, turning first to his own side of his unit's centre; else,
## with rock every way, the way along which the rock lies farthest off.
static func way_round_rock(unit: Unit, i: int, own: Vector2, grown: Array[Rect2]) -> Vector2:
	if grown.is_empty() or own == Vector2.ZERO:
		return own
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var sight: float = unit.sight_range if unit.sight_range > 0.0 else Unit.DEFAULT_SIGHT_SCALE
	var best: Vector2 = own
	var best_clear: float = _clear(pos, own, sight, grown)
	if best_clear >= 1.0:
		return own
	var side: float = 1.0 if (pos - unit.position).cross(own) >= 0.0 else -1.0
	for turn in TURNS:
		for s in [side, -side]:
			var way: Vector2 = own.rotated(turn * float(s))
			var clear: float = _clear(pos, way, sight, grown)
			if clear >= 1.0:
				return way
			if clear > best_clear:
				best_clear = clear
				best = way
	return best


## How far along `way` from `pos`, as a fraction of `sight`, the first grown rock lies (1: none).
static func _clear(pos: Vector2, way: Vector2, sight: float, grown: Array[Rect2]) -> float:
	var t: float = 1.0
	for g in grown:
		t = minf(t, PathField.segment_rect_entry(pos, pos + way * sight, g))
	return t
