class_name SoldierTakeUp
extends RefCounted
## When a horse unit's riders take up a chase (SoldierPursuitStep): when one of them has a routed
## man within his reach, while the unit is under an order to move or fight.


## `unit`'s first `n` riders take up the chase when one of them has a routed man within his reach:
## each looks round for the nearest routed man he sees.
static func take_up(unit: Unit, n: int) -> void:
	if not unit.is_cavalry or not unit._sim_chase_dir.is_empty() \
			or (unit.state != Unit.State.MOVING and unit.state != Unit.State.FIGHTING):
		return
	var reach: float = unit.soldier_reach()
	for foe in SoldierCornered.foes_near(unit, unit.position,
			reach + SoldierCornered._spread(unit)):
		if foe.state == Unit.State.ROUTING and _any_within(unit, n, foe, reach):
			unit._sim_chase_dir.resize(n)
			for i in range(n):
				unit._sim_chase_dir[i] = SoldierPursuitStep.look(unit, i,
						Engine.get_physics_frames())
			return


## Whether a man of `foe` stands within `reach` of one of `unit`'s first `n` men.
static func _any_within(unit: Unit, n: int, foe: Unit, reach: float) -> bool:
	for i in range(mini(n, unit._sim_soldier_pos.size())):
		for q in foe._sim_soldier_pos:
			if q.distance_squared_to(unit._sim_soldier_pos[i]) <= reach * reach:
				return true
	return false
