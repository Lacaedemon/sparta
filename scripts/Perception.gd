extends RefCounted
## Fog-of-war perception: which enemy units a team can currently see, and what it
## remembers about the ones it no longer can.
##
## A pure query over unit state.
## It reads positions, teams, sight ranges, and states and writes nothing back into
## any unit. Perception output feeds unit visibility and ghost markers in Battle, AND
## (via Battle.ai_team_perceives / Unit._enemy_is_perceived, both layered on top of this
## module's own visible_enemy_uids) gates AI/order targeting decisions -- fog is NOT
## purely render-only overall, though this module's own read-only nature is unchanged.
## It does not affect retreat bounds or collision.
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


## The grid cells `observers` currently perceive, as row-major indices (cy * grid_w + cx)
## into a grid_w x grid_h array covering `field` at `cell_size`. Reuses `perceives()` per
## cell center, so a cell counts as seen under exactly the same range/screening/occlusion
## rules as an enemy unit does -- terrain exploration is "was some friendly observer's
## sight disc over this ground", nothing more. Bounded per observer to the cells within its
## sight range (a bounding-box prefilter) so a battle with many empty cells doesn't pay for
## a full grid scan per observer. Returns a Dictionary set (idx -> true); this is always
## recomputed fresh (never cumulative) -- a caller wanting a persistent explored grid ORs
## this into its own storage (see Battle._fog_explored).
static func visible_cells(observers: Array, field: Rect2, cell_size: float, grid_w: int, grid_h: int,
		terrain: Array = [], path_field: Object = null) -> Dictionary:
	var out: Dictionary = {}
	if cell_size <= 0.0 or grid_w <= 0 or grid_h <= 0:
		return out
	for o in observers:
		var sight: float = observer_range(o)
		if sight <= 0.0:
			continue
		var min_cx: int = clampi(int(floor((o.position.x - sight - field.position.x) / cell_size)), 0, grid_w - 1)
		var max_cx: int = clampi(int(ceil((o.position.x + sight - field.position.x) / cell_size)), 0, grid_w - 1)
		var min_cy: int = clampi(int(floor((o.position.y - sight - field.position.y) / cell_size)), 0, grid_h - 1)
		var max_cy: int = clampi(int(ceil((o.position.y + sight - field.position.y) / cell_size)), 0, grid_h - 1)
		for cy in range(min_cy, max_cy + 1):
			for cx in range(min_cx, max_cx + 1):
				var idx: int = cy * grid_w + cx
				if out.has(idx):
					continue
				var center: Vector2 = field.position + Vector2((cx + 0.5) * cell_size, (cy + 0.5) * cell_size)
				if perceives(o.position, sight, center, terrain, path_field):
					out[idx] = true
	return out


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
