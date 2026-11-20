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
	var quarry: int = _quarry_uid(unit)
	var any: bool = _any_routed(unit)
	if quarry < 0 and not any and unit._sim_chase_dir.is_empty():
		return false
	if not unit._sim_chase_dir.is_empty() and unit._sim_chase_dir.size() != n:
		unit._sim_chase_dir.resize(n)
	var frame: int = Engine.get_physics_frames()
	var period: int = unit.rout_reaction_ticks()
	var riding: bool = false
	for i in range(n):
		if (SoldierFlight.tick + i) % period == 0:
			var way: Vector2 = Vector2.ZERO
			if quarry >= 0 or any:
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


## Whether most of `unit`'s first `n` men stand off their own places, each judged on his own:
## farther from his slot than the out-of-good-order distance (Unit.standoff_off_slot_pitches file
## pitches). Then the ranks are where the men are not, and the unit forms up where they stand.
static func scattered(unit: Unit, n: int) -> bool:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var near: float = unit.standoff_off_slot_pitches * unit.file_pitch_wu()
	var m: int = mini(n, slots.size())
	var off: int = 0
	for i in range(m):
		if unit._sim_soldier_pos[i].distance_squared_to(slots[i]) > near * near:
			off += 1
	return 2 * off > m


## The way rider `i` rides: at the nearest running man he sees (ManPerception's routed-only
## look), when `any` or when that man is of the unit his order attacks (uid `quarry`); ZERO when
## he sees none, or the nearest runner he sees is of another unit.
static func _look(unit: Unit, i: int, frame: int, quarry: int, any: bool) -> Vector2:
	var seen: Dictionary = SoldierFlight.perceived(unit, i, frame, true)
	var foe: Unit = seen["nearest_unit"]
	if foe == null or not (any or foe.uid == quarry):
		return Vector2.ZERO
	return (foe._sim_soldier_pos[seen["nearest_index"]] - unit._sim_soldier_pos[i]).normalized()


## The uid of the unit `unit`'s order attacks (Order.Type.ATTACK), or -1: read off the order, not
## off the target the unit has taken up, which contact can change.
static func _quarry_uid(unit: Unit) -> int:
	var o: Order = unit.current_order
	return o.target_uid if o != null and o.type == Order.Type.ATTACK else -1


## Whether `unit` rides down any routed man its riders see: a standing order to pursue, or the
## ON_SIGHT variant off HOLD.
static func _any_routed(unit: Unit) -> bool:
	return unit.order_mode == Unit.ORDER_CHASE or unit.order_mode == Unit.ORDER_SWEEP_ROUTERS \
			or (unit.horse_pursuit == Mode.ON_SIGHT and unit.order_mode != Unit.ORDER_HOLD)
