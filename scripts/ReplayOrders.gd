extends RefCounted
## Orders stream: order queue, playback cursor, pulse and form-up queries.

var orders: Array = []
var play_index: int = 0


func reset() -> void:
	orders.clear()
	play_index = 0


func append(entry: Dictionary) -> void:
	orders.append(entry)


func rewind_cursor_to_tick(tick: int) -> void:
	play_index = 0
	while play_index < orders.size() and int(orders[play_index]["tick"]) < tick:
		play_index += 1


func orders_for_tick(tick: int) -> Array:
	var due: Array = []
	while play_index < orders.size() and int(orders[play_index]["tick"]) == tick:
		due.append(orders[play_index])
		play_index += 1
	# Skip any (shouldn't happen) orders whose tick we've already passed.
	while play_index < orders.size() and int(orders[play_index]["tick"]) < tick:
		play_index += 1
	return due


func pulses_for_tick(tick: int, window: int) -> Array:
	var out: Array = []
	for o in orders:
		var ot: int = int(o["tick"])
		if ot > tick:
			break
		if tick - ot <= window:
			out.append({"x": float(o["x"]), "y": float(o["y"]), "age": tick - ot})
	return out


func form_ups_for_tick(tick: int, window: int) -> Array:
	var out: Array = []
	for o in orders:
		var ot: int = int(o["tick"])
		if ot > tick:
			break
		if o.has("face") and tick - ot <= window:
			var uids: Array = o.get("units", [])
			out.append({"x": float(o["x"]), "y": float(o["y"]), "face": float(o["face"]),
					"frontage": int(o.get("frontage", 1)), "age": tick - ot,
					"uid": int(uids[0]) if not uids.is_empty() else -1})
	return out
