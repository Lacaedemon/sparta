extends RefCounted
## Time-scale track: slow-motion hotkey changes feeding simulation playback.

var track: Array = []
var index: int = 0


func reset() -> void:
	track.clear()
	index = 0


func record_time_scale_change(tick: int, value: float) -> void:
	var current := 1.0
	if not track.is_empty():
		current = float(track[track.size() - 1]["value"])
	if is_equal_approx(value, current):
		return
	track.append({"tick": tick, "value": value})


func for_tick(tick: int) -> float:
	var out := -1.0
	while index < track.size() \
			and int(track[index]["tick"]) == tick:
		out = float(track[index]["value"])
		index += 1
	return out


func rewind_cursor_to_tick(tick: int) -> void:
	index = 0
	while index < track.size() \
			and int(track[index]["tick"]) < tick:
		index += 1
