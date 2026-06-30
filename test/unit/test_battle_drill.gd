extends GutTest
## Drill / solo mode (#390): with Battle.drill_mode set before the node enters the tree, only
## the player army (team 0) deploys and the battle never auto-ends on "no enemies" — so a unit
## can rehearse a maneuver in isolation (what the maneuver demos record).


func test_drill_mode_spawns_only_team0_and_never_auto_ends() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true                   # must be set before _ready
	add_child_autofree(battle)
	for _k in range(40):                       # spawn + a stretch of ticks with no opponent
		await get_tree().physics_frame
	var team0 := 0
	var team1 := 0
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null:
			continue
		if unit.team == 0:
			team0 += 1
		elif unit.team == 1:
			team1 += 1
	assert_gt(team0, 0, "the player army still deploys in drill mode")
	assert_eq(team1, 0, "no enemy army deploys in drill mode")
	assert_false(battle._ended,
		"drill mode does not auto-win when there are no enemies — the rehearsal runs on")
