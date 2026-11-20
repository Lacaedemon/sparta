class_name SoldierTakeUp
extends RefCounted
## Which routed men a horse unit's riders ride down (SoldierPursuitStep), and when each looks round
## for one. A rider rides at a routed man only under an order that sends him after the rout: an
## attack on the routed unit (Order.Type.ATTACK on it), or a standing order to pursue (the CHASE or
## SWEEP_ROUTERS stance). On a march elsewhere, holding, or fighting with no such order, he keeps
## to his order. Whether horse rode a broken enemy down unordered the sources reached do not say,
## so it is a named variant (Unit.horse_pursuit, Mode); both readings are the sim's inference.

## ORDERED: the default; a rider pursues only under an order to. ON_SIGHT: any horse unit not on
## HOLD rides down the routed men its riders see.
enum Mode { ORDERED, ON_SIGHT }


## Each of `unit`'s first `n` riders whose look-round falls on this tick (his reaction time,
## Unit.rout_reaction_ticks, on a battle tick of his own) looks for a routed man he may ride at:
## Unit._sim_chase_dir holds his way, ZERO when he sees none. The array is empty while no rider
## rides, and is emptied when the last one stops; returns whether that happened this tick.
static func look_round(unit: Unit, n: int) -> bool:
	if not unit.is_cavalry or unit.state == Unit.State.ROUTING:
		if not unit._sim_chase_dir.is_empty():
			unit._sim_chase_dir = PackedVector2Array()
		return false
	var quarry: Unit = _quarry(unit)
	var any: bool = _any_routed(unit)
	if quarry == null and not any and unit._sim_chase_dir.is_empty():
		return false
	if not unit._sim_chase_dir.is_empty() and unit._sim_chase_dir.size() != n:
		unit._sim_chase_dir.resize(n)
	var frame: int = Engine.get_physics_frames()
	var period: int = unit.rout_reaction_ticks()
	var riding: bool = false
	for i in range(n):
		if (SoldierFlight.tick + i) % period == 0:
			var way: Vector2 = Vector2.ZERO
			if quarry != null or any:
				way = _look(unit, i, frame, quarry, any)
			if way != Vector2.ZERO and unit._sim_chase_dir.is_empty():
				unit._sim_chase_dir.resize(n)
			if not unit._sim_chase_dir.is_empty():
				unit._sim_chase_dir[i] = way
		riding = riding or (not unit._sim_chase_dir.is_empty() \
				and unit._sim_chase_dir[i] != Vector2.ZERO)
	if riding or unit._sim_chase_dir.is_empty():
		return false
	unit._sim_chase_dir = PackedVector2Array()
	return true


## The way rider `i` rides: at the nearest routed man he sees of any routed foe when `any`, else
## of `quarry`; ZERO when he sees none.
static func _look(unit: Unit, i: int, frame: int, quarry: Unit, any: bool) -> Vector2:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	if any:
		var seen: Dictionary = SoldierFlight.perceived(unit, i, frame, true)
		var foe: Unit = seen["nearest_unit"]
		return Vector2.ZERO if foe == null \
				else (foe._sim_soldier_pos[seen["nearest_index"]] - pos).normalized()
	var best: float = unit.sight_range * unit.sight_range
	var way := Vector2.ZERO
	for q in quarry._sim_soldier_pos:
		var d2: float = pos.distance_squared_to(q)
		if d2 <= best and d2 > 0.0 and SoldierFlightStep._sees(unit, i, q, frame):
			best = d2
			way = (q - pos).normalized()
	return way


## The routed unit `unit` is ordered to attack (Order.Type.ATTACK on it), or null.
static func _quarry(unit: Unit) -> Unit:
	var t: Unit = unit.target_enemy
	var o: Order = unit.current_order
	if o == null or o.type != Order.Type.ATTACK or t == null or not is_instance_valid(t) \
			or t.uid != o.target_uid or t.state != Unit.State.ROUTING:
		return null
	return t


## Whether `unit` rides down any routed man its riders see: a standing order to pursue, or the
## ON_SIGHT variant off HOLD.
static func _any_routed(unit: Unit) -> bool:
	return unit.order_mode == Unit.ORDER_CHASE or unit.order_mode == Unit.ORDER_SWEEP_ROUTERS \
			or (unit.horse_pursuit == Mode.ON_SIGHT and unit.order_mode != Unit.ORDER_HOLD)
