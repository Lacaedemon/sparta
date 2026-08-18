extends GutTest

const UnitRef = preload("res://scripts/Unit.gd")

var _battle: Node

func before_each():
	_battle = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(_battle)
	# Immediately remove and free default units
	var units_node = _battle.get_node("Units")
	for u in units_node.get_children():
		units_node.remove_child(u)
		u.free()

func test_tide_of_battle_changed_signal():
	watch_signals(_battle)
	var u0 = UnitRef.new()
	u0.team = 0
	u0.max_soldiers = 100
	u0.soldiers = 100
	u0.add_to_group("units")
	_battle.get_node("Units").add_child(u0)
	autofree(u0)

	var u1 = UnitRef.new()
	u1.team = 1
	u1.max_soldiers = 50
	u1.soldiers = 50
	u1.add_to_group("units")
	_battle.get_node("Units").add_child(u1)
	autofree(u1)

	_battle._evaluate_battle_event_signals()
	# First tick sets baseline: team 0 is stronger (100 vs 50)

	# Reduce team 0 so team 1 becomes stronger
	u0.soldiers = 30
	_battle._evaluate_battle_event_signals()

	assert_signal_emitted(_battle, "tide_of_battle_changed")
	assert_signal_emit_count(_battle, "tide_of_battle_changed", 1)

func test_army_half_destroyed_signal():
	watch_signals(_battle)
	var u0 = UnitRef.new()
	u0.team = 0
	u0.max_soldiers = 100
	u0.soldiers = 100
	u0.add_to_group("units")
	_battle.get_node("Units").add_child(u0)
	autofree(u0)

	# Establish initial headcount
	_battle._evaluate_battle_event_signals()

	# Reduce headcount below 50%
	u0.soldiers = 40
	_battle._evaluate_battle_event_signals()

	assert_signal_emitted_with_parameters(_battle, "army_half_destroyed", [0])

func test_army_tired_signal():
	watch_signals(_battle)
	var u0 = UnitRef.new()
	u0.team = 0
	u0.max_soldiers = 100
	u0.soldiers = 100
	u0.fatigue = 60.0
	u0.add_to_group("units")
	_battle.get_node("Units").add_child(u0)
	autofree(u0)

	_battle._evaluate_battle_event_signals()

	assert_signal_emitted_with_parameters(_battle, "army_tired", [0])

func test_general_killed_or_routed_signal():
	watch_signals(_battle)
	var gen = UnitRef.new()
	gen.uid = 99
	gen.team = 0
	gen.is_general = true
	gen.state = UnitRef.State.ROUTING
	gen.add_to_group("routers")
	_battle.get_node("Units").add_child(gen)
	autofree(gen)

	_battle._evaluate_battle_event_signals()

	assert_signal_emitted_with_parameters(_battle, "general_killed_or_routed", [0, gen, "routed"])
