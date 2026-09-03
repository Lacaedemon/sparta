extends RefCounted
## Decoder for deserializing replay payload dictionaries.


static func _decode_order(o: Dictionary) -> Dictionary:
	var uids: Array = []
	for u in o.get("units", []):
		uids.append(int(u))
	var entry := {
		"tick": int(o.get("tick", 0)),
		"units": uids,
		"x": float(o.get("x", 0.0)),
		"y": float(o.get("y", 0.0)),
		"target": int(o.get("target", -1)),
		"mode": int(o.get("mode", 0)),   # 0 = OrderMode.NORMAL
	}
	if o.has("formation"):
		entry["formation"] = int(o["formation"])
	if o.has("frontage"):
		entry["frontage"] = int(o["frontage"])
	if o.has("anchor_offset"):
		entry["anchor_offset"] = float(o["anchor_offset"])
	if o.has("face"):
		entry["face"] = float(o["face"])
	if o.has("group_attack"):
		entry["group_attack"] = int(o["group_attack"])
	if o.has("form_up_group"):
		entry["form_up_group"] = int(o["form_up_group"])
	if o.has("walk_advance_toggle"):
		entry["walk_advance_toggle"] = int(o["walk_advance_toggle"])
	if o.has("reform_toggle"):
		entry["reform_toggle"] = int(o["reform_toggle"])
	if o.has("file_major_reform_mode_toggle"):
		entry["file_major_reform_mode_toggle"] = int(o["file_major_reform_mode_toggle"])
	# Absent in a pre-line replay (and in every plain form-up), which then reads back as
	# Battle.LINE_INDEX_UNCHANGED in _apply_order_cmd -- each unit keeps the line_index it
	# already has, exactly as those replays behaved before this field existed.
	if o.has("line"):
		entry["line"] = int(o["line"])
	return entry


static func decode(data: Dictionary) -> Dictionary:
	var orders: Array = []
	for o in data.get("orders", []):
		orders.append(_decode_order(o))
	var camera: Array = []
	for c in data.get("camera", []):
		camera.append({
			"tick": int(c.get("tick", 0)),
			"x": float(c.get("x", 0.0)),
			"y": float(c.get("y", 0.0)),
			"zoom": float(c.get("zoom", 1.0)),
		})
	var pointer: Array = []
	for p in data.get("pointer", []):
		var sel: Array = []
		for u in p.get("sel", []):
			sel.append(int(u))
		var pe := {
			"tick": int(p.get("tick", 0)),
			"x": float(p.get("x", 0.0)),
			"y": float(p.get("y", 0.0)),
			"drag": bool(p.get("drag", false)),
			"sel": sel,
			"mode": int(p.get("mode", 0)),
		}
		if pe["drag"]:
			pe["sx"] = float(p.get("sx", pe["x"]))
			pe["sy"] = float(p.get("sy", pe["y"]))
		pointer.append(pe)
	var keys: Array = []
	for k in data.get("keys", []):
		var labels: Array = []
		for s in k.get("labels", []):
			labels.append(str(s))
		keys.append({"tick": int(k.get("tick", 0)), "labels": labels})
	var time_scale: Array = []
	for t in data.get("time_scale", []):
		time_scale.append({
			"tick": int(t.get("tick", 0)),
			"value": float(t.get("value", 1.0)),
		})
	return {
		"version": int(data.get("version", 0)),
		"physics_tps": int(data.get("physics_tps", 0)),
		"seed": int(str(data.get("seed", "0"))),
		"commit_sha": str(data.get("commit_sha", "")),
		"map": data.get("map", {}),
		"spawn_fingerprint": str(data.get("spawn_fingerprint", "")),
		"orders": orders,
		"camera": camera,
		"pointer": pointer,
		"keys": keys,
		"time_scale": time_scale,
	}
