class_name ScreenCapture
## Internal API for automation: screenshots, state dumps, and rendering sync.
## Usage: ScreenCapture.screenshot("demos/shots/verify.png")
##        ScreenCapture.state_dump("user://state.json")

static func screenshot(path: String) -> bool:
	"""Capture a screenshot to PNG after ensuring rendering is complete."""
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("Failed to capture viewport")
		return false
	var err := img.save_png(path)
	if err == OK:
		print("Screenshot saved: %s" % path)
		return true
	else:
		push_error("Failed to save screenshot: %d" % err)
		return false


static func state_dump(path: String, ticks: PackedInt32Array = []) -> bool:
	"""Dump game state (units, positions, morale) to JSON for verification."""
	var battle := _get_battle()
	if battle == null:
		push_error("Battle not found")
		return false

	var state := {}
	state["current_tick"] = battle.current_tick
	state["units"] = []

	for unit_node in battle.get_tree().get_nodes_in_group("units"):
		var u = unit_node as Unit
		if u == null or not is_instance_valid(u):
			continue
		state["units"].append({
			"uid": u.uid,
			"name": u.unit_name,
			"team": u.team,
			"position": {"x": u.position.x, "y": u.position.y},
			"morale": u.morale,
			"soldiers": u.soldiers,
			"state": Unit.STATE_NAMES.get(u.state, "UNKNOWN"),
		})

	var json_str := JSON.stringify(state, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for write: %s" % path)
		return false
	file.store_string(json_str)
	print("State dump saved: %s" % path)
	return true


static func _get_battle() -> Node:
	"""Find the Battle scene root."""
	var root := get_tree().root
	for child in root.get_children():
		if child is Battle:
			return child
	return null
