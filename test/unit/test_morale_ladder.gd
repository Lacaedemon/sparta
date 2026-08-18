extends GutTest

const UnitRef = preload("res://scripts/Unit.gd")

func test_morale_ladder_classification():
	assert_eq(UnitMorale.ladder_name(0.0, true), "routing")
	assert_eq(UnitMorale.ladder_name(0.0, false), "routing")
	assert_eq(UnitMorale.ladder_name(15.0, false), "wavering")
	assert_eq(UnitMorale.ladder_name(35.0, false), "shaken")
	assert_eq(UnitMorale.ladder_name(60.0, false), "firm")
	assert_eq(UnitMorale.ladder_name(85.0, false), "high")
	assert_eq(UnitMorale.ladder_name(95.0, false), "impetuous")
	assert_eq(UnitMorale.ladder_name(99.0, false), "berserk")

func test_outnumbered_morale_erosion():
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	SpatialHash.reset()
	var units_node = battle.get_node("Units")
	for u in units_node.get_children():
		units_node.remove_child(u)
		u.free()

	# Friendly unit outnumbered 2:1 by enemy units nearby
	var friendly: Unit = UnitRef.new()
	friendly.team = 0
	friendly.position = Vector2(100, 100)
	friendly.max_soldiers = 100
	units_node.add_child(friendly)
	friendly.soldiers = 50
	friendly.morale = 80.0
	autofree(friendly)

	var enemy: Unit = UnitRef.new()
	enemy.team = 1
	enemy.position = Vector2(120, 100)
	enemy.max_soldiers = 100
	units_node.add_child(enemy)
	enemy.soldiers = 100
	enemy.morale = 80.0
	autofree(enemy)

	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())

	var initial_morale: float = friendly.morale
	UnitMorale.tick_morale(friendly, 1.0)

	assert_true(friendly.morale < initial_morale, "outnumbered unit loses morale over time")

func test_under_fire_morale_erosion():
	var unit: Unit = UnitRef.new()
	autofree(unit)
	unit.team = 0
	unit.morale = 80.0
	unit._under_fire = true

	var initial_morale: float = unit.morale
	UnitMorale.tick_morale(unit, 1.0)

	assert_true(unit.morale < initial_morale, "unit under fire suffers morale erosion")

func test_morale_ladder_name_method_and_snapshot():
	var unit: Unit = UnitRef.new()
	autofree(unit)
	unit.morale = 40.0
	assert_eq(unit.morale_ladder_name(), "shaken")

	var snapshot: Dictionary = unit.to_snapshot_dict()
	assert_eq(snapshot.get("morale_ladder"), "shaken")
