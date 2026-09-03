extends RefCounted
## Codec for serializing replay payload dictionaries.

const FORMAT_VERSION := 1
const PHYSICS_TPS := 60


static func encode(state: Dictionary) -> Dictionary:
	var created_val: float = float(state["created"]) if state.has("created") \
			else Time.get_unix_time_from_system()
	var payload := {
		"version": FORMAT_VERSION,
		"seed": str(state.get("seed", 0)),
		"physics_tps": PHYSICS_TPS,
		"created": created_val,
		"result": str(state.get("result", "")),
		"duration_ticks": int(state.get("duration_ticks", 0)),
		"commit_sha": str(state.get("commit_sha", "")),
		"orders": state.get("orders", []),
	}
	# A non-default map rides in the header so playback reconstructs the same
	# battlefield; absent for default-map battles.
	var map_data: Dictionary = state.get("map", {})
	if not map_data.is_empty():
		payload["map"] = map_data
	# Stamp the spawn-layout fingerprint so playback can fail loudly if a later
	# build's spawn table no longer matches the layout these orders were
	# recorded against (the silent spawn-drift failure mode). Absent when Battle
	# never published one; the load check then skips.
	var fingerprint: String = str(state.get("spawn_fingerprint", ""))
	if fingerprint != "":
		payload["spawn_fingerprint"] = fingerprint
	# Only emit a dirty-worktree note when the live checkout actually has
	# uncommitted changes worth flagging, omitted on an exported build or a
	# clean tree so the common case stays byte-for-byte simple.
	var dirty: String = str(state.get("git_dirty_status", ""))
	if not dirty.is_empty():
		payload["git_dirty_status"] = dirty
	# Only emit each track when captured so recordings without activity stay
	# simple; time_scale feeds the simulation on load, unlike cosmetic tracks.
	for track_key in ["camera", "pointer", "keys", "time_scale"]:
		var arr: Array = state.get(track_key, [])
		if not arr.is_empty():
			payload[track_key] = arr
	return payload
