class_name DemoRelational
extends RefCounted
## The men judged against the men they follow, never against a point of a grid in the world.
## A dump's `relations` (DemoState.relations) name, for each man, the man ahead of him in his
## file and the man to his right in his rank, with where he stands from each in the grid's own
## frame as (right, behind). Those relations hold however the block is turned, shifted or folded,
## so the one rotation the men's relations share is fitted from the men themselves, and what
## remains is each man's error from the place behind his leader and from his interval to his
## dressing man. Pure, and a leaf: it runs under bare `godot -s` with no autoloads.


## Each relation edge read off the men at `pos`: [actual, target, man, other, kind], where
## `actual` is the world vector the men stand at, `target` the grid-frame offset it should be,
## `man` the man judged, `other` the man he is judged from, and `kind` 0 for a leader edge
## (man behind other) and 1 for a dressing edge (other to the man's right).
static func edges(pos: Array, rel: Dictionary) -> Array:
	var out: Array = []
	if not rel.has("leaders"):
		return out
	for kind in range(2):
		var who: Array = rel["leaders"] if kind == 0 else rel["dress"]
		var offs: Array = rel["offsets"] if kind == 0 else rel["dress_offsets"]
		for i in range(mini(who.size(), pos.size())):
			var j: int = int(who[i])
			if j < 0 or j >= pos.size():
				continue
			var a := Vector2(pos[i][0], pos[i][1])
			var b := Vector2(pos[j][0], pos[j][1])
			out.append([(a - b) if kind == 0 else (b - a),
					Vector2(offs[i][0], offs[i][1]), i, j, kind])
	return out


## The rotation the grid frame has taken in the world, the one that best fits every edge's
## target onto where the men stand (the 2-D Kabsch angle over edge vectors, which needs no
## centroid, so no point of the grid is read).
static func angle(edge_list: Array) -> float:
	var dot_sum: float = 0.0
	var cross_sum: float = 0.0
	for e in edge_list:
		dot_sum += (e[1] as Vector2).dot(e[0])
		cross_sum += (e[1] as Vector2).cross(e[0])
	return atan2(cross_sum, dot_sum)


## Whether man `i`, who stands `err` from the place behind his leader (`place` is the offset to
## it in the world), stands on the place behind some other man instead: within `stand` of it and
## nearer it than his own. He has taken the wrong man for his leader; a man still walking, near
## no man's place, has taken none.
static func _behind_wrong_man(pos: Array, i: int, leader: int, place: Vector2, err: float,
		stand: float) -> bool:
	var me := Vector2(pos[i][0], pos[i][1])
	for k in range(pos.size()):
		if k != i and k != leader \
				and me.distance_to(Vector2(pos[k][0], pos[k][1]) + place) < minf(err, stand):
			return true
	return false


## Reading of one sample: `rms` over every edge's error from where it should be, `far` the
## largest one, `behind_wrong` the men who stand on the place behind another man rather than
## behind their leader (or on the wrong side of their dressing man), `settled` the median error of
## the men with a leader (the gate misslot reads only below: who a man stands nearest in transit
## is noise, while a minority of swapped men leaves the median where it was, so a swap can
## still be read), and `men` how many men have a leader. `edges` is zero when the dump carries
## no relations.
static func read(pos: Array, rel: Dictionary, stand: float) -> Dictionary:
	var list: Array = edges(pos, rel)
	if list.is_empty():
		return {"edges": 0, "rms": 0.0, "far": 0.0, "behind_wrong": 0, "settled": 0.0, "men": 0}
	var turn: float = angle(list)
	var sq: float = 0.0
	var far: float = 0.0
	var wrong: Dictionary = {}
	var led_errors: Array = []
	for e in list:
		var place: Vector2 = (e[1] as Vector2).rotated(turn)
		var err: float = ((e[0] as Vector2) - place).length()
		sq += err * err
		far = maxf(far, err)
		if e[4] == 1:
			if (e[0] as Vector2).dot(Vector2.RIGHT.rotated(turn)) * (e[1] as Vector2).x < 0.0:
				wrong[e[2]] = true
				wrong[e[3]] = true
			continue
		led_errors.append(err)
		if _behind_wrong_man(pos, e[2], e[3], place, err, stand):
			wrong[e[2]] = true
	led_errors.sort()
	return {"edges": list.size(), "rms": sqrt(sq / list.size()), "far": far,
			"behind_wrong": wrong.size(),
			"settled": led_errors[floori(led_errors.size() / 2.0)] if not led_errors.is_empty() else 0.0,
			"men": led_errors.size()}
