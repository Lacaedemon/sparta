extends RefCounted
## Fog-of-war perception: which enemy units a team can currently see, and what it
## remembers about the ones it no longer can.
##
## A pure query over unit state.
## It reads positions, teams, sight ranges, and states and writes nothing back into
## any unit. Perception output feeds unit visibility and ghost markers in Battle.
## Fog is render-only and does not affect retreat bounds or simulation state.
const PathFieldRef = preload("res://scripts/PathField.gd")
const UnitRef = preload("res://scripts/Unit.gd")

## Visibility is a disc per observer on open ground.
## A target is seen when its center lies within some friendly observer's effective sight range.
## Line of sight is blocked by occluding terrain patches (sight: block).
## Screening terrain patches (sight: screen) attenuate sight range by Unit.SIGHT_SCREEN_FACTOR
## per patch crossed.
## A unit's own team always sees it (an army knows where its own regiments stand).


## Whether an observer at `observer_pos` with `sight_range` (world units) perceives a
## target at `target_pos`. Evaluates range (attenuated by screening terrain patches
## via Unit.SIGHT_SCREEN_FACTOR) and line-of-sight occlusion against blocking patches.
## Inclusive at the boundary, compared in squared distance so no square root runs
## per observer-target pair.
static func perceives(observer_pos: Vector2, sight_range: float, target_pos: Vector2,
		terrain: Array = [], path_field: Object = null) -> bool:
	if sight_range <= 0.0:
		return false
	var dist_sq: float = observer_pos.distance_squared_to(target_pos)
	if dist_sq > sight_range * sight_range:
		return false

	# Attenuate sight range across screening patches crossed by the segment.
	var eff_range: float = sight_range
	if not terrain.is_empty():
		for patch in terrain:
			var sight: String = patch.get("sight", "block" if patch.get("kind", "block") == "block" else "screen")
			if sight == "screen":
				if PathFieldRef.segment_intersects_rect(observer_pos, target_pos, patch["rect"]):
					eff_range *= float(patch.get("screen_factor", UnitRef.SIGHT_SCREEN_FACTOR))

	if dist_sq > eff_range * eff_range:
		return false

	# Line-of-sight occlusion: blocking terrain patches.
	if path_field != null:
		if path_field.is_leg_blocked(observer_pos, target_pos, 0.0):
			return false
	elif not terrain.is_empty():
		for patch in terrain:
			var sight: String = patch.get("sight", "block" if patch.get("kind", "block") == "block" else "screen")
			if sight == "block":
				if PathFieldRef.segment_intersects_rect(observer_pos, target_pos, patch["rect"]):
					return false
	elif PathFieldRef.active != null:
		if PathFieldRef.active.is_leg_blocked(observer_pos, target_pos, 0.0):
			return false

	return true


## The sight range an observing unit contributes this tick: its own `sight_range`, cut by
## `Unit.SIGHT_ROUTING_PENALTY` while it is routing (a fleeing unit is not observing).
static func observer_range(observer: Unit) -> float:
	if observer.state == Unit.State.ROUTING:
		return observer.sight_range * Unit.SIGHT_ROUTING_PENALTY
	return observer.sight_range


## The enemy uids `team` sees this tick, as a Dictionary set (uid -> true). `units` is
## every unit in play (the "units" and "routers" groups together); friendlies never appear
## in the result because a team always knows its own army.
static func visible_enemy_uids(team: int, units: Array, terrain: Array = [],
		path_field: Object = null) -> Dictionary:
	var observers: Array = []
	for u in units:
		if u.team == team:
			observers.append(u)
	var seen: Dictionary = {}
	for t in units:
		if t.team == team:
			continue
		for o in observers:
			if perceives(o.position, observer_range(o), t.position, terrain, path_field):
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
