extends RefCounted
## Codec for serializing replay payload dictionaries.

const FORMAT_VERSION := 1
const PHYSICS_TPS := 60


static func encode(state: Dictionary) -> Dictionary:
	var payload := {
		"version": FORMAT_VERSION,
		"seed": str(state.get("seed", 0)),
		"physics_tps": PHYSICS_TPS,
		"created": state.get("created", Time.get_unix_time_from_system()),
		"result": str(state.get("result", "")),
		"duration_ticks": int(state.get("duration_ticks", 0)),
		"commit_sha": str(state.get("commit_sha", "")),
		"orders": state.get("orders", []),
	}
	var map_data: Dictionary = state.get("map", {})
	if not map_data.is_empty():
		payload["map"] = map_data
	var fingerprint: String = str(state.get("spawn_fingerprint", ""))
	if fingerprint != "":
		payload["spawn_fingerprint"] = fingerprint
	var dirty: String = str(state.get("git_dirty_status", ""))
	if not dirty.is_empty():
		payload["git_dirty_status"] = dirty
	for track_key in ["camera", "pointer", "keys", "time_scale"]:
		var arr: Array = state.get(track_key, [])
		if not arr.is_empty():
			payload[track_key] = arr
	return payload
