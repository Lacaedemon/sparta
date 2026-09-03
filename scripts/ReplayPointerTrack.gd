extends RefCounted
## Presentation track: cursor, drag-box, selection, and armed stance.

const POINTER_EPS := 1.5

var track: Array = []
var index: int = 0


func reset() -> void:
	track.clear()
	index = 0


func has_track() -> bool:
	return not track.is_empty()


func _advance_index(tick: int) -> void:
	if index > 0 and int(track[index]["tick"]) > tick:
		index = 0
	while index + 1 < track.size() \
			and int(track[index + 1]["tick"]) <= tick:
		index += 1


func record_pointer(tick: int, cursor: Vector2, dragging: bool, drag_start: Vector2,
		selection: Array, armed_mode: int) -> void:
	if not track.is_empty():
		var last: Dictionary = track[track.size() - 1]
		var still: bool = bool(last["drag"]) == dragging \
				and int(last["mode"]) == armed_mode \
				and last["sel"] == selection \
				and Vector2(last["x"], last["y"]).distance_squared_to(cursor) <= POINTER_EPS * POINTER_EPS
		if still and dragging:
			still = Vector2(last.get("sx", 0.0), last.get("sy", 0.0)).distance_squared_to(drag_start) <= POINTER_EPS * POINTER_EPS
		if still:
			return
	var entry := {
		"tick": tick,
		"x": cursor.x,
		"y": cursor.y,
		"drag": dragging,
		"sel": selection.duplicate(),
		"mode": armed_mode,
	}
	if dragging:
		entry["sx"] = drag_start.x
		entry["sy"] = drag_start.y
	track.append(entry)


func for_tick(tick: int) -> Dictionary:
	if track.is_empty():
		return {}
	_advance_index(tick)
	return track[index]


func cursor_for_tick(tick: int) -> Vector2:
	if track.is_empty():
		return Vector2.ZERO
	_advance_index(tick)
	var cur: Dictionary = track[index]
	var cur_pos := Vector2(cur["x"], cur["y"])
	if index + 1 >= track.size():
		return cur_pos
	var nxt: Dictionary = track[index + 1]
	var span: float = float(int(nxt["tick"]) - int(cur["tick"]))
	if span <= 0.0:
		return cur_pos
	var f: float = clampf(float(tick - int(cur["tick"])) / span, 0.0, 1.0)
	return cur_pos.lerp(Vector2(nxt["x"], nxt["y"]), f)
