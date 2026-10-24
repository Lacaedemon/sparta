extends GutTest
## A combat re-face absorbed on riders inside a foot block (Unit._face_dir's absorb) keeps the
## drill record (_drill_turn_fold) under it unless it brings the fold within
## melee_reface_drill_record_square_tol of square. While the record stands, the next order's
## re-square deals the drilled quarter in one step by lateral order (_pair_after_quarter_fold);
## once dropped, the fold is squared by a half-turn reflection and a bounded residue turn, as any
## fold is. These tests measure each man against his new slot after the block has squared:
## how many slots lie across a centreline from their man (either axis, each more than half a
## file pitch off it), and the mean walk.

const DT := 1.0 / 60.0


## A seeded 60-man, 8-file, row-major block whose quarter-turn drill has settled with every man
## on his slot, then `drift_deg` more of absorbed combat re-face on top (in steps of 5 degrees,
## as a melee's small re-faces come).
func _drilled_block(drift_deg: float) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	u.seed_sim_soldiers()
	var leaf := Order.new_quarter_turn(1)
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI * 0.5)
	u._settle_order_turn()
	u.set_current_order(null)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]
	var steps: int = int(ceil(absf(drift_deg) / 5.0))
	for _i in range(steps):
		u._face_dir(u.facing.rotated(deg_to_rad(drift_deg / float(steps))), true)
	return u


## Order the block clear of the fight, let any residue turn out, and measure the men (who have
## not moved) against the squared grid.
func _square_and_measure(u: Unit) -> Dictionary:
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	u._in_enemy_contact = false
	u._contact_clear_time = Unit.RESQUARE_CONTACT_CLEAR_TIME
	u.start_order_response()
	var lag_after_order: float = u._grid_lag
	for _i in range(2000):
		u._advance_grid_lag(DT)
	assert_almost_eq(u.grid_fold(), 0.0, 1e-4, "the block ends square to its heading")
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var lb: PackedVector2Array = u.to_slot_frame(bodies)
	var ls: PackedVector2Array = u.to_slot_frame(slots)
	var half: float = u.file_pitch_wu() * 0.5
	var crossed: int = 0
	var total: float = 0.0
	for i in range(bodies.size()):
		total += bodies[i].distance_to(slots[i])
		if lb[i].x * ls[i].x < 0.0 and absf(lb[i].x) > half and absf(ls[i].x) > half:
			crossed += 1
		if lb[i].y * ls[i].y < 0.0 and absf(lb[i].y) > half and absf(ls[i].y) > half:
			crossed += 1
	return {"crossed": crossed, "mean": total / bodies.size(), "lag": lag_after_order}


func _check_kept_record_beats_dropping_it(drift_deg: float) -> void:
	var kept := _drilled_block(drift_deg)
	assert_almost_eq(absf(kept._drill_turn_fold), PI * 0.5, 1e-6, "the drill record is kept")
	var dropped := _drilled_block(drift_deg)
	dropped._drill_turn_fold = 0.0
	var k := _square_and_measure(kept)
	var d := _square_and_measure(dropped)
	assert_eq(float(k["lag"]), 0.0, "the kept record is dealt in one step")
	assert_ne(float(d["lag"]), 0.0, "sanity: the dropped record turns a residue out")
	assert_lt(int(k["crossed"]), 3, "few men's slots cross the block")
	assert_lt(float(k["mean"]), kept.file_pitch_wu(), "the average man walks under a file pitch")
	assert_lt(int(k["crossed"]), int(d["crossed"]), "fewer crossings than wheeling the grid round")
	assert_lt(float(k["mean"]), float(d["mean"]), "and a shorter mean walk")


func test_a_drilled_quarter_with_a_small_absorbed_drift_is_dealt_in_one_step() -> void:
	# Measured: kept 2 crossings, 14.7 wu; dropped 36, 57.9 wu.
	_check_kept_record_beats_dropping_it(25.0)


func test_a_drilled_quarter_with_a_large_absorbed_drift_is_still_dealt_in_one_step() -> void:
	# A fold 160 degrees off: measured kept 1 crossing, 16.0 wu; dropped 8, 24.7 wu.
	_check_kept_record_beats_dropping_it(70.0)


func test_a_drift_back_to_near_square_drops_the_record() -> void:
	# A fold drifted back to 10 degrees off square is squared by the bounded residue turn, which
	# walks the men 9.2 wu on average against 10.2 for the one-step re-deal.
	var u := _drilled_block(-80.0)
	assert_eq(u._drill_turn_fold, 0.0, "within the tolerance of square the record is dropped")
	var m := _square_and_measure(u)
	assert_almost_eq(rad_to_deg(float(m["lag"])), -10.0, 0.01, "the order turns the residue out")
	assert_eq(int(m["crossed"]), 0, "no man's slot crosses the block")
	assert_lt(float(m["mean"]), 10.0, "and the average man walks under 10 wu")


func test_a_zero_tolerance_keeps_the_record_at_any_fold() -> void:
	var u: Unit = Unit.new()
	add_child_autofree(u)
	assert_eq(u.melee_reface_drill_record_square_tol, Unit.MELEE_REFACE_DRILL_RECORD_SQUARE_TOL,
		"a new unit runs on the default")
	u.melee_reface_drill_record_square_tol = 0.0
	u.facing = Vector2.DOWN
	u._formation_angle = deg_to_rad(5.0)
	u._drill_turn_fold = PI * 0.5
	u._face_dir(Vector2.DOWN.rotated(deg_to_rad(5.0)), true)
	assert_almost_eq(u._formation_angle, 0.0, 1e-6, "sanity: the fold lands square")
	assert_eq(u._drill_turn_fold, PI * 0.5, "a tolerance of 0 never drops the record")
