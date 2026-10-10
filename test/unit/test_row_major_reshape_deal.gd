extends GutTest
## A row-major block that changes its file count deals the new cells from where its men stand.
##
## Cell i of a row-major grid sits in column i % files, so handing soldier i cell i again after
## the file count changes moves his column with it, and a third of a block that never turned walks
## across its own centreline to reach the new grid. These measure that walk for a player resize
## and for the automatic ranks-closed narrowing, on foot and on cavalry (which is always row
## major), and the paths that keep the dealt pairing in force afterwards: casualties on either
## path, an absorb, a lateral mirror armed or baked, a hold-ground re-square, a reform hold, and a
## block with no bodies.

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
	# The Cavalry loadout's own pitches (1 m files, 3 m ranks), which a bare Unit does not get,
	# so the grid matches a live squadron's (the demo dumps 40 wu files and 120 wu ranks):
	# a rank is deeper than a file is wide, as a horse is longer than broad.
	u.file_pitch = 1.0 * WorldScale.WU_PER_M
	u.rank_pitch = 3.0 * WorldScale.WU_PER_M
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


## The walk from where the men stood (`bodies`) to their slots now, for every man both cover.
## `lateral` is a FIXED world axis, measured from the unit's position.
## - crossed: men on the other side of the centreline from their slot, each more than half a
##   file pitch off it. No margin: a column half a pitch off the centre sits there only to float
##   precision (9.000006 wu against a 9.0 half pitch), so a man stepping between the two
##   columns either side of the centre can read as crossing. That step is one pitch, which the
##   lateral bound below allows, so a reading there is a real flaw in the deal, not noise.
## - lateral_excess: how far each man's slot lies sideways from the nearest point of the new
##   block's width to him (his own lateral position when he already stands inside it). A man
##   inside the block keeps within a pitch of his place; one outside it comes straight in.
## - depth_excess: the same along the depth axis (perpendicular to `lateral`), against the new
##   block's own depth span: a man already inside it keeps within a rank of his depth, so no
##   front-rank man is dealt a cell ranks back.
## - depth_gained: how much deeper the new block is than the men stood (the slots' depth span
##   less the men's), 0 when it is shallower. A narrowing deepens the block, so its men spread
##   rearward by design, by at most this much more than a widening's men move.
## - farthest: the longest walk to a slot.
func _travel(u: Unit, bodies: PackedVector2Array, lateral: Vector2) -> Dictionary:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var depth_axis: Vector2 = lateral.orthogonal()
	var half: float = u.file_pitch_wu() * 0.5
	var width: float = 0.0
	var depth_lo: float = INF
	var depth_hi: float = -INF
	for s in slots:
		width = maxf(width, absf((s - u.position).dot(lateral)))
		depth_lo = minf(depth_lo, (s - u.position).dot(depth_axis))
		depth_hi = maxf(depth_hi, (s - u.position).dot(depth_axis))
	var count: int = mini(bodies.size(), slots.size())
	var old_lo: float = INF
	var old_hi: float = -INF
	for i in range(count):
		old_lo = minf(old_lo, (bodies[i] - u.position).dot(depth_axis))
		old_hi = maxf(old_hi, (bodies[i] - u.position).dot(depth_axis))
	var crossed: int = 0
	var farthest: float = 0.0
	var excess: float = 0.0
	var depth_excess: float = 0.0
	for i in range(count):
		farthest = maxf(farthest, bodies[i].distance_to(slots[i]))
		var a: float = (bodies[i] - u.position).dot(lateral)
		var b: float = (slots[i] - u.position).dot(lateral)
		if a * b < 0.0 and absf(a) > half and absf(b) > half:
			crossed += 1
		excess = maxf(excess, absf(b - clampf(a, -width, width)))
		var ad: float = (bodies[i] - u.position).dot(depth_axis)
		var bd: float = (slots[i] - u.position).dot(depth_axis)
		depth_excess = maxf(depth_excess, absf(bd - clampf(ad, depth_lo, depth_hi)))
	return {"crossed": crossed, "farthest": farthest, "lateral_excess": excess,
			"depth_excess": depth_excess,
			"depth_gained": maxf(0.0, (depth_hi - depth_lo) - (old_hi - old_lo))}


## Assert no man crosses the centreline, none is sent more than `lateral_pitches` file pitches
## sideways of his place in the new block, and (when `depth_ranks` is positive) none more than
## that many rank pitches off his depth. A narrowing deepens the block, so its men spread
## rearward by design: `depth_ranks` 0 bounds the depth walk by the depth the block gains plus
## one rank instead. A front man dealt to the rear of a deepened file walks the block's whole
## new depth, past that bound.
func _assert_no_walk_across(u: Unit, t: Dictionary, what: String,
		depth_ranks: float = 1.0, lateral_pitches: float = 1.0) -> void:
	assert_eq(int(t["crossed"]), 0, "%s: %d men cross the centreline" % [what, int(t["crossed"])])
	assert_lt(float(t["lateral_excess"]), u.file_pitch_wu() * lateral_pitches + 0.01,
		"%s: a man is sent %.1f wu sideways of his place (pitch %.1f)"
		% [what, float(t["lateral_excess"]), u.file_pitch_wu()])
	if depth_ranks > 0.0:
		assert_lt(float(t["depth_excess"]), u.rank_pitch_wu() * depth_ranks + 0.01,
			"%s: a man is sent %.1f wu off his depth (rank pitch %.1f)"
			% [what, float(t["depth_excess"]), u.rank_pitch_wu()])
	else:
		assert_lt(float(t["depth_excess"]),
			float(t["depth_gained"]) + u.rank_pitch_wu() + 0.01,
			"%s: a man is sent %.1f wu off his depth (the block gains %.1f, rank %.1f)"
			% [what, float(t["depth_excess"]), float(t["depth_gained"]), u.rank_pitch_wu()])


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
	_assert_no_walk_across(u, t, "resize 8 -> 7")


## Both rear ranks of that resize hold four men at the same four lateral positions, so each of
## them keeps his own: the short rear rank is dealt on its own rather than by the left-hand
## files its cells are numbered into.
func test_a_resize_keeps_the_short_rear_rank_in_place_laterally() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	u.set_frontage(7)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(56, COUNT):
		var a: float = (bodies[i] - u.position).dot(lateral)
		var b: float = (slots[i] - u.position).dot(lateral)
		assert_almost_eq(b, a, 0.01, "rear-rank man %d keeps his lateral place" % i)


## The automatic ranks-closed narrowing (no player frontage), 11 files to 5: no crossings (the
## identity reflow sent 20).
func test_closing_ranks_sends_no_man_across_the_centreline() -> void:
	var u := _make_foot(0)
	var files_open: int = u.formation_files(u.soldiers)
	var t := _regrid(u, _close_ranks)
	assert_eq(files_open, 11, "precondition: 60 men open on 11 files")
	assert_eq(u.formation_files(u.soldiers), 5, "precondition: closing ranks narrows to 5")
	_assert_no_walk_across(u, t, "ranks closed 11 -> 5", 0.0)


## Cavalry reflows row major whatever its reform mode, so it carries the same walk: a resize and
## the ranks-closed narrowing (80 mounts, 9 files to 4) both send no mount across.
func test_cavalry_reshapes_send_no_mount_across_the_centreline() -> void:
	var resized := _make_cavalry(8)
	assert_false(resized._effective_file_major_reform(), "precondition: cavalry is row major")
	var t := _regrid(resized, func(b: Unit) -> void: b.set_frontage(5))
	_assert_no_walk_across(resized, t, "cavalry resize 8 -> 5", 0.0)
	var closing := _make_cavalry(0, 80)
	var files_open: int = closing.formation_files(closing.soldiers)
	t = _regrid(closing, _close_ranks)
	assert_eq(files_open, 9, "precondition: 80 mounts open on 9 files")
	assert_eq(closing.formation_files(closing.soldiers), 4,
		"precondition: closing ranks narrowed the squadron to 4")
	_assert_no_walk_across(closing, t, "cavalry ranks closed 9 -> 4", 0.0)


## The narrowings again on every heading the widening test uses: read back into the slot frame
## off an axis, one old column's men stand a hair apart laterally, which is when the deal's
## column buckets matter (see the widening test below).
func test_narrowings_keep_their_depth_on_every_heading() -> void:
	for heading in [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2(1, 1).normalized()]:
		var foot := _make_foot(0)
		foot.facing = heading
		_assert_no_walk_across(foot, _regrid(foot, _close_ranks),
				"foot facing %s ranks closed 11 -> 5" % heading, 0.0)
		var squadron := _make_cavalry(0, 80)
		squadron.facing = heading
		_assert_no_walk_across(squadron, _regrid(squadron, _close_ranks),
				"cavalry facing %s ranks closed 9 -> 4" % heading, 0.0)
		var resized := _make_cavalry(8)
		resized.facing = heading
		_assert_no_walk_across(resized,
				_regrid(resized, func(b: Unit) -> void: b.set_frontage(5)),
				"cavalry facing %s resized 8 -> 5" % heading, 0.0)


## A widening by one file, the demo's left squadron: 46 mounts from 7 files to 8. The plain
## lateral-file deal sent a front-rank mount 180 wu rearward there, a rank and a half of the
## squadron's 120 wu ranks (3 m ranks at 20 wu/m, doubled by the formation's spacing). Every
## mount now stays within a rank of his depth and a pitch of his place.
##
## The deal sorts the men laterally, and one column's men stand a hair apart laterally: float
## residue, from reading them back into the slot frame (a diagonal heading here) or from the sim
## itself (the demo squadron's columns agree to the dump's 0.01 wu). An exact lateral sort
## ordered each column by that hair instead of by depth; bucketing lateral position into
## half-pitch steps fixes it. Without the buckets the diagonal foot block reads 27 wu here.
func test_a_widening_keeps_every_mount_near_his_depth() -> void:
	for heading in [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2(1, 1).normalized()]:
		var u := _make_cavalry(7, 46)
		u.facing = heading
		assert_eq(u.rank_pitch_wu(), 3.0 * u.file_pitch_wu(), "precondition: ranks three files deep")
		var t := _regrid(u, func(b: Unit) -> void: b.set_frontage(8))
		assert_eq(u.formation_files(u.soldiers), 8, "precondition: widened to 8 files")
		_assert_no_walk_across(u, t, "cavalry facing %s widened 7 -> 8" % heading)
		for f in range(1, 4):
			var g := _make_foot(8 + f)
			g.facing = heading
			_assert_no_walk_across(g, _regrid(g, func(b: Unit) -> void: b.set_frontage(9 + f)),
					"foot facing %s widened %d -> %d" % [heading, 8 + f, 9 + f])
		# A doubling, 5 files to 10: each new file takes half an old column, which the column's
		# bit-reversed order spreads over its whole depth (plain front-to-back order sends a
		# man 54 wu, three ranks, off his depth here). Five files are added, so the outermost
		# men spread up to 5 / 2 pitches sideways, plus half a pitch where the new grid's
		# centring shifts: a bound of (5 + 1) / 2 = 3 pitches (they read 2.5).
		var doubled := _make_foot(5)
		doubled.facing = heading
		_assert_no_walk_across(doubled, _regrid(doubled, func(b: Unit) -> void: b.set_frontage(10)),
				"foot facing %s doubled 5 -> 10" % heading, 1.0, 3.0)


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


## The rear-rank-first deal is a permutation for every shape, short rear rank or not.
func test_pair_slots_rear_rank_first_is_a_permutation() -> void:
	for shape in [[60, 7], [60, 8], [57, 7], [5, 8], [24, 8], [1, 1], [13, 4]]:
		var n: int = shape[0]
		var files: int = shape[1]
		var grid: PackedVector2Array = UnitFormation.block_slots(n, files + 1, 10.0, 12.0)
		var slots: PackedVector2Array = UnitFormation.block_slots(n, files, 10.0, 12.0)
		var perm: PackedInt32Array = UnitFormation.pair_slots_rear_rank_first(grid, slots, files)
		var seen := {}
		for c in perm:
			seen[c] = true
		assert_eq(perm.size(), n, "one cell per man (%d/%d)" % [n, files])
		assert_eq(seen.size(), n, "every cell taken once (%d/%d)" % [n, files])


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
	_assert_no_walk_across(u, t, "placeholder then deal")


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
		# The casualties are the tail men, three of the four in the short rear rank, so its one
		# survivor, 1.5 pitches off centre, steps in to the one rear cell left, at the centre.
		assert_lt(float(t["lateral_excess"]), u.file_pitch_wu() * 1.5 + 0.01,
			"cavalry %s: a man is sent %.1f wu sideways of his place"
			% [u.is_cavalry, float(t["lateral_excess"])])
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
	_assert_no_walk_across(u, t, "hold ground, three regiment-path casualties")
	assert_lt(float(t["farthest"]), u.file_pitch_wu() * 4.0,
		"no man walks the block's depth (farthest %.1f wu)" % float(t["farthest"]))


## An absorb after a resize appends men the dealt pairing has no entry for. Once the body layer
## holds them, the whole block is dealt again from where it stands rather than dropped to the
## identity layout, which walked 23 of the 60 across.
func test_an_absorb_after_a_resize_deals_the_newcomers_in() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	_stand_on_slots(u)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	var other: Unit = Unit.new()
	other.max_soldiers = 10
	add_child_autofree(other)
	other.position = Vector2(0.0, 200.0)
	other.facing = Vector2.DOWN
	other.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	other.seed_sim_soldiers()
	u.absorb(other)
	assert_eq(u.soldiers, COUNT + 10, "precondition: the newcomers joined")
	for _k in range(3):
		SoldierBodies.step(u, 1.0 / 60.0)
	assert_eq(u._sim_soldier_pos.size(), u.soldiers, "precondition: the body layer holds them")
	assert_eq(u._sim_soldier_row_slot.size(), u.soldiers, "the pairing covers the whole block")
	# The newcomers still stand where they spawned, 200 wu off the block, and are dealt in with
	# the rest. Measured, one file's own men shift up to 27 wu (a rank and a half) along it:
	# a rank for a newcomer dealt into that file, and the half rank the grid re-centres by as
	# it gains a rank.
	_assert_no_walk_across(u, _travel(u, bodies, lateral), "absorb after a resize", 1.5)


## An ordinary per-soldier casualty keeps the deal: SoldierMelee.reap trims the pairing at the
## dead man's own index, and the next query leaves that trim as it is. The trim renumbers every
## cell behind the dead man's, so a row-major rank's first man behind him steps to the far end
## of the rank ahead; this pins only that the deal does not undo or redo the trim.
## TODO(#1781): the reap cascade itself walks men across the block.
func test_a_per_soldier_casualty_after_a_resize_keeps_the_deal() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	_stand_on_slots(u)
	var held: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	assert_eq(held.size(), COUNT, "precondition: a dealt pairing is held")
	var killer: Unit = _make_foot(8)
	killer.team = 1
	u._sim_soldier_hp[10] = 0.0
	SoldierMelee.reap(u, killer)
	assert_eq(u.soldiers, COUNT - 1, "precondition: reap took the man")
	var expected: PackedInt32Array = UnitFormation.drop_slot_assignment(held, 10)
	assert_eq(u._sim_soldier_row_slot, expected, "reap trims the pairing at the dead man's index")
	u.formation_slots(u.soldiers)
	assert_eq(u._sim_soldier_row_slot, expected, "and the next query leaves the trim as it is")


## An about-faced block whose mirror is still armed narrows its ranks: the deal reads the bodies
## through the mirror, so it keeps every man on his own flank.
func test_closing_ranks_under_an_armed_mirror_sends_no_man_across() -> void:
	for make in [_make_foot.bind(0), _make_cavalry.bind(0, 80)]:
		var u: Unit = make.call()
		_about_face_and_resquare(u, true)
		assert_true(u._formation_mirror_x, "precondition: the mirror is armed")
		var t := _regrid(u, _close_ranks)
		_assert_no_walk_across(u, t, "cavalry %s, ranks closed under an armed mirror" % u.is_cavalry,
				0.0)


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
		_assert_no_walk_across(u, t, "cavalry %s, resized after a baked mirror" % u.is_cavalry)


## A regiment-path casualty no query has seen yet, then a fresh order that bakes the mirror. The
## bake relabels only a pairing as long as the block, so it leaves this one as it was; the next
## query finds it longer than the block and deals it again from the bodies, which already stand
## where the mirrored slots put them, so the skipped relabel costs nothing. Dropping that pairing
## to the identity layout instead walked a man 128.9 wu through the block's depth.
func test_a_bake_over_an_unqueried_casualty_is_dealt_from_the_bodies() -> void:
	var u := _make_foot(8)
	_about_face_and_resquare(u, true)
	var bodies: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var lateral: Vector2 = u.facing.orthogonal()
	u.soldiers -= 3
	u.set_current_order(Order.new_move(u.position + u.facing * 200.0))
	assert_false(u._formation_mirror_x, "precondition: the mirror is baked")
	assert_eq(u._sim_soldier_row_slot.size(), COUNT, "the bake leaves the long pairing unrelabelled")
	var t: Dictionary = _travel(u, bodies, lateral)
	assert_eq(u._sim_soldier_row_slot.size(), u.soldiers, "the next query deals it for the survivors")
	_assert_no_walk_across(u, t, "a bake over an unqueried casualty")
	assert_lt(float(t["farthest"]), u.file_pitch_wu() * 4.0,
		"no man walks the block's depth (farthest %.1f wu)" % float(t["farthest"]))


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
	# The re-square reflects the grid in depth and the new grid is a rank deeper, so the short
	# rear rank's men, now at the front, step a rank and a half back into the new front ranks.
	_assert_no_walk_across(u, t, "hold ground over a pending reshape", 1.5)
	assert_lt(float(t["farthest"]), u.file_pitch_wu() * 4.0,
		"no man walks the block's depth (farthest %.1f wu)" % float(t["farthest"]))


## A reform hold bends the paths of men a depth reflection leaves walking the block's depth (the
## traverse flank arcs). It reads a man on his own cell index as one of those, which means
## nothing in a lateral deal, so a dealt pairing takes no arcs: its slots are exactly the cells
## it names, even with every body midway through the block where the arcs would bow widest.
func test_a_dealt_pairing_takes_no_flank_arcs_under_a_reform_hold() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	_stand_on_slots(u)
	assert_true(u._row_slot_dealt, "precondition: the pairing was dealt")
	var pairing: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	var ranks: int = UnitFormation.ranks_for(COUNT, 7)
	var would_bow: int = 0
	for i in range(COUNT):
		if pairing[i] == i and i / 7 != ranks - 1 - i / 7:
			would_bow += 1
	assert_gt(would_bow, 0, "precondition: the deal leaves men the arcs would bow")
	u.set_current_order(Order.new_move(u.position + u.facing * 200.0))
	u.active_leaf().reform_timer = 1.0
	assert_true(u._reform_holding(), "precondition: a reform hold")
	for i in range(COUNT):
		u._sim_soldier_pos[i] = u.position
	var slots: PackedVector2Array = u.formation_slots(COUNT, false)
	assert_eq(slots, UnitFormation.permute_slots(UnitFormation.slots(u, COUNT), pairing),
		"every man's slot is the dealt cell, unbowed")


## A quarter-fold re-square deals its pairing from where the men stand too, so it is tagged as
## dealt and its reform hold takes no arcs either (the gate itself is the test above).
func test_a_quarter_fold_pairing_takes_no_flank_arcs_under_its_reform_hold() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	# A settled quarter-turn drill: the facing turns and the grid folds the turn back.
	var leaf: Order = Order.new_quarter_turn(1)
	u.set_current_order(leaf)
	leaf.turn_start_facing = u.facing
	u.facing = u.facing.rotated(PI * 0.5)
	u._settle_order_turn()
	_stand_on_slots(u)
	assert_almost_eq(absf(u._formation_angle), PI * 0.5, 0.001, "precondition: a quarter fold")
	assert_true(u.reform_ranks(true), "precondition: the quarter fold re-squares")
	assert_true(u._row_slot_dealt, "the quarter-fold pairing is tagged as dealt")
	var pairing: PackedInt32Array = u._sim_soldier_row_slot.duplicate()
	assert_eq(pairing.size(), COUNT, "precondition: the fold was re-paired")
	if u.active_leaf() == null:
		u.set_current_order(Order.new_move(u.position + u.facing * 200.0))
	u.active_leaf().reform_timer = 1.0
	assert_true(u._reform_holding(), "precondition: a reform hold")
	for i in range(COUNT):
		u._sim_soldier_pos[i] = u.position
	assert_eq(u.formation_slots(COUNT, false),
		UnitFormation.permute_slots(UnitFormation.slots(u, COUNT), pairing),
		"every man's slot is the dealt cell, unbowed")


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


func test_row_layout_state_survives_a_snapshot() -> void:
	var u := _make_foot(8)
	_stand_on_slots(u)
	u.set_frontage(7)
	u.formation_slots(u.soldiers)
	var d: Dictionary = u.to_snapshot_dict()
	var restored := Unit.new()
	restored.apply_snapshot_dict(d)
	assert_eq(restored._row_layout_files, 7, "the layout file count round-trips")
	assert_true(restored._row_slot_dealt, "the dealt flag round-trips")
	restored.free()
	d.erase("row_layout_files")
	d.erase("row_slot_dealt")
	var old := Unit.new()
	old.apply_snapshot_dict(d)
	assert_eq(old._row_layout_files, -1, "an older snapshot falls back to never laid out")
	assert_false(old._row_slot_dealt, "and to a pairing that was not dealt")
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
