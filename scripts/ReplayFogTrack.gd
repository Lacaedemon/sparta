extends RefCounted
## Fog-of-war track: mid-battle fog toggles feeding simulation playback.

var track: Array = []
var index: int = 0
var initial_value: bool = false


func reset() -> void:
	track.clear()
	index = 0
	initial_value = false


func init_state(initial_fog: bool) -> void:
	initial_value = initial_fog


func record_fog_change(tick: int, value: bool) -> void:
	var current: bool = initial_value
	if not track.is_empty():
		current = bool(track[track.size() - 1]["value"])
	if value == current:
		return
	track.append({"tick": tick, "value": value})


## Return 1 if fog toggled on at tick, 0 if fog toggled off, or -1 if no change.
func for_tick(tick: int) -> int:
	var out := -1
	while index < track.size() \
			and int(track[index]["tick"]) == tick:
		out = 1 if bool(track[index]["value"]) else 0
		index += 1
	return out


func rewind_cursor_to_tick(tick: int) -> void:
	index = 0
	while index < track.size() \
			and int(track[index]["tick"]) < tick:
		index += 1
