extends GutTest
## Demo scenario staging: a Battle spawned with a custom `scenario` list deploys exactly
## those units (type, team, position, and count/morale/facing overrides) instead of the
## default two-line spawn. Tooling only -- the demo recorder sets `scenario` before the
## battle enters the tree; a normal battle leaves it empty and spawns the default lines.
##
## Standing up the full Battle scene is heavy, so everything is asserted from ONE spawn of a
## rich multi-unit scenario. (The empty-scenario = default two-line path is already covered
## by test_battle_drill and test_battle_spawn_formation, which spawn the default battle.)


func test_scenario_spawns_exactly_its_units_with_types_positions_and_overrides() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		# A spearman with every override: count, morale, an explicit facing that must win
		# over the team default, and walk_advance/reform_before_move/file_major_reform
		# overrides that must win over Spearmen's own type defaults (walk_advance true,
		# reform_before_move true, file_major_reform true).
		{"team": 0, "type": "Spearmen", "x": 500, "y": 250, "count": 40, "morale": 30.0,
			"facing": [1, 0], "disciplined": false,
			"walk_advance": false, "reform_before_move": false, "file_major_reform": false},
		# A plain enemy cavalry unit: no facing override, so it takes the team-1 default (up),
		# and no disciplined override, so it takes Unit's own default (true).
		{"team": 1, "type": "Cavalry", "x": 500, "y": 750},
		# A second enemy cavalry with a MALFORMED facing (one element): must fall back to the
		# team default rather than crash, and its label must read "Cavalry 2" (per-type index).
		{"team": 1, "type": "Cavalry", "x": 700, "y": 750, "facing": [1]},
	]
	# add_child runs Battle._ready() synchronously, which spawns the scenario and sets each
	# unit's spawn-time morale and facing. Read those values NOW, before awaiting any physics
	# frame -- one tick of morale recovery / facing rotation would drift them off the exact
	# spawn value. (Under coverage instrumentation the interpreter runs slower per wall-clock
	# second, so more ticks elapse before an assert reads the value; reading pre-tick removes
	# that dependency on how fast the interpreter runs.)
	add_child_autofree(battle)

	var team0: Array = []
	var team1: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null:
			continue
		if unit.team == 0:
			team0.append(unit)
		elif unit.team == 1:
			team1.append(unit)

	# Exactly the listed units -- not the default 5-per-side lines.
	assert_eq(team0.size(), 1, "exactly the one listed team-0 unit spawns (not the default line)")
	assert_eq(team1.size(), 2, "exactly the two listed team-1 units spawn")
	if team0.is_empty() or team1.size() < 2:
		return

	var spear: Unit = team0[0]
	assert_true(spear.anti_cavalry, "type 'Spearmen' maps onto the spearmen loadout (anti-cavalry)")
	assert_almost_eq(spear.position.x, 500.0, 0.5, "the unit spawns at the spec's x")
	assert_almost_eq(spear.position.y, 250.0, 0.5, "and its y")
	assert_eq(spear.max_soldiers, 40, "the count override sets max_soldiers")
	assert_eq(spear.soldiers, 40, "and _ready() seeds the live soldier count from it")
	assert_almost_eq(spear.morale, 30.0, 0.001, "the morale override sets the starting morale")
	assert_almost_eq(spear.facing.x, 1.0, 0.001, "the explicit facing vector wins over the team default (x)")
	assert_almost_eq(spear.facing.y, 0.0, 0.001, "...and y")
	assert_false(spear.disciplined, "the disciplined:false override forwards onto the spawned unit")
	assert_false(spear.walk_advance,
		"the walk_advance:false override wins over Spearmen's own type default (true)")
	assert_false(spear.reform_before_move,
		"the reform_before_move:false override wins over the type default (true)")
	assert_false(spear.file_major_reform,
		"the file_major_reform:false override wins over the type default (true)")

	for horse: Unit in team1:
		assert_true(horse.is_cavalry, "type 'Cavalry' maps onto the cavalry loadout")
		assert_true(horse.disciplined, "with no override, a spawned unit defaults to disciplined")
		assert_false(horse.reform_before_move,
			"with no override, Cavalry's own type default (reform_before_move off) applies")
		assert_true(horse.file_major_reform,
			"with no override, every type's own file_major_reform default (on) applies")
		# The first cavalry has no facing override, the second has a MALFORMED one -- both must
		# fall back to the team-1 default (facing up), and neither may crash on the bad array.
		assert_almost_eq(horse.facing.y, -1.0, 0.001,
			"an enemy with no / a malformed facing override defaults to facing up (no crash)")

	# Labels are numbered per type, not across all teams: the two cavalry read "Cavalry 1" and
	# "Cavalry 2" (not "Cavalry 2"/"Cavalry 3" offset by the team-0 spearman).
	var cav_labels := [str(team1[0].unit_name), str(team1[1].unit_name)]
	cav_labels.sort()
	assert_eq(cav_labels, ["Cavalry 1", "Cavalry 2"],
		"unit labels are numbered per type, so cross-team spawns still read 1, 2 within a type")


func test_scenario_starting_state_routing_spawns_an_already_routing_unit() -> void:
	# For demo/test staging only (e.g. the isolated morale-recovery demo): a scenario spec
	# can force a unit straight into ROUTING on spawn, since a normal battle can only ever
	# reach that state as a side effect of real combat casualties.
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true   # no team-1 units below, so _check_victory must not fire
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 400, "starting_state": Unit.State.ROUTING},
	]
	add_child_autofree(battle)

	var routers: Array = get_tree().get_nodes_in_group("routers")
	assert_eq(routers.size(), 1, "the unit spawns already in the routers group")
	if routers.is_empty():
		return
	var unit: Unit = routers[0] as Unit
	assert_eq(unit.state, Unit.State.ROUTING, "starting_state ROUTING puts the unit straight into ROUTING")


func test_scenario_starting_state_dead_sets_the_unit_state_directly() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 400, "starting_state": Unit.State.DEAD},
	]
	add_child_autofree(battle)

	# Unlike a real death (Unit._remove_from_play), this leaves the unit un-freed so a demo
	# can show an already-dead body on the field -- find it via the Units container, not the
	# "units" group, since it's deliberately removed from that group (no longer fightable).
	var spawned: Array = battle.get_node("Units").get_children()
	assert_eq(spawned.size(), 1, "the unit still spawns (starting_state doesn't skip spawning)")
	if spawned.is_empty():
		return
	var unit: Unit = spawned[0] as Unit
	assert_eq(unit.state, Unit.State.DEAD, "starting_state DEAD sets the unit's state directly")
	assert_false(unit.is_in_group("units"), "a dead unit doesn't count as fightable, same as a real death")


func test_scenario_starting_state_unknown_value_is_a_no_op() -> void:
	# An unrecognized value (e.g. a typo'd enum int) must not silently do nothing worse than
	# leave the unit at its default IDLE -- it also warns (see _apply_starting_state), but the
	# no-crash / stays-IDLE behavior is what's asserted here.
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 400, "starting_state": 99},
	]
	add_child_autofree(battle)

	var units: Array = get_tree().get_nodes_in_group("units")
	assert_eq(units.size(), 1, "the unit still spawns")
	if units.is_empty():
		return
	var unit: Unit = units[0] as Unit
	assert_eq(unit.state, Unit.State.IDLE, "an unrecognized starting_state value leaves the unit at the default IDLE")
