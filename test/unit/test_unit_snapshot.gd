extends GutTest
## Unit.to_snapshot_dict()/apply_snapshot_dict(): the per-unit round-trip
## Battle.capture_snapshot()/restore_snapshot() relies on. Pure field copies -- no tree
## needed, so these run against bare Unit.new() instances like test_order.gd's pure style.


func _sample_unit() -> Unit:
	var u := Unit.new()
	u.uid = 7
	u.unit_name = "Spearmen 1"
	u.team = 1
	u.anti_cavalry = true
	u.is_cavalry = false
	u.is_ranged = false
	u.max_soldiers = 140
	u.attack = 11
	u.defense = 8
	u.move_speed = 200.0
	u.walk_speed = 50.0
	u.jog_speed = 90.0
	u.back_speed_fraction = 0.35
	u.accel = 20.0
	u.decel = 45.0
	u.attack_range = 60.0
	u.weapon_type_id = LoadoutRegistry.WEAPON_SPEAR
	u.shield_type_id = LoadoutRegistry.SHIELD_SCUTUM
	u.armor_type_id = LoadoutRegistry.ARMOR_TUNIC       # non-default, so the round-trip is provable
	u.mount_type_id = LoadoutRegistry.MOUNT_WARHORSE    # non-default, so the round-trip is provable
	u.order_response_delay = 0.5
	u.atomic_response_delay = 0.35
	u.training = 0.75
	u.disciplined = true
	u.field_bounds = Rect2(0, 0, 1600, 1000)
	u.retreat_bounds = Rect2(-50, -50, 1700, 1100)
	u.separation_radius = 12.0
	u._base_separation_radius = 18.0
	u.spacing_scale = 1.0
	u.team_color = Color(0.83, 0.35, 0.29)

	u.soldiers = 88
	u.morale = 42.5
	u.fatigue = 12.0
	u.cohesion = 0.6
	u.state = Unit.State.FIGHTING
	u.facing = Vector2(0, -1)
	u.position = Vector2(640, 380)
	u.move_target = Vector2(700, 300)
	u.has_move_target = true
	u.order_mode = 3
	u.knockback_push_indefinite = true
	u.formation_mode = Unit.FORMATION_SQUARE
	u.rank_relief = false
	u.engage_reshape_mode = Unit.EngageReshapeMode.RECREATE_WIDTH
	u.tier = FormationTier.FAR
	u.frontage_override = 6
	u.frontage_anchor_offset = 3.5
	u._last_reshape_tick = 42
	u._last_reshape_widened = true
	u._ranks_closed = true
	u._formation_angle = 1.2
	u._formation_mirror_x = true
	u.deploy_facing = Vector2(1, 0)
	u.ordered_facing = Vector2(0, 1)
	u.walk_advance = true
	u.reform_before_move = false   # non-default (the field defaults true), so the round-trip is provable
	u.file_major_reform = false    # non-default (the field defaults true), so the round-trip is provable
	u._under_fire = true
	u._attack_cd = 0.2
	u._pin_down_exposure_cd = 0.1
	u._rout_timer = 3.0
	u._shattered = true
	u._order_response_timer = 0.4
	u._engaged_linger = 0.35
	u._moved_last_frame = true
	u._approach_velocity = Vector2(5, -5)
	u._current_speed = 44.0
	u._body_follow_vel = Vector2(1, 1)
	u._cycle_recharging = true
	u._combat_intermixing = 0.3
	u._per_soldier_facing = true
	u._engage_turn_target = Vector2(1, 0)
	u._engage_turn_start_facing = Vector2(0, -1)
	u._engage_turn_old_files = 9
	u._reform_on_arrival = true

	u._sim_soldier_pos = PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
	u._sim_body_vel = PackedVector2Array([Vector2(0.1, 0.2)])
	u._sim_steer = PackedVector2Array([Vector2(0.5, 0.5)])
	u._sim_soldier_hp = PackedFloat32Array([90.0, 75.0])
	u._sim_soldier_weapon_id = PackedInt32Array([LoadoutRegistry.WEAPON_SPEAR])
	u._sim_soldier_shield_id = PackedInt32Array([LoadoutRegistry.SHIELD_SCUTUM])
	u._sim_soldier_shield_hold_angle = PackedFloat32Array([0.3])
	u._sim_prone = PackedFloat32Array([0.0, 1.5])
	u._sim_soldier_stamina = PackedFloat32Array([80.0, 60.0])
	u._sim_soldier_facing = PackedVector2Array([Vector2(0, -1), Vector2(0, -1)])
	u._sim_soldier_file = PackedInt32Array([0, 1])
	u._file_assignment_files = 2   # non-default (the field defaults -1), so the round-trip is provable

	var move := Order.new_move(Vector2(700, 300))
	move.phase = Order.Phase.MARCH
	u.orders = [move]
	u.current_order = move
	return u


func test_to_snapshot_dict_round_trips_every_captured_field() -> void:
	var original := _sample_unit()
	var d := original.to_snapshot_dict()

	var restored := Unit.new()
	restored.apply_snapshot_dict(d)

	assert_eq(restored.uid, original.uid)
	assert_eq(restored.unit_name, original.unit_name)
	assert_eq(restored.team, original.team)
	assert_eq(restored.max_soldiers, original.max_soldiers)
	assert_eq(restored.attack_range, original.attack_range)
	assert_eq(restored.weapon_type_id, original.weapon_type_id)
	assert_eq(restored.armor_type_id, original.armor_type_id)
	assert_eq(restored.mount_type_id, original.mount_type_id)
	assert_almost_eq(restored.order_response_delay, original.order_response_delay, 0.001)
	assert_almost_eq(restored.atomic_response_delay, original.atomic_response_delay, 0.001,
		"a spawn-customized drill beat survives a replay-seek snapshot restore")
	assert_eq(restored.disciplined, original.disciplined)
	assert_eq(restored.field_bounds, original.field_bounds)
	assert_eq(restored.retreat_bounds, original.retreat_bounds)
	assert_eq(restored.team_color, original.team_color)

	assert_eq(restored.soldiers, original.soldiers)
	assert_almost_eq(restored.morale, original.morale, 0.001)
	assert_eq(restored.state, original.state)
	assert_eq(restored.facing, original.facing)
	assert_eq(restored.position, original.position)
	assert_eq(restored.has_move_target, original.has_move_target)
	assert_eq(restored.order_mode, original.order_mode)
	assert_eq(restored.formation_mode, original.formation_mode)
	assert_eq(restored.walk_advance, original.walk_advance)
	assert_eq(restored.reform_before_move, original.reform_before_move)
	assert_eq(restored.file_major_reform, original.file_major_reform)
	assert_eq(restored._file_assignment_files, original._file_assignment_files)
	assert_eq(restored.frontage_override, original.frontage_override)
	assert_eq(restored._formation_angle, original._formation_angle)
	assert_eq(restored._shattered, original._shattered)
	assert_eq(restored._rout_timer, original._rout_timer)
	assert_eq(restored._engaged_linger, original._engaged_linger,
		"the engaged afterglow window survives a restore -- is_engaged() must not flip")
	assert_eq(restored._approach_velocity, original._approach_velocity)
	assert_eq(restored.current_speed, original.current_speed)
	assert_eq(restored._engage_turn_target, original._engage_turn_target)
	assert_eq(restored._engage_turn_old_files, original._engage_turn_old_files)

	assert_eq(Array(restored._sim_soldier_pos), Array(original._sim_soldier_pos))
	assert_eq(Array(restored._sim_soldier_hp), Array(original._sim_soldier_hp))
	assert_eq(Array(restored._sim_prone), Array(original._sim_prone))
	assert_eq(Array(restored._sim_soldier_stamina), Array(original._sim_soldier_stamina))
	assert_eq(Array(restored._sim_soldier_facing), Array(original._sim_soldier_facing))
	assert_eq(Array(restored._sim_soldier_weapon_id), Array(original._sim_soldier_weapon_id))
	assert_eq(Array(restored._sim_soldier_file), Array(original._sim_soldier_file))

	assert_eq(restored.orders.size(), 1)
	assert_eq(restored.orders[0].type, Order.Type.MOVE)
	assert_eq(restored.orders[0].phase, Order.Phase.MARCH)
	assert_eq(restored.orders[0].target_pos, Vector2(700, 300))
	assert_eq(restored.current_order, restored.orders[0],
			"current_order is re-derived as orders[0], not double-serialized")


func test_snapshot_dict_carries_target_references_as_bare_uids_not_live_refs() -> void:
	var attacker := _sample_unit()
	var enemy := Unit.new()
	enemy.uid = 99
	attacker.target_enemy = enemy
	attacker.support_target = enemy
	attacker._engage_turn_enemy = enemy

	var d := attacker.to_snapshot_dict()

	assert_eq(int(d["target_enemy_uid"]), 99)
	assert_eq(int(d["support_target_uid"]), 99)
	assert_eq(int(d["engage_turn_enemy_uid"]), 99)

	# apply_snapshot_dict alone never resolves these -- that's the caller's (Battle's)
	# second-pass job, once every unit in the snapshot exists. A freshly restored unit
	# has no live target until that pass runs.
	var restored := Unit.new()
	restored.apply_snapshot_dict(d)
	assert_null(restored.target_enemy)
	assert_null(restored.support_target)
	assert_null(restored._engage_turn_enemy)


func test_a_unit_with_no_targets_or_orders_reports_sentinel_uids_and_an_empty_queue() -> void:
	var u := Unit.new()
	u.uid = 1
	var d := u.to_snapshot_dict()
	assert_eq(int(d["target_enemy_uid"]), -1)
	assert_eq(int(d["support_target_uid"]), -1)
	assert_eq(int(d["engage_turn_enemy_uid"]), -1)
	assert_eq((d["orders"] as Array).size(), 0)


func test_mutating_the_original_units_arrays_after_capture_does_not_alter_the_snapshot() -> void:
	# to_snapshot_dict() must duplicate() its packed arrays -- otherwise a later live tick
	# that resizes/rewrites the unit's own _sim_soldier_pos would silently corrupt an
	# already-cached snapshot (see ReplaySnapshotCache, which can hold this dict for many
	# ticks before a rewind ever reads it back).
	var u := _sample_unit()
	var d := u.to_snapshot_dict()
	u._sim_soldier_pos[0] = Vector2(999, 999)
	assert_eq((d["sim_soldier_pos"] as PackedVector2Array)[0], Vector2(1, 2),
			"the cached snapshot's array is an independent copy")
