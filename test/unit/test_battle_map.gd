extends GutTest
## Per-battle map definitions: BattleMap's pure parse/serialize contract, and a live
## Battle rebuilding its battlefield from instance map data instead of the consts.
## The consts remain the DEFAULT map; these tests pin both halves of that split.


# --- parse ---------------------------------------------------------------------

func test_parse_reads_field_terrain_and_spawn_lines() -> void:
	var out: Dictionary = BattleMap.parse({
		"field": [800, 1600],
		"terrain": [
			{"rect": [100, 400, 200, 300], "type": "hill", "kind": "block"},
			{"rect": [500, 400, 200, 300], "type": "forest", "kind": "slow", "speed": 0.5},
		],
		"spawn_lines": [200, 1400],
	})
	assert_eq(out.get("field"), Rect2(0, 0, 800, 1600), "field parses to an origin rect")
	assert_eq((out.get("terrain") as Array).size(), 2, "both patches parse")
	assert_eq(out["terrain"][0]["rect"], Rect2(100, 400, 200, 300), "block rect parses")
	assert_eq(str(out["terrain"][1]["kind"]), "slow", "slow kind carries through")
	assert_almost_eq(float(out["terrain"][1]["speed"]), 0.5, 0.001, "slow speed carries through")
	assert_eq(out.get("spawn_lines"), [200.0, 1400.0], "spawn lines parse as floats")


func test_parse_keeps_absent_keys_absent_so_defaults_survive() -> void:
	var out: Dictionary = BattleMap.parse({"field": [640, 640]})
	assert_true(out.has("field"), "the supplied key parses")
	assert_false(out.has("terrain"), "an absent terrain key stays absent (keep the default)")
	assert_false(out.has("spawn_lines"), "an absent spawn_lines key stays absent")


func test_parse_rejects_malformed_blocks_with_named_errors() -> void:
	# Map geometry decides WHAT battle runs, so a bad block must fail loudly --
	# never degrade to a plausible-looking battle on the wrong battlefield.
	assert_true(BattleMap.parse({"field": [0, 100]}).has("error"), "zero width is an error")
	assert_true(BattleMap.parse({"field": [100]}).has("error"), "a one-element field is an error")
	assert_true(BattleMap.parse({"terrain": "hill"}).has("error"), "non-array terrain is an error")
	assert_true(BattleMap.parse({"terrain": [{"rect": [1, 2, 3]}]}).has("error"),
			"a three-element rect is an error")
	assert_true(BattleMap.parse({"terrain": [{"rect": [0, 0, 10, 10], "kind": "swamp"}]}).has("error"),
			"an unknown patch kind is an error")
	assert_true(BattleMap.parse({"terrain": [{"rect": [0, 0, 10, 10], "kind": "slow"}]}).has("error"),
			"a slow patch without a speed is an error")
	assert_true(BattleMap.parse({"spawn_lines": [100]}).has("error"),
			"a one-element spawn_lines is an error")


func test_serialize_round_trips_through_parse() -> void:
	var terrain: Array = [
		{"rect": Rect2(100, 400, 200, 300), "type": "hill", "kind": "block"},
		{"rect": Rect2(500, 400, 200, 300), "type": "forest", "kind": "slow", "speed": 0.5},
	]
	var blob: Dictionary = BattleMap.serialize(Rect2(0, 0, 800, 1600), terrain, [200.0, 1400.0])
	var back: Dictionary = BattleMap.parse(blob)
	assert_false(back.has("error"), "a serialized map parses clean")
	assert_eq(back["field"], Rect2(0, 0, 800, 1600), "field survives the round trip")
	assert_eq(back["terrain"][0]["rect"], terrain[0]["rect"], "block rect survives")
	assert_almost_eq(float(back["terrain"][1]["speed"]), 0.5, 0.001, "slow speed survives")
	assert_eq(back["spawn_lines"], [200.0, 1400.0], "spawn lines survive")


func test_differs_from_default_detects_each_axis_and_accepts_the_default() -> void:
	var d_field := Rect2(0, 0, 1600, 1200)
	var d_terrain: Array = [{"rect": Rect2(1, 1, 2, 2), "type": "hill", "kind": "block"}]
	var d_spawn: Array = [300.0, 880.0]
	assert_false(BattleMap.differs_from_default(d_field, d_terrain.duplicate(true), d_spawn.duplicate(),
			d_field, d_terrain, d_spawn), "the default map does not differ from itself")
	assert_true(BattleMap.differs_from_default(Rect2(0, 0, 800, 800), d_terrain, d_spawn,
			d_field, d_terrain, d_spawn), "a different field differs")
	assert_true(BattleMap.differs_from_default(d_field, [], d_spawn,
			d_field, d_terrain, d_spawn), "different terrain differs")
	assert_true(BattleMap.differs_from_default(d_field, d_terrain, [300.0, 700.0],
			d_field, d_terrain, d_spawn), "different spawn lines differ")


# --- a live battle rebuilds the battlefield from instance map data ----------------

func _spawn_battle_with(field: Rect2, terrain: Array, spawn_lines: Array) -> Node:
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle: Node = scene.instantiate()
	battle.field = field
	battle.terrain = terrain
	battle.spawn_line_ys = spawn_lines
	add_child_autofree(battle)
	return battle


func test_battle_defaults_run_on_the_default_map() -> void:
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle: Node = scene.instantiate()
	assert_eq(battle.field, battle.FIELD, "the instance field defaults to the const map")
	assert_eq(battle.terrain, battle.TERRAIN, "the instance terrain defaults to the const map")
	assert_eq(battle.spawn_line_ys, battle.SPAWN_LINE_YS, "spawn lines default to the const map")
	battle.free()


func test_custom_field_sizes_the_routing_grid_camera_and_rout_margin() -> void:
	var small := Rect2(0, 0, 640, 640)
	var battle: Node = _spawn_battle_with(small, [], [100.0, 540.0])
	assert_eq(battle.FIELD_WITH_MARGIN, small.grow(battle.ROUT_MARGIN),
			"the rout margin tracks the live field, not the default const")
	assert_not_null(PathField.active, "a routing grid was built")
	assert_true(PathField.active.has_path(Vector2(50, 50), Vector2(600, 600)),
			"the routing grid spans the custom field (a route across it exists)")
	assert_true(PathField.active.has_escape_route(Vector2(320, 320), Vector2(1, 0)),
			"escape queries stay in-bounds on the custom grid")


func test_custom_terrain_blocks_routing_on_the_custom_map() -> void:
	var wall: Array = [{"rect": Rect2(300, 0, 64, 560), "type": "hill", "kind": "block"}]
	var battle: Node = _spawn_battle_with(Rect2(0, 0, 640, 640), wall, [100.0, 540.0])
	assert_true(battle != null, "battle spawned")
	assert_ne(PathField.active.next_step(Vector2(50, 50), Vector2(600, 50)), Vector2(600, 50),
			"the custom wall forces a detour on the live routing grid")


func test_custom_spawn_lines_place_the_default_armies() -> void:
	var battle: Node = _spawn_battle_with(Rect2(0, 0, 1600, 1600), [], [250.0, 1350.0])
	var top_ys: Array = []
	var bottom_ys: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		if u.team == 0:
			top_ys.append(u.position.y)
		else:
			bottom_ys.append(u.position.y)
	assert_gt(top_ys.size(), 0, "team 0 spawned")
	assert_gt(bottom_ys.size(), 0, "team 1 spawned")
	for y in top_ys:
		assert_almost_eq(float(y), 250.0, 0.001, "team 0 deploys on the custom attacker line")
	for y in bottom_ys:
		assert_almost_eq(float(y), 1350.0, 0.001, "team 1 deploys on the custom defender line")


func test_non_default_map_is_published_to_the_replay_and_restored_on_playback() -> void:
	var custom_terrain: Array = [{"rect": Rect2(100, 700, 300, 200), "type": "hill", "kind": "block"}]
	var battle: Node = _spawn_battle_with(Rect2(0, 0, 900, 1500), custom_terrain, [200.0, 1300.0])
	assert_true(battle != null, "battle spawned")
	assert_false(Replay.map.is_empty(), "a non-default map is published to the recording")
	var restored: Dictionary = BattleMap.parse(Replay.map)
	assert_false(restored.has("error"), "the published map parses clean")
	assert_eq(restored["field"], Rect2(0, 0, 900, 1500), "the published field matches the live one")
	assert_eq(restored["spawn_lines"], [200.0, 1300.0], "the published spawn lines match")


func test_playback_restores_the_recorded_map_before_rebuilding_the_battlefield() -> void:
	# Arm playback by hand: seed + a recorded map block, no orders. Battle._ready
	# must apply the map before any consumer (camera, routing grid, spawns) runs.
	var old_mode: int = Replay.mode
	var old_map: Dictionary = Replay.map
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.seed_value = 424242
	Replay.rng.seed = Replay.seed_value
	Replay.map = BattleMap.serialize(Rect2(0, 0, 700, 900),
			[{"rect": Rect2(100, 400, 200, 100), "type": "hill", "kind": "block"}],
			[150.0, 750.0])
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle: Node = scene.instantiate()
	add_child_autofree(battle)
	assert_eq(battle.field, Rect2(0, 0, 700, 900), "playback rebuilds the recorded field")
	assert_eq((battle.terrain as Array).size(), 1, "playback rebuilds the recorded terrain")
	assert_eq(battle.spawn_line_ys, [150.0, 750.0], "playback rebuilds the recorded spawn lines")
	assert_eq(battle.FIELD_WITH_MARGIN, Rect2(0, 0, 700, 900).grow(battle.ROUT_MARGIN),
			"the rout margin tracks the restored field")
	Replay.mode = old_mode
	Replay.map = old_map


func test_playback_with_a_bad_map_block_warns_and_keeps_the_default_map() -> void:
	# A hand-edited replay with a corrupt map block must not silently run a
	# plausible-looking battle on the wrong battlefield: it warns and falls back
	# to the default map (the seed/orders still replay, just on default ground).
	var old_mode: int = Replay.mode
	var old_map: Dictionary = Replay.map
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.seed_value = 424242
	Replay.rng.seed = Replay.seed_value
	Replay.map = {"field": [0, -5]}
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle: Node = scene.instantiate()
	add_child_autofree(battle)
	assert_eq(battle.field, battle.FIELD, "a corrupt map block falls back to the default field")
	assert_eq(battle.terrain, battle.TERRAIN, "and the default terrain")
	Replay.mode = old_mode
	Replay.map = old_map


func test_default_map_publishes_no_replay_map_block() -> void:
	var scene := load("res://scenes/Battle.tscn") as PackedScene
	var battle: Node = scene.instantiate()
	add_child_autofree(battle)
	assert_true(Replay.map.is_empty(),
			"a default-map battle records no map block, keeping the pre-map replay shape")
