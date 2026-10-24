extends GutTest
## A combat re-face absorbed on riders inside a foot block (Unit._face_dir's absorb) keeps a
## quarter drill record (_drill_turn_fold) under it unless it brings the fold within
## melee_reface_drill_record_square_tol of square. While the record stands, the next order's
## re-square deals the men onto the squared grid in one step by lateral file order
## (_pair_after_quarter_fold); once dropped, the fold is turned out at a bounded rate as any
## fold is. Each case is measured on both reform layouts, kept record against dropped, as the
## mean walk from each man (who has not moved) to his slot once the block is square.

const DT := 1.0 / 60.0
const LAYOUTS := [Unit.ReformMode.ROW_MAJOR, Unit.ReformMode.FILE_MAJOR]


## A seeded 60-man, 8-file block in `layout` whose quarter-turn drill has settled with every
## man on his slot (a -90 degree fold), then absorbed combat re-faces in 5-degree steps turning
## the fold back until it stands `off_deg` degrees off square.
func _drilled_block(layout: int, off_deg: float) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.file_major_reform_mode = layout
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
	var drift: float = -(90.0 - off_deg)   # an absorbed turn of t moves the fold by -t
	var steps: int = int(ceil(absf(drift) / 5.0))
	for _i in range(steps):
		u._face_dir(u.facing.rotated(deg_to_rad(drift / float(steps))), true)
	return u


## Order the block clear of the fight, let any residue turn out, and return the mean walk.
func _square_and_walk(u: Unit) -> float:
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	u._in_enemy_contact = false
	u._contact_clear_time = Unit.RESQUARE_CONTACT_CLEAR_TIME
	u.start_order_response()
	for _i in range(2000):
		u._advance_grid_lag(DT)
	assert_almost_eq(u.grid_fold(), 0.0, 1e-4, "the block ends square to its heading")
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var total: float = 0.0
	for i in range(bodies.size()):
		total += bodies[i].distance_to(slots[i])
	return total / bodies.size()


## Mean walks [kept, dropped] for a drilled block `off_deg` off square in `layout`. The kept
## side forces the record back on and the dropped side clears it, so both paths are measured
## whatever the gate decided.
func _both_paths(layout: int, off_deg: float) -> Array:
	var kept := _drilled_block(layout, off_deg)
	kept._drill_turn_fold = -PI * 0.5
	var dropped := _drilled_block(layout, off_deg)
	dropped._drill_turn_fold = 0.0
	return [_square_and_walk(kept), _square_and_walk(dropped)]


func _fold_off_square_deg(u: Unit) -> float:
	return rad_to_deg(absf(wrapf(u._formation_angle, -PI, PI)))


func test_the_default_tolerance_is_nine_degrees() -> void:
	assert_almost_eq(rad_to_deg(Unit.MELEE_REFACE_DRILL_RECORD_SQUARE_TOL), 9.0, 1e-4,
		"the default sits in the measured crossover between 8 and 10 degrees")


func test_far_from_square_the_record_is_kept_and_walks_less() -> void:
	# Folds 65 and 20 degrees off square.
	for layout in LAYOUTS:
		for off in [65.0, 20.0]:
			var u := _drilled_block(layout, off)
			assert_almost_eq(_fold_off_square_deg(u), off, 0.01, "sanity: the fold is where asked")
			assert_almost_eq(absf(u._drill_turn_fold), PI * 0.5, 1e-6, "the record is kept")
			var w: Array = _both_paths(layout, off)
			assert_lt(float(w[0]), float(w[1]),
				"layout %d, %d degrees off: the one-step deal walks less" % [layout, int(off)])


func test_in_the_band_above_the_tolerance_the_record_is_kept() -> void:
	# 15 degrees off square: measured kept 13.2 against 13.8 (row major), 10.6 against 13.8
	# (file major).
	for layout in LAYOUTS:
		var u := _drilled_block(layout, 15.0)
		assert_almost_eq(absf(u._drill_turn_fold), PI * 0.5, 1e-6, "the record is kept at 15 degrees")
		var w: Array = _both_paths(layout, 15.0)
		assert_lt(float(w[0]), float(w[1]), "layout %d: keeping walks less at 15 degrees" % layout)


func test_near_square_the_record_is_dropped_and_dropping_walks_no_further() -> void:
	# 5 degrees off square: measured dropped 4.6 against kept 11.8 (row major), and the two
	# paths equal at 4.6 (file major).
	for layout in LAYOUTS:
		var u := _drilled_block(layout, 5.0)
		assert_eq(u._drill_turn_fold, 0.0, "within the tolerance of square the record is dropped")
		var w: Array = _both_paths(layout, 5.0)
		assert_true(float(w[1]) <= float(w[0]) + 1e-3,
			"layout %d: dropping walks no further than keeping (%.2f vs %.2f)" % [layout, w[1], w[0]])
		if layout == Unit.ReformMode.ROW_MAJOR:
			assert_lt(float(w[1]), float(w[0]) * 0.5, "row major: dropping walks under half as far")


func test_an_about_face_record_is_cleared_by_an_absorb() -> void:
	var u: Unit = Unit.new()
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u._formation_angle = PI
	u._drill_turn_fold = PI
	u._face_dir(Vector2.DOWN.rotated(deg_to_rad(10.0)), true)
	assert_eq(u._drill_turn_fold, 0.0, "only a quarter record is kept under an absorb")


func test_a_zero_tolerance_keeps_a_quarter_record_at_any_fold() -> void:
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
