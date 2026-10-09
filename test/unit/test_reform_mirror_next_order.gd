extends GutTest
## What happens to an about-faced block's men AFTER its re-square, when the next order arrives.
##
## A re-square of an about-face fold reflects the grid in depth (Unit._formation_mirror_x), and
## the hold-ground variant cancels that reflection on the soldier-to-slot assignment so the men
## re-square where they stand. Once the re-squaring order has run, a fresh order must not move a
## single man: the block is already square, so nothing about the new order re-slots it. In
## particular no man may be carried across the block's centreline to the opposite flank.
##
## The existing re-square tests (test_reform_ranks.gd, test_reform_battle.gd) only measure the
## first order after the about-face. These measure the order after that one, for every layout the
## hold-ground cancellation has (file major, row major, square), for a countermarch, for a full
## grid whose drilled half-turn is forced to hold its ground, and for a second about-face.
## The live-battle version, through the real order pipeline, is the last test in this file.

const TICK: float = 1.0 / 60.0
const SPEARMEN_COUNT := 40          # 9 files -> 4 full ranks + a 4-man partial rank
const SPAWN := Vector2(500, 430)

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## 60 men at 8 files = 7 full ranks + a 4-man partial rank, file-major reform (the default).
func _make_partial_file_major() -> Unit:
	return _make_unit(60, Unit.ReformMode.FILE_MAJOR)


## The same 60/8 partial grid on the row-major branch.
func _make_partial_row_major() -> Unit:
	return _make_unit(60, Unit.ReformMode.ROW_MAJOR)


## A FULL grid: 24 men at 8 files = exactly 3 ranks.
func _make_full() -> Unit:
	return _make_unit(24, Unit.ReformMode.FILE_MAJOR)


## A squared 60-man block: square_files(60) is 8, so 7 full ranks of 8 plus a 4-man rear rank.
func _make_square() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.set_formation(Unit.FORMATION_SQUARE)
	return u


func _make_unit(count: int, mode: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = 8
	u.file_major_reform_mode = mode
	u.seed_sim_soldiers()
	return u


## Every body onto its slot: the block has formed.
func _stand_on_slots(u: Unit) -> void:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


## Settle an about-face drill the way a completed ABOUT_FACE leaf does (facing reversed, the
## half-turn folded into the grid by _settle_order_turn), with every body on its slot.
func _settle_about_face(u: Unit) -> void:
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)


## About-face `u`, re-square it (reform_ranks must start a reform), and let the re-square run:
## every body ends on its new slot.
func _about_face_and_resquare(u: Unit, hold_ground: bool) -> void:
	_settle_about_face(u)
	assert_true(u.reform_ranks(hold_ground), "precondition: the about-face fold re-squares")
	_stand_on_slots(u)


## How far each man's slot moves from where he stands, and how many men's slot lies across the
## block's lateral centreline from them (both more than half a file pitch off it). `lateral`
## is a FIXED world axis, so a heading change cannot read as a flank change.
func _travel(u: Unit, bodies: PackedVector2Array, lateral: Vector2) -> Dictionary:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var half: float = u.file_pitch_wu() * 0.5
	var crossed: int = 0
	var farthest: float = 0.0
	for i in range(bodies.size()):
		farthest = maxf(farthest, bodies[i].distance_to(slots[i]))
		var a: float = (bodies[i] - u.position).dot(lateral)
		var b: float = (slots[i] - u.position).dot(lateral)
		if a * b < 0.0 and absf(a) > half and absf(b) > half:
			crossed += 1
	return {"crossed": crossed, "farthest": farthest}


## A fresh move straight ahead: no turn, so nothing in the order itself re-slots the block.
func _issue_move_ahead(u: Unit) -> void:
	u.set_current_order(Order.new_move(u.position + u.facing * 200.0))


## The core check: after the re-square has run, the next order leaves every man's slot where he
## stands -- no crossing and no walk at all.
func _assert_next_order_moves_nobody(u: Unit, what: String) -> void:
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	var off_centre: int = 0
	for i in range(bodies.size()):
		if absf((bodies[i] - u.position).dot(lateral)) > u.file_pitch_wu() * 0.5:
			off_centre += 1
	assert_gt(off_centre, 0, "%s: precondition: the block has off-centre men" % what)
	_issue_move_ahead(u)
	var t: Dictionary = _travel(u, bodies, lateral)
	assert_eq(int(t["crossed"]), 0,
		"%s: no man's slot changes flank on the next order (%d of %d off-centre men cross)"
		% [what, int(t["crossed"]), off_centre])
	assert_lt(float(t["farthest"]), 0.01,
		"%s: no man's slot moves on the next order (farthest %.2f wu)"
		% [what, float(t["farthest"])])


func test_a_partial_file_major_hold_ground_re_square_survives_the_next_order() -> void:
	var u := _make_partial_file_major()
	assert_true(u._effective_file_major_reform(), "precondition: file major")
	_about_face_and_resquare(u, true)
	_assert_next_order_moves_nobody(u, "file major, hold ground")


func test_a_partial_row_major_hold_ground_re_square_survives_the_next_order() -> void:
	var u := _make_partial_row_major()
	assert_false(u._effective_file_major_reform(), "precondition: row major")
	_about_face_and_resquare(u, true)
	_assert_next_order_moves_nobody(u, "row major, hold ground")


func test_a_partial_square_hold_ground_re_square_survives_the_next_order() -> void:
	var u := _make_square()
	assert_true(u.in_square(), "precondition: squared")
	_about_face_and_resquare(u, true)
	_assert_next_order_moves_nobody(u, "square, hold ground")


## A countermarch (no hold-ground cancellation): the ranks trade ends, and once they have, the
## next order must leave them there just the same.
func test_a_partial_countermarch_survives_the_next_order() -> void:
	for make in [_make_partial_file_major, _make_partial_row_major]:
		var u: Unit = make.call()
		var layout: String = "file major" if u._effective_file_major_reform() else "row major"
		_about_face_and_resquare(u, false)
		_assert_next_order_moves_nobody(u, "%s, countermarch" % layout)


## A full grid on a snap-absorb residue: its drilled half-turn is forced to hold its ground and
## is reflected, so it carries the same reflection as a partial grid's exact about-face.
func test_a_full_grid_drilled_half_turn_re_square_survives_the_next_order() -> void:
	for hold_ground in [true, false]:
		var u := _make_full()
		u._formation_angle = deg_to_rad(-25.0)
		_settle_about_face(u)
		assert_true(u.reform_ranks(hold_ground), "precondition: the residue re-squares")
		assert_true(u._formation_mirror_x, "precondition: reflected, not swung")
		_stand_on_slots(u)
		_assert_next_order_moves_nobody(u, "full grid on a residue, hold_ground %s" % hold_ground)


## A rally re-squares a fold the flight left behind through reform_ranks(true). The first order
## after the rally must leave the men where the rally formed them.
func test_a_rallied_about_face_fold_survives_the_next_order() -> void:
	var u := _make_partial_file_major()
	u.facing = Vector2.UP
	u._formation_angle = PI   # the snap-absorb fold of a flight's about-face
	_stand_on_slots(u)
	assert_true(u.reform_ranks(true), "precondition: the rally's fold re-squares")
	_stand_on_slots(u)
	_assert_next_order_moves_nobody(u, "rallied fold")


## A second about-face after the first re-square and a fresh order: the second re-square is
## another depth-only reflection, so each man still ends on the flank he held before it.
func test_a_second_about_face_re_square_keeps_every_man_on_his_flank() -> void:
	for make in [_make_partial_file_major, _make_partial_row_major, _make_square]:
		var u: Unit = make.call()
		var layout: String = "square" if u.in_square() \
				else ("file major" if u._effective_file_major_reform() else "row major")
		_about_face_and_resquare(u, true)
		_issue_move_ahead(u)
		_stand_on_slots(u)
		var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
		var lateral: Vector2 = u.facing.orthogonal()
		_settle_about_face(u)
		assert_true(u.reform_ranks(true), "precondition: the second about-face re-squares (%s)" % layout)
		var t: Dictionary = _travel(u, bodies, lateral)
		assert_eq(int(t["crossed"]), 0,
			"%s: the second re-square sends no man across the block (%d cross)"
			% [layout, int(t["crossed"])])


## A standing frontage anchor shift is added in the same local frame the mirror reflects, so the
## next order must carry it across with the men rather than throw the block sideways by twice it.
func test_an_anchored_block_survives_the_next_order() -> void:
	for make in [_make_partial_file_major, _make_partial_row_major]:
		var u: Unit = make.call()
		var layout: String = "file major" if u._effective_file_major_reform() else "row major"
		u.frontage_anchor_offset = u.file_pitch_wu() * 2.0
		_stand_on_slots(u)
		_about_face_and_resquare(u, true)
		_assert_next_order_moves_nobody(u, "%s, anchored" % layout)
		assert_almost_eq(u.frontage_anchor_offset, -u.file_pitch_wu() * 2.0, 0.001,
			"%s: the anchor shift is carried into the unmirrored frame" % layout)


## Fold the block by `turn` the way a snap-absorb or a settled drill does, holding every slot
## where it is (facing turns, the fold takes the turn back), with no fresh order in between.
func _fold_in_place(u: Unit, turn: float) -> void:
	u.facing = u.facing.rotated(turn)
	u._formation_angle = wrapf(u._formation_angle - turn, -PI, PI)


## A second about-face re-square inside the SAME order (a queued leg, with no fresh order to
## bake the first mirror): the second depth-only reflection must keep each man on his flank.
func test_a_second_about_face_inside_one_order_keeps_every_man_on_his_flank() -> void:
	for make in [_make_partial_file_major, _make_partial_row_major, _make_square]:
		var u: Unit = make.call()
		var layout: String = "square" if u.in_square() \
				else ("file major" if u._effective_file_major_reform() else "row major")
		_about_face_and_resquare(u, true)
		assert_true(u._formation_mirror_x, "precondition: the first re-square is mirrored (%s)" % layout)
		var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
		var lateral: Vector2 = u.facing.orthogonal()
		_fold_in_place(u, PI)
		assert_true(u.reform_ranks(true), "precondition: the second fold re-squares (%s)" % layout)
		assert_false(u._formation_mirror_x, "the second reflection takes the mirror off (%s)" % layout)
		var t: Dictionary = _travel(u, bodies, lateral)
		assert_eq(int(t["crossed"]), 0,
			"%s: the second re-square sends no man across the block (%d cross)"
			% [layout, int(t["crossed"])])


## A plain residue drop inside the same order as an about-face re-square (a snap-absorb fold
## squared before any fresh order): the drop is a rotation, so it must leave the mirror armed.
## A full grid, whose slots are symmetric in depth as well as laterally, so the mirrored block
## and a never-mirrored one stand on the same ground and the residue moves them identically.
func test_a_residue_drop_under_a_standing_mirror_keeps_it() -> void:
	var u := _make_full()
	u._formation_angle = deg_to_rad(-25.0)
	_settle_about_face(u)
	assert_true(u.reform_ranks(true), "precondition: the drilled half-turn re-squares")
	_stand_on_slots(u)
	assert_true(u._formation_mirror_x, "precondition: mirrored")
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	_fold_in_place(u, deg_to_rad(25.0))
	assert_true(u.reform_ranks(true), "precondition: the residue re-squares")
	assert_true(u._formation_mirror_x, "a plain drop leaves the mirror armed")
	var t: Dictionary = _travel(u, bodies, lateral)
	# The yardstick: the same residue squared on a block that was never mirrored.
	var plain := _make_full()
	var plain_bodies: PackedVector2Array = plain._sim_soldier_pos.duplicate()
	_fold_in_place(plain, deg_to_rad(25.0))
	assert_true(plain.reform_ranks(true), "precondition: the yardstick re-squares")
	var yardstick: Dictionary = _travel(plain, plain_bodies, plain.facing.orthogonal())
	assert_eq(int(t["crossed"]), int(yardstick["crossed"]),
		"no more men cross than squaring the residue alone sends across (%d against %d)"
		% [int(t["crossed"]), int(yardstick["crossed"])])
	assert_almost_eq(float(t["farthest"]), float(yardstick["farthest"]), 0.01,
		"the farthest man walks exactly the residue's turn")


## The pure pairing the bake composes: each cell pairs with the cell at the same depth on the
## other side of the centreline, short rear rank included, and the pairing is an involution.
func test_lateral_reflection_pairing_reflects_every_cell() -> void:
	for shape in [[60, 8], [40, 9], [24, 8], [7, 3], [5, 8], [1, 1]]:
		var n: int = shape[0]
		var files: int = shape[1]
		var slots: PackedVector2Array = UnitFormation.block_slots(n, files, 10.0, 12.0)
		var pairing: PackedInt32Array = UnitFormation.lateral_reflection_pairing(n, files)
		assert_eq(pairing.size(), n, "one partner per cell (%d/%d)" % [n, files])
		for c in range(n):
			var p: int = pairing[c]
			assert_almost_eq(slots[p].x, -slots[c].x, 0.001, "cell %d mirrors laterally (%d/%d)" % [c, n, files])
			assert_almost_eq(slots[p].y, slots[c].y, 0.001, "cell %d keeps its depth (%d/%d)" % [c, n, files])
			assert_eq(pairing[p], c, "the pairing is an involution at cell %d (%d/%d)" % [c, n, files])
	assert_eq(UnitFormation.lateral_reflection_pairing(0, 8).size(), 0, "no cells, no pairing")
	assert_eq(UnitFormation.lateral_reflection_pairing(8, 0).size(), 0, "no files, no pairing")


## Lateral offset of every body from the unit centre, on a FIXED world axis.
func _laterals(u: Unit, axis: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in u._sim_soldier_pos:
		out.push_back((p - u.position).dot(axis))
	return out


## The full-scene version, through the real order pipeline: a drilled rear move about-faces a
## depleted spearmen block, re-squares it holding ground, and marches it to its destination.
## A second move order straight ahead must then march the block off with every man on the
## flank he held, rather than walking each off-centre man across the block.
func test_live_second_order_after_an_about_face_keeps_every_man_on_his_flank() -> void:
	Replay.forced_seed = 24680
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Spearmen", "x": SPAWN.x, "y": SPAWN.y,
			"count": SPEARMEN_COUNT, "facing": [0, 1], "frontage_override": 9},
	]
	add_child(_battle)
	var u: Unit = null
	for n in get_tree().get_nodes_in_group("units"):
		if n is Unit and n.team == 0:
			u = n
	assert_not_null(u, "the scenario staged the spearmen")
	if u == null:
		return
	for _k in range(40):
		await get_tree().physics_frame
	u.reform_before_move = true
	var dest := SPAWN + Vector2(0, -120)   # behind the DOWN-facing block: an about-face
	_battle._apply_order_cmd({"units": [u.uid], "x": dest.x, "y": dest.y,
		"target": -1, "mode": 0})
	# The whole first order: turn, re-square, march, arrival.
	var arrived: bool = false
	for _i in range(1800):
		await get_tree().physics_frame
		if u.current_order == null and not u.has_move_target and u._reform_bodies_settled():
			arrived = true
			break
	assert_true(arrived, "the first order ran to completion")
	assert_gt(u.facing.dot(Vector2.UP), 0.99, "the block faces its first destination")

	var axis: Vector2 = u.facing.orthogonal()
	var before: PackedFloat32Array = _laterals(u, axis)
	var half: float = u.file_pitch_wu() * 0.5
	# The second order: straight ahead, so it needs no turn of its own.
	var dest2 := u.position + Vector2(0, -100)
	_battle._apply_order_cmd({"units": [u.uid], "x": dest2.x, "y": dest2.y,
		"target": -1, "mode": 0})
	var crossed := {}
	var worst_shift: float = 0.0
	for _i in range(240):
		await get_tree().physics_frame
		var now: PackedFloat32Array = _laterals(u, axis)
		for i in range(now.size()):
			worst_shift = maxf(worst_shift, absf(now[i] - before[i]))
			if before[i] * now[i] < 0.0 and absf(before[i]) > half and absf(now[i]) > half:
				crossed[i] = true
	assert_eq(crossed.size(), 0,
		"no man crosses to the other flank on the second order (%d did)" % crossed.size())
	assert_lt(worst_shift, u.file_pitch_wu() * 0.5,
		"no man walks sideways off his file on the second order (worst %.1f wu)" % worst_shift)
