extends RefCounted
## Presentation track: hotkey presses captured during live play.

var track: Array = []


func reset() -> void:
	track.clear()


func record_keys(tick: int, labels: Array) -> void:
	if labels.is_empty():
		return
	track.append({"tick": tick, "labels": labels.duplicate()})


func for_tick(tick: int, window: int) -> Array:
	var out: Array = []
	for k in track:
		var kt: int = int(k["tick"])
		if kt > tick:
			break
		if tick - kt <= window:
			for label in k["labels"]:
				out.append({"label": str(label), "age": tick - kt})
	return out
