class_name SoldierFlightWay
extends RefCounted
## The way a routed man chooses for himself when he looks round (SoldierFlightStep): from the
## foes he perceives and the refuge he knows (SoldierFlight.refuge_direction). It never comes
## to nothing: a panicking man does not stand still in front of the enemy where his refuge's
## pull and the enemy's push happen to balance. With the enemy between him and his refuge he
## runs away from them and round them, on the side he chose when he last looked round.


## His own direction, which never stalls. With the foes he perceives between him and his refuge
## (the refuge within a quarter-turn of the `threat`), he runs round them on one side: toward his
## refuge's side of them (where fewer foes stand), else the side `grown` rock does not shut, else
## his own side of his unit's centre; and away from them as strongly as he feels them (the
## threat's weight, up to 1), so a man who barely sees them at the edge of his sight runs along
## them rather than turning back out of sight, where his refuge would turn him in again.
## Otherwise his refuge's pull (rout_refuge_weight) and the threat's push add, both pointing
## away from the foes.
static func choose(unit: Unit, i: int, threat: Vector2,
		grown: Array[Rect2] = []) -> Vector2:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var refuge: Vector2 = SoldierFlight.refuge_direction(unit, pos)
	if threat.length_squared() <= 0.000001:
		return refuge
	var away: Vector2 = -threat.normalized()
	if refuge.dot(away) >= 0.0:
		return (refuge * unit.rout_refuge_weight - threat).normalized()
	var side: Vector2 = refuge - away * refuge.dot(away)
	if side.length_squared() <= 0.000001:
		var across: Vector2 = away.orthogonal()
		side = across if (pos - unit.position).dot(across) >= 0.0 else -across
	side = side.normalized()
	var stride: float = unit.soldier_reach()
	if PathField.inside_any_rect(pos + side * stride, grown) \
			and not PathField.inside_any_rect(pos - side * stride, grown):
		side = -side
	return (side + away * minf(1.0, threat.length())).normalized()
