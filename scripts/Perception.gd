extends RefCounted
## Fog-of-war perception: which enemy units a team can currently see, and what it
## remembers about the ones it no longer can.
##
## A pure query over unit state.
## It reads positions, teams, sight ranges, and states and writes nothing back into
## any unit. Perception output feeds unit visibility and ghost markers in Battle.
## Fog is render-only and does not affect retreat bounds or simulation state.
## Visibility is a disc per observer.
## A target is seen when its center lies within some friendly observer's sight range.
## Terrain occlusion and screening are not modelled yet.
## A unit's own team always sees it (an army knows where its own regiments stand).


## Whether an observer at `observer_pos` with `sight_range` (world units) perceives a
## target at `target_pos`. Inclusive at the boundary, compared in squared distance so no
## square root runs per observer-target pair.
static func perceives(observer_pos: Vector2, sight_range: float, target_pos: Vector2) -> bool:
	if sight_range <= 0.0:
		return false
	return observer_pos.distance_squared_to(target_pos) <= sight_range * sight_range


## The sight range an observing unit contributes this tick: its own `sight_range`, cut by
## `Unit.SIGHT_ROUTING_PENALTY` while it is routing (a fleeing unit is not observing).
static func observer_range(observer: Unit) -> float:
	if observer.state == Unit.State.ROUTING:
		return observer.sight_range * Unit.SIGHT_ROUTING_PENALTY
	return observer.sight_range


## The enemy uids `team` sees this tick, as a Dictionary set (uid -> true). `units` is
## every unit in play (the "units" and "routers" groups together); friendlies never appear
## in the result because a team always knows its own army.
static func visible_enemy_uids(team: int, units: Array) -> Dictionary:
	var observers: Array = []
	for u in units:
		if u.team == team:
			observers.append(u)
	var seen: Dictionary = {}
	for t in units:
		if t.team == team:
			continue
		for o in observers:
			if perceives(o.position, observer_range(o), t.position):
				seen[t.uid] = true
				break
	return seen


## Refresh a team's last-known table from this tick's `seen` set. Each visible enemy's
## entry is rewritten with where and how it was seen; an unseen enemy's entry is left
## exactly as it was and is never deleted, so a commander's memory goes stale on its own
## (the `tick` field dates it) rather than silently improving. A unit that dies unobserved
## therefore keeps its entry: the enemy commander does not learn of a death it did not see.
static func record_contacts(contacts: Dictionary, units: Array, seen: Dictionary, tick: int) -> void:
	for t in units:
		if not seen.has(t.uid):
			continue
		contacts[t.uid] = {
			"position": t.position,
			"facing": t.facing,
			"strength": t.soldiers,
			"state": t.state,
			"tick": tick,
			"team": t.team,
			"color": t.team_color,
		}
