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

func test_ambient_morale_loss_triggers_rout():
	# Distinct from the register_casualties() rout path (see test_unit.gd): this exercises
	# UnitMorale.tick_morale()'s own ambient-erosion trigger, added alongside
	# Unit._rout_clearance() to fix routing-mob pathfinding clearance.
	var unit: Unit = UnitRef.new()
	autofree(unit)
	unit.team = 0
	unit.state = Unit.State.IDLE
	unit.morale = 0.0
	unit._under_fire = true   # blocks the resting-recovery branch so morale stays at 0

	UnitMorale.tick_morale(unit, 1.0)

	assert_eq(unit.state, Unit.State.ROUTING, "zero ambient morale routs the unit")

func test_ambient_morale_loss_rout_does_not_crash_outside_scene_tree():
	# _rout()'s "shake nearby friends" loop used to call get_tree() unconditionally, which
	# is null for a Unit outside the scene tree -- exactly the shape of a bare Unit built
	# by a unit test. tick_morale() is what gave this path a way to fire from outside the
	# tree, since it previously only routed via register_casualties() (called during real
	# combat resolution, always in-tree). A fresh Unit (never added to a tree) at 0 morale
	# must rout without raising.
	var unit: Unit = UnitRef.new()
	autofree(unit)
	assert_false(unit.is_inside_tree(), "sanity: this Unit was never added to a tree")
	unit.team = 0
	unit.morale = 0.0
	unit._under_fire = true

	UnitMorale.tick_morale(unit, 1.0)

	assert_eq(unit.state, Unit.State.ROUTING, "ambient rout still fires outside the tree")

func test_ambient_morale_loss_with_rank_relief_triggers_rout():
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	SpatialHash.reset()
	var units_node: Node = battle.get_node("Units")
	for child: Node in units_node.get_children():
		units_node.remove_child(child)
		child.free()

	var friendly: Unit = UnitRef.new()
	friendly.team = 0
	friendly.position = Vector2(100, 100)
	friendly.max_soldiers = 100
	units_node.add_child(friendly)
	friendly.soldiers = 100
	friendly.morale = 0.0
	friendly.state = Unit.State.FIGHTING
	friendly.is_ranged = false
	friendly.rank_relief = true
	friendly.training = 1.0
	autofree(friendly)

	var enemy: Unit = UnitRef.new()
	enemy.team = 1
	enemy.position = Vector2(120, 100)
	enemy.max_soldiers = 200
	units_node.add_child(enemy)
	enemy.soldiers = 200
	enemy.morale = 80.0
	autofree(enemy)

	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())

	UnitMorale.tick_morale(friendly, 1.0)

	assert_eq(friendly.state, Unit.State.ROUTING, "zero-morale fighting unit with rank relief routs")

func test_morale_recovery_while_fighting_continues_when_not_broken():
	var unit: Unit = UnitRef.new()
	autofree(unit)
	unit.team = 0
	unit.max_soldiers = 100
	unit.soldiers = 100
	unit.morale = 0.5
	unit.state = Unit.State.FIGHTING
	unit.is_ranged = false
	unit.rank_relief = true
	unit.training = 1.0

	UnitMorale.tick_morale(unit, 1.0)

	assert_eq(unit.state, Unit.State.FIGHTING, "fighting unit with positive morale remains fighting")
	assert_gt(unit.morale, 0.5, "fighting unit with positive morale recovers morale via rank cycling")

