extends RefCounted
## Presentation track: camera keyframes captured during live play.

var track: Array = []
var index: int = 0


func reset() -> void:
	track.clear()
	index = 0


func has_track() -> bool:
	return not track.is_empty()


func record_camera(tick: int, pos: Vector2, zoom: float) -> void:
	if not track.is_empty():
		var last: Dictionary = track[track.size() - 1]
		if is_equal_approx(last["x"], pos.x) and is_equal_approx(last["y"], pos.y) \
				and is_equal_approx(last["zoom"], zoom):
			return
	track.append({"tick": tick, "x": pos.x, "y": pos.y, "zoom": zoom})


func for_tick(tick: int) -> Dictionary:
	if track.is_empty():
		return {}
	if index > 0 and int(track[index]["tick"]) > tick:
		index = 0
	while index + 1 < track.size() \
			and int(track[index + 1]["tick"]) <= tick:
		index += 1
	return track[index]
