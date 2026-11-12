extends GutTest
## Cost of ManPerception on the cannae_scale clip. A measurement, not an assertion: it runs
## only when SPARTA_MEASURE_MAN_PERCEPTION=1, so the normal suite skips it.
##
##   SPARTA_MEASURE_MAN_PERCEPTION=1 godot --headless --path . -s addons/gut/gut_cmdln.gd \
##     -gconfig= -gtest=res://test/unit/test_man_perception_cost.gd -gexit
##
## Each of TICKS ticks, every man of every unit with bodies (about 1600 on cannae_scale)
## asks what he perceives, which is the upper bound: a consumer needs far fewer, such as
## the routers or the men in contact. Prints the mean, median, p95 and max milliseconds
## per tick of the queries (including prepare), the microseconds per man, and the foe
## bodies perceived per man, once at the default radius and once at 5 m (100 world units).
## Wall-clock times swing with machine load; the foe-bodies figure is deterministic.

const ManPerception = preload("res://scripts/ManPerception.gd")
const TICKS := 240
const FIVE_METRES: float = 100.0
var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _enabled() -> bool:
	if OS.get_environment("SPARTA_MEASURE_MAN_PERCEPTION") == "1":
		return true
	pass_test("skipped: set SPARTA_MEASURE_MAN_PERCEPTION=1 to measure")
	return false


func _start_cannae_scale() -> void:
	var path := "res://demos/inputs/cannae-scale.json"
	var script: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
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


func _measure(radius: float, label: String) -> void:
	await _start_cannae_scale()
	var mp := ManPerception.new()
	mp.sight_radius = radius
	var tick_us: Array = []
	var men_total := 0
	var perceived_total := 0
	for _t in range(TICKS):
		await get_tree().physics_frame
		var frame: int = Engine.get_physics_frames()
		SpatialHash.rebuild(get_tree(), frame)
		var units: Array = get_tree().get_nodes_in_group("units")
		units.append_array(get_tree().get_nodes_in_group("routers"))
		var t0: int = Time.get_ticks_usec()
		mp.prepare(frame, units, _battle.terrain, _battle._sight_path_field)
		for u in units:
			for i in range((u as Unit)._sim_soldier_pos.size()):
				perceived_total += int(mp.perceive(u, i, frame)["perceived"])
				men_total += 1
		tick_us.append(Time.get_ticks_usec() - t0)
	var sorted := tick_us.duplicate()
	sorted.sort()
	var sum := 0
	for x in tick_us:
		sum += x
	print("[man-perception-cost] %s: men/tick=%.0f | ms/tick mean=%.1f median=%.1f p95=%.1f max=%.1f | us/man=%.1f | foe bodies perceived/man=%.1f" % [
		label, float(men_total) / TICKS, sum / 1000.0 / TICKS, sorted[TICKS / 2] / 1000.0,
		sorted[int(TICKS * 0.95)] / 1000.0, sorted[-1] / 1000.0,
		float(sum) / maxf(1.0, float(men_total)), float(perceived_total) / maxf(1.0, float(men_total))])
	assert_gt(men_total, 0, "precondition: the clip has men")


func test_cost_at_the_default_radius() -> void:
	if _enabled():
		await _measure(-1.0, "default radius")


func test_cost_at_five_metres() -> void:
	if _enabled():
		await _measure(FIVE_METRES, "5 m radius")
