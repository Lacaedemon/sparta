extends GutTest
## The info panel's full stat sheet: show_unit() must surface every unit-level
## characteristic -- attack/defense/armour, per-soldier hit points, ordered gait,
## live mean speed and its acceleration, and the weapon/shield types with stats.

const HUDScript = preload("res://scripts/HUD.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func _hud() -> CanvasLayer:
	var h = HUDScript.new()
	add_child_autofree(h)
	return h


func _unit(uid: int = 1) -> Unit:
	var u: Unit = UnitScript.new()
	u.uid = uid
	u.max_soldiers = 10
	add_child_autofree(u)
	return u


func test_stat_sheet_reports_combat_stats_and_loadout() -> void:
	var hud := _hud()
	var u := _unit()
	u.attack = 12
	u.defense = 6
	u._sim_soldier_hp = PackedFloat32Array([100.0, 80.0])
	hud.show_unit(u, 1)
	var text: String = hud._info.text
	assert_string_contains(text, "Attack: 12  Defense: 6",
			"the attack/defense stats show")
	assert_string_contains(text, "Armour: 45%",
			"the infantry profile's armour scalar shows as a percentage")
	assert_string_contains(text, "HP per man: 90 ±10 of 110",
			"mean, spread, and the type's full-health value all show")
	assert_string_contains(text, "Gladius: reach 1.3 m, lethality 1.00",
			"the weapon type shows with its stats")
	assert_string_contains(text, "Scutum: block 60%, arc 120°",
			"the shield type shows with its stats")


func test_stat_sheet_reads_auto_gait_without_a_move_order() -> void:
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)
	assert_string_contains(hud._info.text, "Gait: Auto",
			"no explicit gait on order -> the unit paces itself")


func test_stat_sheet_names_an_ordered_gait_with_this_units_own_pace() -> void:
	var hud := _hud()
	var u := _unit()
	u.current_order = Order.new_move(Vector2(100, 100), 0, Unit.GAIT_JOG)
	hud.show_unit(u, 1)
	# jog_speed defaults to 67.5 wu/s = 3.375 m/s at 20 wu/m, rendered "3.4 m/s".
	assert_string_contains(hud._info.text, "Gait: Jog (3.4 m/s)",
			"the ordered gait names itself with this unit's own pace for it")


func test_stat_sheet_shows_the_living_mean_speed() -> void:
	var hud := _hud()
	var u := _unit()
	# One living soldier at 40 wu/s = 2.0 m/s; the fallen one's velocity must not count.
	u._sim_body_vel = PackedVector2Array([Vector2(40, 0), Vector2(500, 0)])
	u._sim_soldier_hp = PackedFloat32Array([100.0, 0.0])
	hud.show_unit(u, 1)
	assert_string_contains(hud._info.text, "Speed: 2.0 m/s",
			"mean speed averages the living bodies only")


func test_track_accel_derives_the_mean_speed_change_per_second() -> void:
	var hud := _hud()
	var u := _unit()
	var before: int = Engine.get_physics_frames()
	hud._track_accel(u, 2.0)
	assert_eq(hud._accel_mps2, 0.0, "the first sample of a unit seeds at zero")
	await get_tree().physics_frame
	var elapsed: int = Engine.get_physics_frames() - before
	hud._track_accel(u, 2.5)
	var dt: float = float(elapsed) / float(Replay.PHYSICS_TPS)
	assert_almost_eq(hud._accel_mps2, 0.5 / dt, 0.001,
			"the derivative reads the speed change over the elapsed sim time")


func test_track_accel_reseeds_when_the_shown_unit_changes() -> void:
	var hud := _hud()
	var a := _unit(1)
	var b := _unit(2)
	hud._track_accel(a, 2.0)
	await get_tree().physics_frame
	hud._track_accel(b, 9.0)
	assert_eq(hud._accel_mps2, 0.0,
			"a different unit reseeds instead of differencing across regiments")


func test_track_accel_holds_its_value_within_one_tick() -> void:
	var hud := _hud()
	var u := _unit()
	hud._track_accel(u, 2.0)
	hud._track_accel(u, 99.0)
	assert_eq(hud._accel_mps2, 0.0,
			"a same-tick repeat call keeps the last derivative instead of dividing by zero")
