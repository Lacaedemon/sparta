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
	# Static rows live in the fold's own label; dynamic rows stay in the main one.
	var text: String = hud._info.text + "\n" + hud._info_static.text
	assert_string_contains(hud._info_static.text,
			"Attack: 12\nDefense: 6\nLorica hamata: protection 45%",
			"attack and defense get their own lines; the armour line is the panoply item")
	assert_string_contains(text, "Lorica hamata: protection 45%, 11 kg",
			"the armor type shows with its protection and weight")
	assert_string_contains(hud._info.text, "HP per man: 90 ±10 of 110",
			"the live hit-point line stays in the always-visible block")
	assert_string_contains(text, "Gladius: reach 1.3 m, lethality 1.00",
			"the weapon type shows with its stats, whole on one line")
	assert_string_contains(text, "Scutum: block 60%, arc 120°",
			"the shield type shows with its stats, whole on one line")
	assert_string_contains(text, "Body mass: 80 kg",
			"the soldier's own mass reports in absolute kilograms")
	assert_string_contains(text, "On foot: 0 kg, pace 0.0 m/s",
			"the mount row shows uniformly even on foot, like the Unshielded row")


func test_stat_sheet_shows_the_cavalry_mount_with_its_stats() -> void:
	var hud := _hud()
	var u := _unit()
	u.is_cavalry = true
	u.armor_type_id = LoadoutRegistry.ARMOR_SQUAMATA
	u.mount_type_id = LoadoutRegistry.MOUNT_WARHORSE
	hud.show_unit(u, 1)
	var text: String = hud._info_static.text
	assert_string_contains(text, "Lorica squamata: protection 40%, 13 kg",
			"the cavalry scale shirt shows with its stats")
	assert_string_contains(text, "Body mass: 75 kg",
			"the rider's own mass reports in absolute kilograms")
	assert_string_contains(text, "Warhorse: 450 kg, pace 8.5 m/s",
			"the warhorse reports its real mass in absolute kilograms, not a sim offset")


func test_characteristics_fold_defaults_collapsed_and_toggles() -> void:
	# The static block is COLLAPSED by default: the toggle row shows (folded
	# glyph), the static label stays hidden, and none of the static rows leak
	# into the always-visible label. Toggling expands and collapses it again,
	# and the state survives a re-show of the same or another unit.
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)
	assert_true(hud._chars_toggle.visible, "the fold toggle appears with a unit shown")
	assert_string_contains(hud._chars_toggle.text, "▸", "collapsed glyph by default")
	assert_false(hud._info_static.visible, "the static block starts folded")
	assert_false(hud._info.text.contains("Attack:"),
			"static rows stay out of the always-visible label")
	hud._on_chars_toggle()
	assert_true(hud._info_static.visible, "toggling expands the static block")
	assert_string_contains(hud._chars_toggle.text, "▾", "expanded glyph while open")
	hud.show_unit(u, 1)
	assert_true(hud._info_static.visible,
			"re-showing a unit keeps the player's expand choice within the battle")
	hud._on_chars_toggle()
	assert_false(hud._info_static.visible, "toggling again folds it back up")


func test_clear_unit_hides_the_fold_entirely() -> void:
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)
	hud._on_chars_toggle()   # expand first, so the hide covers the open state
	hud.clear_unit()
	assert_false(hud._chars_toggle.visible, "no unit -> no toggle row")
	assert_false(hud._info_static.visible, "no unit -> no static block")


func test_info_lines_hold_one_semantic_item_each() -> void:
	# The panel stays NARROW because no line packs two unrelated stats abreast
	# (the old "Morale: 100  Fatigue: 0%" style). Every line is either the unit
	# name header or a single "Label: value" item -- the weapon/shield rows count
	# as one item (an item plus its own attributes). Pin it structurally, across
	# BOTH labels: no line may contain a second "Label:" introduced by the old
	# two-space packing.
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)
	var both: String = hud._info.text + "\n" + hud._info_static.text
	for line in both.split("\n"):
		assert_false(line.contains("  ") and line.split("  ")[1].contains(": "),
				"line packs a second labelled stat after a double space: '%s'" % line)


func test_show_unit_splits_the_header_stats_onto_own_lines() -> void:
	# The pre-stat-sheet block splits the same way: type, commander, morale,
	# fatigue, formation, width, and order each on their own line.
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)
	var text: String = hud._info.text
	assert_string_contains(text, "Type: Infantry\nCommander: ",
			"type and commander sit on adjacent single-item lines")
	assert_string_contains(text, "Morale: 100\nFatigue: 0%",
			"morale and fatigue split onto their own lines")
	assert_string_contains(text, "\nWidth: ", "the width gets its own line")
	assert_string_contains(text, "\nOrder: ", "the order gets its own line")


func test_cohesion_and_training_get_their_own_conditional_lines() -> void:
	# Both lines only appear when meaningful (cohesion below full, any training),
	# and each sits alone on its line like every other stat.
	var hud := _hud()
	var u := _unit()
	u.cohesion = 0.7
	u.training = 0.5
	hud.show_unit(u, 1)
	assert_string_contains(hud._info.text, "\nCohesion: 70%\n",
			"a degraded cohesion shows on its own line")
	assert_string_contains(hud._info.text, "\nTraining: 50%\n",
			"a trained unit's training shows on its own line")
	var fresh := _unit()
	hud.show_unit(fresh, 1)
	assert_false(hud._info.text.contains("Cohesion:"),
			"full cohesion stays hidden, as before the split")


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
