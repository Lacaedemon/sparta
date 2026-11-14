extends GutTest
## A routed man boxed in by rock with no foe in his reach is not cornered: he backs out of the
## dead end, the one way open (SoldierLookRound), and his unit gets away, whether he sees no foe
## or a distant one.

const POCKET := Rect2(600, 1180, 220, 220)   # the walls' outer box; open to the south
const WATCH_TICKS := 1500

var _battle: Node = null


func after_each() -> void:
	SoldierFlight.perceive_threats = true
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## A U of rock round the router, its mouth to the south, his refuge to the north.
func _walls() -> Array:
	return [
		{"rect": Rect2(600, 1180, 220, 20), "type": "hill", "kind": "block"},
		{"rect": Rect2(600, 1180, 20, 220), "type": "hill", "kind": "block"},
		{"rect": Rect2(800, 1180, 20, 220), "type": "hill", "kind": "block"},
	]


func _spawn(foe_at: Vector2) -> Array:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.all_teams_control = true
	_battle.terrain = _walls()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": 4, "x": 710.0, "y": 1290.0, "facing": [0, -1]},
		{"team": 1, "type": "Infantry", "count": 12, "x": foe_at.x, "y": foe_at.y, "facing": [0, -1]},
	]
	add_child(_battle)
	await get_tree().physics_frame
	var out: Array = [null, null]
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit:
			out[(u as Unit).team] = u
	return out


func _advance(n: int) -> void:
	var target: int = _battle.current_tick() + n
	var safety: int = n * 20 + 200
	while _battle.current_tick() < target and safety > 0:
		safety -= 1
		await get_tree().physics_frame


func _gets_away(router: Unit) -> bool:
	router.rally_morale_threshold = 1000.0
	router.rout_time = 1000.0
	router.morale = 0.0
	router._rout()
	for _t in range(WATCH_TICKS):
		await _advance(1)
		if not is_instance_valid(router) or router._sim_soldier_pos.is_empty():
			return true
		var inside := false
		for p in router._sim_soldier_pos:
			if POCKET.has_point(p):
				inside = true
		if not inside:
			return true
	return false


func test_a_man_boxed_by_rock_alone_is_not_cornered() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 1
	add_child_autofree(u)
	u.position = Vector2(710, 1290)
	u.seed_sim_soldiers()
	u._sim_soldier_pos[0] = Vector2(710, 1215)   # against the north wall, inside the U
	var grown: Array[Rect2] = [Rect2(595.5, 1175.5, 229, 29), Rect2(595.5, 1175.5, 29, 229),
			Rect2(795.5, 1175.5, 29, 229)]   # the walls grown by a body radius
	var seen: Dictionary = {"threat": Vector2.ZERO, "nearest_unit": null, "nearest_index": -1,
			"nearest_distance": INF}
	assert_false(SoldierCornered.is_cornered(u, 0, Vector2.UP, seen, grown), "no foe, no corner")
	var way: Vector2 = SoldierLookRound.way_round_rock(u, 0, Vector2.UP, grown)
	assert_almost_eq(way, Vector2.DOWN, Vector2(0.0001, 0.0001), "he backs out the way he came")


func test_a_unit_routed_in_a_dead_end_with_no_foe_in_sight_gets_away() -> void:
	SoldierFlight.perceive_threats = false
	var pair: Array = await _spawn(Vector2(1500, 1290))
	assert_true(await _gets_away(pair[0]), "its men back out of the U and away")


func test_a_unit_routed_in_a_dead_end_with_a_distant_foe_gets_away() -> void:
	var pair: Array = await _spawn(Vector2(1150, 1600))
	assert_true(await _gets_away(pair[0]), "its men back out of the U and away")
