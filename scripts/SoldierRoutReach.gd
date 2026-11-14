class_name SoldierRoutReach
extends RefCounted
## Which of a fighting unit's men strike a routed one. A routed unit is no formation: its men run
## each on his own and may pass any side of the block fighting them, down its flank or along its
## rear, where the block's engaged front (Unit.engaged_soldier_indices) cannot reach. So every man
## of the block with a runner within his own reach strikes him, as he would any foe in reach,
## wherever he stands in the block (UnitCombat.strike).


## The body indices of `attacker`'s men with a body of `router` within their reach
## (Unit.soldier_reach), in ascending order.
static func men_in_reach(attacker: Unit, router: Unit) -> PackedInt32Array:
	var out := PackedInt32Array()
	var reach_sq: float = attacker.soldier_reach() * attacker.soldier_reach()
	for i in range(attacker._sim_soldier_pos.size()):
		var pos: Vector2 = attacker._sim_soldier_pos[i]
		for p in router._sim_soldier_pos:
			if pos.distance_squared_to(p) <= reach_sq:
				out.push_back(i)
				break
	return out
