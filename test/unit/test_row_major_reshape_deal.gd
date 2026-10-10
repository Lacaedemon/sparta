extends GutTest
## A row-major block that changes its file count deals the new cells from where its men stand.
##
## Cell i of a row-major grid sits in column i % files, so handing soldier i cell i again after
## the file count changes moves his column with it, and a third of a block that never turned walks
## across its own centreline to reach the new grid. These measure that walk for a player resize
## and for the automatic ranks-closed narrowing, on foot and on cavalry (which is always row
## major), and the paths that keep the dealt pairing in force afterwards: casualties on either
## path, a lateral mirror armed or baked, a hold-ground re-square, and a block with no bodies.

const COUNT := 60


## A 60-man row-major foot block facing down the screen, on 8 files unless `files` is 0 (then
## its frontage comes from its own headcount, so closing ranks narrows it).
func _make_foot(files: int = 8) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = COUNT
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = files
	u.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	u.seed_sim_soldiers()
	return u


## A cavalry block, 60 mounts unless `count` says otherwise: row major whatever its reform mode
## says. 80 mounts open on 9 files and close ranks onto 4, an uneven narrowing; 60 open on 8 and
## close onto exactly half, which the identity layout already crosses little.
func _make_cavalry(files: int = 0, count: int = COUNT) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.is_cavalry = true
	add_child_autofree(u)
	u.position = Vector2.ZERO
	u.facing = Vector2.DOWN
	u.frontage_override = files
	u.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	u.seed_sim_soldiers()
	return u


## Every body onto its slot: the block has formed.
func _stand_on_slots(u: Unit) -> void:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		u._sim_soldier_pos[i] = slots[i]


## How many of the first `u.soldiers` men stand on the other side of the block's lateral
## centreline from their slot now, each more than half a file pitch off it, and how far the
## farthest man's slot lies from him. `lateral` is a FIXED world axis. "More than half a pitch"
## carries a 0.01 wu margin: a column half a pitch off the centre sits there only to float
## precision (9.000006 against 9.0 measured), so without it a man stepping onto or off such a
## column reads as crossing the block.
func _travel(u: Unit, bodies: PackedVector2Array, lateral: Vector2) -> Dictionary:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var half: float = u.file_pitch_wu() * 0.5 + 0.01
	var crossed: int = 0
	var farthest: float = 0.0
	for i in range(u.soldiers):
		farthest = maxf(farthest, bodies[i].distance_to(slots[i]))
		var a: float = (bodies[i] - u.position).dot(lateral)
		var b: float = (slots[i] - u.position).dot(lateral)
		if a * b < 0.0 and absf(a) > half and absf(b) > half:
			crossed += 1
	return {"crossed": crossed, "farthest": farthest}


## Apply `regrid` to a formed block and measure the walk to the regridded slots.
func _regrid(u: Unit, regrid: Callable) -> Dictionary:
	_stand_on_slots(u)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	regrid.call(u)
	return _travel(u, bodies, lateral)


func _close_ranks(u: Unit) -> void:
	u._ranks_closed = true


## The issue's own measurement, as an absolute: a 60-man foot block that never turned, resized
## from 8 files to 7, sends no man across its centreline (the identity reflow sent 19).
func test_a_resize_sends_no_man_across_the_centreline() -> void:
	var u := _make_foot(8)
	assert_false(u._effective_file_major_reform(), "precondition: row major")
	var t := _regrid(u, func(b: Unit) -> void: b.set_frontage(7))
	assert_eq(u.formation_files(u.soldiers), 7, "precondition: resized to 7 files")
	assert_eq(int(t["crossed"]), 0,
		"resize 8 -> 7: %d of %d men cross the centreline" % [int(t["crossed"]), COUNT])
	assert_lt(float(t["farthest"]), u.file_pitch_wu() * 4.0,
		"resize 8 -> 7: the farthest man walks %.1f wu" % float(t["farthest"]))


## The automatic ranks-closed narrowing (no player frontage), 11 files to 5: no crossings (the
## identity reflow sent 20).
func test_closing_ranks_sends_no_man_across_the_centreline() -> void:
	var u := _make_foot(0)
	var files_open: int = u.formation_files(u.soldiers)
	var t := _regrid(u, _close_ranks)
	assert_eq(files_open, 11, "precondition: 60 men open on 11 files")
	assert_eq(u.formation_files(u.soldiers), 5, "precondition: closing ranks narrows to 5")
	assert_eq(int(t["crossed"]), 0,
		"ranks closed 11 -> 5: %d of %d men cross the centreline" % [int(t["crossed"]), COUNT])


## Cavalry reflows row major whatever its reform mode, so it carries the same walk: a resize and
## the ranks-closed narrowing (80 mounts, 9 files to 4) both send no mount across.
func test_cavalry_reshapes_send_no_mount_across_the_centreline() -> void:
	var resized := _make_cavalry(8)
	assert_false(resized._effective_file_major_reform(), "precondition: cavalry is row major")
	var t := _regrid(resized, func(b: Unit) -> void: b.set_frontage(5))
	assert_eq(int(t["crossed"]), 0,
		"cavalry resize 8 -> 5: %d mounts cross the centreline" % int(t["crossed"]))
	var closing := _make_cavalry(0, 80)
	var files_open: int = closing.formation_files(closing.soldiers)
	t = _regrid(closing, _close_ranks)
	assert_eq(files_open, 9, "precondition: 80 mounts open on 9 files")
	assert_eq(closing.formation_files(closing.soldiers), 4,
		"precondition: closing ranks narrowed the squadron to 4")
	assert_eq(int(t["crossed"]), 0,
		"cavalry ranks closed %d -> %d: %d mounts cross the centreline"
		% [files_open, closing.formation_files(closing.soldiers), int(t["crossed"])])


## The deal is a re-labelling: the block's footprint is the grid's, cell for cell.
func test_the_deal_keeps_the_grid() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	var grid: PackedVector2Array = UnitFormation.slots(u, u.soldiers)
	var local: PackedVector2Array = u.formation_slots(u.soldiers)
	var used := {}
	for p in local:
		used[p] = true
	assert_eq(used.size(), COUNT, "every man has a cell of his own")
	for c in grid:
		assert_true(used.has(c), "cell %s is filled" % c)


## A block with no bodies (a far-tier unit, or one not yet seeded) keeps the identity fill:
## its bodies are built from these slots, so nobody has a place to stay near.
func test_a_block_with_no_bodies_keeps_the_identity_fill() -> void:
	var u := _make_foot(8)
	u._sim_soldier_pos = PackedVector2Array()
	u.set_frontage(7)
	var slots: PackedVector2Array = u.formation_slots(u.soldiers)
	var grid: PackedVector2Array = UnitFormation.slots(u, u.soldiers)
	assert_eq(slots, grid, "soldier i takes cell i")
	assert_eq(u._sim_soldier_row_slot.size(), 0, "no pairing is held")
	assert_eq(u._row_layout_files, 7, "the identity layout is committed at the new file count")


## Fewer bodies than men (a reinforcement ahead of the body layer): the identity fill stands in
## for the tick, but the file count stays uncommitted, so the next query with bodies deals.
func test_too_few_bodies_hold_a_placeholder_and_deal_next_query() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	u._sim_soldier_pos = bodies.slice(0, COUNT - 5)
	u.set_frontage(7)
	u.formation_slots(u.soldiers)
	assert_eq(u._sim_soldier_row_slot.size(), 0, "no pairing from too few bodies")
	assert_eq(u._row_layout_files, 8, "the placeholder does not commit the new file count")
	u._sim_soldier_pos = bodies
	var t: Dictionary = _travel(u, bodies, u.facing.orthogonal())
	assert_eq(u._row_slot_files, 7, "the next query deals from the bodies")
	assert_eq(int(t["crossed"]), 0, "and sends nobody across (%d cross)" % int(t["crossed"]))


## A regiment-path casualty (UnitCombat.take_casualties) drops `soldiers` without splicing the
## per-soldier arrays and never says who died. The survivors are dealt again from where they
## stand: dropping the pairing would fall back to the identity layout and send the crossing walk
## the deal avoided, and trimming the tail men's cells out cascades every man behind a vacancy
## one cell on, which sends a rank's first man to the far end of the rank ahead (20 of 57 cross).
func test_a_regiment_path_casualty_after_a_resize_keeps_men_on_their_flank() -> void:
	for make in [_make_foot, _make_cavalry]:
		var u: Unit = make.call(8)
		_stand_on_slots(u)
		u.set_frontage(7)
		_stand_on_slots(u)
		var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
		u.soldiers -= 3
		var t: Dictionary = _travel(u, bodies, u.facing.orthogonal())
		assert_eq(u._sim_soldier_row_slot.size(), u.soldiers, "the pairing is dealt for the survivors")
		assert_eq(int(t["crossed"]), 0,
			"cavalry %s: %d men cross after three regiment-path casualties"
			% [u.is_cavalry, int(t["crossed"])])
		assert_lt(float(t["farthest"]), u.file_pitch_wu() * 4.0,
			"cavalry %s: the farthest man walks %.1f wu" % [u.is_cavalry, float(t["farthest"])])


## The same casualties on a hold-ground re-squared block, whose pairing is the depth reflection:
## the survivors are dealt from where they stand, so none walks the block's depth either.
func test_a_regiment_path_casualty_after_a_hold_ground_re_square_keeps_men_in_place() -> void:
	var u := _make_foot(8)
	_about_face_and_resquare(u, true)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	u.soldiers -= 3
	var t: Dictionary = _travel(u, bodies, u.facing.orthogonal())
	assert_eq(int(t["crossed"]), 0, "%d men cross" % int(t["crossed"]))
	assert_lt(float(t["farthest"]), u.file_pitch_wu() * 4.0,
		"no man walks the block's depth (farthest %.1f wu)" % float(t["farthest"]))


## An ordinary per-soldier casualty (SoldierMelee.reap) keeps the deal too: reap trims the
## pairing at the dead man's own index.
func test_a_per_soldier_casualty_after_a_resize_keeps_the_deal() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	_stand_on_slots(u)
	var held: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	assert_eq(held.size(), COUNT, "precondition: a dealt pairing is held")
	var expected: PackedInt32Array = UnitFormation.drop_slot_assignment(held, 10)
	u._sim_soldier_row_slot = expected
	u._sim_soldier_pos.remove_at(10)
	u.soldiers -= 1
	u.formation_slots(u.soldiers)
	assert_eq(u._sim_soldier_row_slot, expected, "the query keeps reap's trimmed pairing as it is")


## An about-faced block whose mirror is still armed narrows its ranks: the deal reads the bodies
## through the mirror, so it keeps every man on his own flank.
func test_closing_ranks_under_an_armed_mirror_sends_no_man_across() -> void:
	for make in [_make_foot.bind(0), _make_cavalry.bind(0, 80)]:
		var u: Unit = make.call()
		_about_face_and_resquare(u, true)
		assert_true(u._formation_mirror_x, "precondition: the mirror is armed")
		var t := _regrid(u, _close_ranks)
		assert_eq(int(t["crossed"]), 0,
			"cavalry %s: ranks closed under an armed mirror, %d cross"
			% [u.is_cavalry, int(t["crossed"])])


## The same block once a fresh order has baked its mirror into the assignment, then resized:
## the baked block's fallback reflection is not what places the men any more, the deal is.
func test_a_resize_after_a_baked_mirror_sends_no_man_across() -> void:
	for make in [_make_foot, _make_cavalry]:
		var u: Unit = make.call(8)
		_about_face_and_resquare(u, true)
		u.set_current_order(Order.new_move(u.position + u.facing * 200.0))
		assert_false(u._formation_mirror_x, "precondition: the mirror is baked")
		assert_true(u._fallback_mirror_x, "precondition: the fallback reflection stands")
		var t := _regrid(u, func(b: Unit) -> void: b.set_frontage(7))
		assert_eq(int(t["crossed"]), 0,
			"cavalry %s: resized after a baked mirror, %d cross" % [u.is_cavalry, int(t["crossed"])])


## A regiment-path casualty the row layout has not been queried since, and then a fresh order
## that bakes the mirror: the bake trims the pairing before relabelling it, or the trim that
## follows would restore it unrelabelled and swap every off-centre man's flank.
func test_a_bake_after_an_unqueried_casualty_keeps_the_flanks() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	_about_face_and_resquare(u, true)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	u.soldiers -= 3
	u.set_current_order(Order.new_move(u.position + u.facing * 200.0))
	assert_false(u._formation_mirror_x, "precondition: the mirror is baked")
	var t: Dictionary = _travel(u, bodies, lateral)
	assert_eq(int(t["crossed"]), 0, "%d men cross after the bake" % int(t["crossed"]))


## A file-count change no query has laid out yet, reached by a hold-ground about-face: the deal
## lands every man on his ground, and the reflection is not composed onto it a second time.
func test_a_hold_ground_re_square_over_a_pending_reshape_moves_nobody() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	_settle_about_face(u)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	u.frontage_override = 7   # no query between this and the re-square
	assert_true(u.reform_ranks(true), "precondition: the about-face fold re-squares")
	var t: Dictionary = _travel(u, bodies, lateral)
	assert_eq(int(t["crossed"]), 0, "%d men cross" % int(t["crossed"]))
	assert_lt(float(t["farthest"]), u.file_pitch_wu() * 4.0,
		"no man walks the block's depth (farthest %.1f wu)" % float(t["farthest"]))


## A block that never changes its file count holds no pairing: the identity layout is
## untouched by this, cell i for soldier i, through spawn and casualties alike.
func test_an_unchanged_frontage_holds_no_pairing() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.soldiers -= 3
	var slots: PackedVector2Array = u.formation_slots(u.soldiers)
	assert_eq(slots, UnitFormation.slots(u, u.soldiers), "identity layout")
	assert_eq(u._sim_soldier_row_slot.size(), 0, "no pairing held")
	assert_eq(u._row_layout_files, 8, "the layout's file count is recorded")


func test_row_layout_files_survives_a_snapshot() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	u.formation_slots(u.soldiers)
	var d: Dictionary = u.to_snapshot_dict()
	var restored := Unit.new()
	restored.apply_snapshot_dict(d)
	assert_eq(restored._row_layout_files, 7, "the layout file count round-trips")
	restored.free()
	d.erase("row_layout_files")
	var old := Unit.new()
	old.apply_snapshot_dict(d)
	assert_eq(old._row_layout_files, -1, "an older snapshot falls back to never laid out")
	old.free()


## Settle an about-face drill the way a completed ABOUT_FACE leaf does, with every body on its
## slot.
func _settle_about_face(u: Unit) -> void:
	var leaf: Order = Order.new_about_face()
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI)
	u._settle_order_turn()
	_stand_on_slots(u)


func _about_face_and_resquare(u: Unit, hold_ground: bool) -> void:
	_stand_on_slots(u)
	_settle_about_face(u)
	assert_true(u.reform_ranks(hold_ground), "precondition: the about-face fold re-squares")
	_stand_on_slots(u)
