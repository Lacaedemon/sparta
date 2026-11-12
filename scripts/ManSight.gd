extends RefCounted
## What blocks or shortens a man's sightlines: Perception.perceives' terrain rule, sorted
## once per frame so each sightline only runs the segment tests.
##
## A man sights from his own position, so a foe at his elbow is seen even when its unit's
## centre is out of view, and a foe behind a hill is not, even when a comrade sees it.
const PathFieldRef = preload("res://scripts/PathField.gd")


## The terrain inputs of Perception.perceives, sorted into "screens" (rects that shorten
## sight, in terrain order) with their "factors", and "blocks" (rects that stop it). Blocks
## come from where perceives reads them: the path field when one is given, else the
## terrain's blocking patches, else PathField.active (a global read). Pure apart from that.
static func compile(terrain: Array, path_field: Object) -> Dictionary:
	var screens: Array[Rect2] = []
	var factors := PackedFloat64Array()
	var blocks: Array[Rect2] = []
	for patch in terrain:
		if _sight_of(patch) == "screen":
			screens.append(patch["rect"])
			factors.append(float(patch.get("screen_factor", Unit.SIGHT_SCREEN_FACTOR)))
	if path_field != null:
		blocks.append_array(path_field.block_rects())
	elif not terrain.is_empty():
		for patch in terrain:
			if _sight_of(patch) == "block":
				blocks.append(patch["rect"])
	elif PathFieldRef.active != null:
		blocks.append_array(PathFieldRef.active.block_rects())
	return {"screens": screens, "factors": factors, "blocks": blocks}


## Whether `target` is in sight from `observer` at `radius` under `rule` (from compile):
## Perception.perceives' answer for the same inputs, for a target already known to lie
## within `radius`. Pure.
static func line_of_sight(observer: Vector2, radius: float, target: Vector2,
		rule: Dictionary) -> bool:
	var screens: Array[Rect2] = rule["screens"]
	var factors: PackedFloat64Array = rule["factors"]
	var eff: float = radius
	for k in range(screens.size()):
		if PathFieldRef.segment_intersects_rect(observer, target, screens[k]):
			eff *= factors[k]
	if observer.distance_squared_to(target) > eff * eff:
		return false
	for r in (rule["blocks"] as Array[Rect2]):
		if PathFieldRef.segment_intersects_rect(observer, target, r):
			return false
	return true


## The part of `rule` that can touch a sightline from `pos` of length at most `radius`:
## the rects overlapping the box around his sight disc, kept in their order.
static func near(rule: Dictionary, pos: Vector2, radius: float) -> Dictionary:
	var disc := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var screens: Array[Rect2] = []
	var factors := PackedFloat64Array()
	var all_screens: Array[Rect2] = rule["screens"]
	var all_factors: PackedFloat64Array = rule["factors"]
	for k in range(all_screens.size()):
		if all_screens[k].intersects(disc, true):
			screens.append(all_screens[k])
			factors.append(all_factors[k])
	var blocks: Array[Rect2] = []
	for r in (rule["blocks"] as Array[Rect2]):
		if r.intersects(disc, true):
			blocks.append(r)
	return {"screens": screens, "factors": factors, "blocks": blocks}


static func _sight_of(patch: Dictionary) -> String:
	return patch.get("sight", "block" if patch.get("kind", "block") == "block" else "screen")
