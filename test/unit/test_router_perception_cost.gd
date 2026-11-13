extends GutTest
## What a routed man's perception costs (SoldierFlight.threat over ManPerception) on the
## cannae_scale clip. A measurement, not an assertion: it runs only when
## SPARTA_MEASURE_ROUTER_PERCEPTION=1, so the normal suite skips it.
##
##   SPARTA_MEASURE_ROUTER_PERCEPTION=1 godot --headless --path . -s addons/gut/gut_cmdln.gd \
##     -gconfig= -gtest=res://test/unit/test_router_perception_cost.gd -gexit
##
## The clip is run twice from the same seed, once with routers querying perception
## (SoldierFlight.perceive_threats on) and once without, and each prints the mean, median, p95
## and max wall-clock milliseconds per battle tick over TICKS ticks (the clip's own 300 by
## default; SPARTA_MEASURE_TICKS overrides it), with the routed men per tick, since only routers
## query. The routing change's added cost is the difference of the two means. Wall-clock times
## swing with machine load, so run it on an idle machine; the router counts are deterministic
## for a given run.

const DEFAULT_TICKS := 300
var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	SoldierFlight.perceive_threats = true
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _enabled() -> bool:
	if OS.get_environment("SPARTA_MEASURE_ROUTER_PERCEPTION") == "1":
		return true
	pending("skipped: set SPARTA_MEASURE_ROUTER_PERCEPTION=1 to measure")
	return false


func _ticks() -> int:
	var spec: String = OS.get_environment("SPARTA_MEASURE_TICKS")
	return spec.to_int() if spec.is_valid_int() and spec.to_int() > 0 else DEFAULT_TICKS


func _start_cannae_scale() -> void:
	var script: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://demos/inputs/cannae-scale.json"))
	Replay.forced_seed = int(script["seed"])
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = script["scenario"]
	var terrain: Array = []
	for p in script["map"]["terrain"]:
		var patch: Dictionary = (p as Dictionary).duplicate()
		var r: Array = patch["rect"]
		patch["rect"] = Rect2(r[0], r[1], r[2], r[3])
		terrain.append(patch)
	_battle.terrain = terrain
	add_child(_battle)
	await get_tree().physics_frame


## Run the clip with perception `on` and return [mean ms/tick, routed men summed over ticks].
func _measure(on: bool, label: String) -> Array:
	SoldierFlight.perceive_threats = on
	await _start_cannae_scale()
	var ticks: int = _ticks()
	var tick_us: Array = []
	var routed: int = 0
	for _t in range(ticks):
		var t0: int = Time.get_ticks_usec()
		await get_tree().physics_frame
		tick_us.append(Time.get_ticks_usec() - t0)
		for u in get_tree().get_nodes_in_group("routers"):
			routed += (u as Unit)._sim_soldier_pos.size()
	var sorted := tick_us.duplicate()
	sorted.sort()
	var sum := 0
	for x in tick_us:
		sum += x
	var mean_ms: float = sum / 1000.0 / ticks
	print("[router-perception-cost] %s: ticks=%d | ms/tick mean=%.2f median=%.2f p95=%.2f max=%.2f | routed men/tick=%.1f" % [
		label, ticks, mean_ms, sorted[ticks / 2] / 1000.0, sorted[int(ticks * 0.95)] / 1000.0,
		sorted[-1] / 1000.0, float(routed) / ticks])
	_battle.free()
	_battle = null
	await get_tree().physics_frame
	return [mean_ms, routed]


func test_cost_of_router_perception_on_cannae_scale() -> void:
	if not _enabled():
		return
	var off: Array = await _measure(false, "perception off")
	var on: Array = await _measure(true, "perception on")
	print("[router-perception-cost] added mean ms/tick (on - off) = %.2f" % (on[0] - off[0]))
	assert_gt(_ticks(), 0, "precondition: the clip ran")
