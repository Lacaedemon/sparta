extends GutTest
## Formation-grid operations (#367): the pure layout primitives a maneuver reshapes a
## block with -- the general centred grid (block_slots), the rank count, and the
## transpose / widen / narrow file-count helpers. All pure functions of (n, files,
## spacing), so they're directly unit-testable and replay-safe; a maneuver layers the
## body relabel (which soldier takes which slot) on top.


func _centroid(slots: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for s in slots:
		c += s
	return c / float(slots.size()) if slots.size() > 0 else Vector2.ZERO


# --- block_slots ------------------------------------------------------------

func test_block_slots_has_one_slot_per_soldier() -> void:
	assert_eq(UnitFormation.block_slots(40, 8, 3.4).size(), 40, "one slot per soldier")


func test_block_slots_is_centred_on_the_origin() -> void:
	# A full grid is symmetric about the unit centre, so its centroid is ~0.
	var c := _centroid(UnitFormation.block_slots(40, 8, 3.4))
	assert_almost_eq(c.x, 0.0, 0.001, "centred on X")
	assert_almost_eq(c.y, 0.0, 0.001, "centred on Y")


func test_block_slots_front_rank_is_toward_negative_y() -> void:
	# The first `files` slots are the front rank; it sits at the most-negative Y (forward).
	var slots := UnitFormation.block_slots(40, 8, 3.4)
	var front_y: float = slots[0].y
	var back_y: float = slots[39].y
	assert_lt(front_y, back_y, "the front rank is ahead (-Y) of the rear rank")


func test_block_slots_spacing_scales_the_grid() -> void:
	var slots := UnitFormation.block_slots(40, 8, 5.0)
	# Adjacent files in the front rank are exactly `spacing` apart.
	assert_almost_eq(slots[0].distance_to(slots[1]), 5.0, 0.001, "files are one spacing apart")


func test_block_slots_rank_pitch_deepens_only_the_rank_axis() -> void:
	# An anisotropic grid (cavalry: ranks far deeper than files are wide) keeps the
	# file axis on `spacing` while the rank axis steps by `rank_pitch`, still centred.
	var slots := UnitFormation.block_slots(6, 3, 10.0, 30.0)
	assert_almost_eq(slots[1].x - slots[0].x, 10.0, 0.001, "files stay one file pitch apart")
	assert_almost_eq(slots[0].y, -15.0, 0.001, "front rank sits half the rank pitch forward")
	assert_almost_eq(slots[3].y - slots[0].y, 30.0, 0.001, "ranks are one rank pitch apart")


func test_block_slots_negative_rank_pitch_falls_back_to_isotropic() -> void:
	# The default sentinel (-1.0) must reproduce the isotropic grid exactly, so
	# every pre-existing caller that omits the argument is bit-for-bit unchanged.
	var plain := UnitFormation.block_slots(40, 8, 5.0)
	var sentinel := UnitFormation.block_slots(40, 8, 5.0, -1.0)
	for i in range(plain.size()):
		assert_eq(sentinel[i], plain[i], "slot %d matches the isotropic grid" % i)


func test_anchored_block_slots_carries_rank_pitch() -> void:
	# The anchored variant threads the same rank pitch through to the grid it lays out.
	var plain := UnitFormation.block_slots(6, 3, 10.0, 30.0)
	var anchored := UnitFormation.anchored_block_slots(6, 3, 3, 10.0,
			UnitFormation.Anchor.CENTRE, 30.0)
	for i in range(plain.size()):
		assert_eq(anchored[i], plain[i], "anchored slot %d matches at centre" % i)


func test_block_slots_partial_last_rank_stays_laterally_centred() -> void:
	# 10 soldiers, 4 files -> ranks of 4, 4, 2. Each rank is centred on its own count, so the
	# short last rank doesn't pull the block sideways: the X-centroid stays on the origin.
	# (The Y-centroid sits slightly forward of centre because the rear rank is short -- that's
	# a depth effect, not a lateral lean, so only X is asserted here.)
	var c := _centroid(UnitFormation.block_slots(10, 4, 3.4))
	assert_almost_eq(c.x, 0.0, 0.02, "a partial last rank doesn't pull the block off centre laterally")


func test_block_slots_partial_rear_rank_closes_toward_the_centre() -> void:
	# The short rear rank fills the CENTRE files first -- the wings close in toward the
	# standard while the centre files stay deepest. 10 in 4 files -> ranks 4, 4, 2; the 2-man
	# rear rank sits on the inner columns (+/- half a spacing), never spread out to the wings
	# (which for a full rank would be +/- 1.5 spacings). This is the file-closing behaviour:
	# survivors cluster centrally rather than leaving a ragged gap-toothed rear rank.
	var slots := UnitFormation.block_slots(10, 4, 4.0)
	for i in range(8, 10):
		assert_almost_eq(absf(slots[i].x), 2.0, 0.001,
			"rear-rank survivor %d closes onto an INNER file, not a wing" % i)


func test_block_slots_rear_rank_never_wider_than_a_full_rank() -> void:
	# However the rear rank thins, its survivors stay within the block's full frontage -- the
	# line never bulges sideways as it closes up. Check across a spread of partial counts.
	var full := UnitFormation.block_slots(24, 6, 3.0)          # 6 x 4, full
	var edge: float = absf(full[0].x)                          # a full rank's outermost |x|
	for n in [19, 20, 21, 22, 23]:                             # assorted partial rear ranks
		for s in UnitFormation.block_slots(n, 6, 3.0):
			assert_true(absf(s.x) <= edge + 0.001,
				"n=%d: no slot sits outside the full frontage as the block closes" % n)


func test_block_slots_empty_for_nonpositive_inputs() -> void:
	assert_eq(UnitFormation.block_slots(0, 8, 3.4).size(), 0, "no soldiers -> no slots")
	assert_eq(UnitFormation.block_slots(40, 0, 3.4).size(), 0, "no files -> no slots")


# --- ranks_for --------------------------------------------------------------

func test_ranks_for_divides_and_rounds_up() -> void:
	assert_eq(UnitFormation.ranks_for(40, 8), 5, "40 in 8 files = 5 ranks")
	assert_eq(UnitFormation.ranks_for(41, 8), 6, "a partial rank rounds up")
	assert_eq(UnitFormation.ranks_for(0, 8), 0, "no soldiers, no ranks")


# --- transpose (ranks <-> columns) ------------------------------------------

func test_transposed_files_swaps_frontage_and_depth() -> void:
	# 40 in 8 files is 5 ranks; transposed it is 5 files (the old depth becomes the width).
	assert_eq(UnitFormation.transposed_files(40, 8), 5, "frontage becomes the old rank count")


func test_double_transpose_returns_to_original_for_a_full_grid() -> void:
	# A full grid (n = files * ranks) transposes back to its original frontage.
	var files := 8
	var n := 40                                   # 8 x 5, full
	var once := UnitFormation.transposed_files(n, files)
	var twice := UnitFormation.transposed_files(n, once)
	assert_eq(twice, files, "transposing a full grid twice restores the frontage")


func test_transposed_files_is_at_least_one() -> void:
	assert_eq(UnitFormation.transposed_files(0, 8), 1, "never returns a zero file count")


# --- widen / narrow (explicatio / duplicatio) -------------------------------

func test_widened_files_doubles_the_frontage() -> void:
	assert_eq(UnitFormation.widened_files(40, 8), 16, "explicatio doubles the files")


func test_widened_files_caps_at_a_single_rank() -> void:
	assert_eq(UnitFormation.widened_files(10, 8), 10, "can't have more files than soldiers")


func test_narrowed_files_halves_the_frontage() -> void:
	assert_eq(UnitFormation.narrowed_files(8), 4, "duplicatio halves the files")


func test_narrowed_files_floors_at_one() -> void:
	assert_eq(UnitFormation.narrowed_files(1), 1, "never narrower than a single column")


# --- anchored (asymmetric) explicatio/duplicatio ----------------------------

func test_anchor_shift_is_zero_for_centre() -> void:
	# CENTRE reproduces the plain symmetric widen: no lateral shift at all.
	assert_almost_eq(UnitFormation.anchor_shift(8, 16, 3.4, UnitFormation.Anchor.CENTRE),
		0.0, 0.001, "centre anchor never shifts the block")


func test_anchor_shift_right_holds_the_right_edge_fixed() -> void:
	# Widening 8 -> 16 files at spacing 4.0: half-width goes from 14.0 to 30.0, a
	# gain of 16.0. Anchoring RIGHT slides the (already-centred) block left by that
	# full gain, so the +X edge lands back where it started.
	var spacing := 4.0
	var old_files := 8
	var new_files := 16
	var shift: float = UnitFormation.anchor_shift(old_files, new_files, spacing, UnitFormation.Anchor.RIGHT)
	var old_slots := UnitFormation.block_slots(old_files, old_files, spacing)
	var new_slots := UnitFormation.anchored_block_slots(new_files, old_files, new_files, spacing,
		UnitFormation.Anchor.RIGHT)
	var old_right_edge: float = old_slots[old_files - 1].x   # front rank's rightmost slot
	var new_right_edge: float = new_slots[new_files - 1].x   # front rank's rightmost slot
	assert_almost_eq(new_right_edge, old_right_edge, 0.001,
		"the right edge stays fixed as the block widens")
	assert_lt(shift, 0.0, "widening right-anchored slides the centred block toward -X")


func test_anchor_shift_left_holds_the_left_edge_fixed() -> void:
	# The mirror of the RIGHT case: the -X edge stays fixed, the block slides +X.
	var spacing := 4.0
	var old_files := 8
	var new_files := 16
	var shift: float = UnitFormation.anchor_shift(old_files, new_files, spacing, UnitFormation.Anchor.LEFT)
	var old_slots := UnitFormation.block_slots(old_files, old_files, spacing)
	var new_slots := UnitFormation.anchored_block_slots(new_files, old_files, new_files, spacing,
		UnitFormation.Anchor.LEFT)
	var old_left_edge: float = old_slots[0].x   # front rank's leftmost slot
	var new_left_edge: float = new_slots[0].x   # front rank's leftmost slot
	assert_almost_eq(new_left_edge, old_left_edge, 0.001,
		"the left edge stays fixed as the block widens")
	assert_gt(shift, 0.0, "widening left-anchored slides the centred block toward +X")


func test_anchored_block_slots_matches_block_slots_at_centre() -> void:
	# Anchor.CENTRE must reproduce the plain centred layout exactly -- the existing
	# symmetric explicatio/duplicatio behaviour is a special case of the general
	# anchored layout, not a separate code path.
	var plain := UnitFormation.block_slots(40, 16, 3.4)
	var anchored := UnitFormation.anchored_block_slots(40, 8, 16, 3.4, UnitFormation.Anchor.CENTRE)
	assert_eq(anchored.size(), plain.size(), "same slot count")
	for i in range(plain.size()):
		assert_true(anchored[i].is_equal_approx(plain[i]),
			"slot %d matches the plain centred layout under Anchor.CENTRE" % i)


func test_anchored_block_slots_narrowing_also_respects_the_anchor() -> void:
	# Duplicatio (narrowing) anchored RIGHT: the +X edge of the narrower block still
	# lines up with the +X edge of the wider block it started from.
	var spacing := 4.0
	var old_files := 16
	var new_files := 8
	var old_slots := UnitFormation.block_slots(old_files, old_files, spacing)
	var new_slots := UnitFormation.anchored_block_slots(new_files, old_files, new_files, spacing,
		UnitFormation.Anchor.RIGHT)
	var old_right_edge: float = old_slots[old_files - 1].x
	var new_right_edge: float = new_slots[new_files - 1].x
	assert_almost_eq(new_right_edge, old_right_edge, 0.001,
		"the right edge stays fixed as the block narrows too")


func test_anchor_shift_composes_across_repeated_widens() -> void:
	# anchor_shift always computes a SINGLE step's shift as if starting from a
	# centred block (offset 0) -- it does NOT know about a unit's existing anchor
	# offset from an earlier anchored widen. A caller applying this a second time
	# (e.g. Battle.enqueue_file_double, pressing Shift+B twice on the same unit)
	# must ADD the new shift to the unit's current offset, not replace it, or the
	# "held" flank silently drifts. This pins the composed-offset math directly,
	# mirroring the worked example from the review that caught the bug.
	var spacing := 1.0
	var files_a := 8
	var files_b := 16
	var files_c := 32
	# Step 1: centred (offset 0) -> RIGHT-anchored widen 8 -> 16.
	var shift1: float = UnitFormation.anchor_shift(files_a, files_b, spacing, UnitFormation.Anchor.RIGHT)
	var offset_after_1: float = 0.0 + shift1
	var right_edge_1: float = UnitFormation._half_width(files_b, spacing) + offset_after_1
	# Step 2: RIGHT-anchored widen again, 16 -> 32, composing onto the existing offset.
	var shift2: float = UnitFormation.anchor_shift(files_b, files_c, spacing, UnitFormation.Anchor.RIGHT)
	var offset_after_2: float = offset_after_1 + shift2
	var right_edge_2: float = UnitFormation._half_width(files_c, spacing) + offset_after_2
	assert_almost_eq(right_edge_2, right_edge_1, 0.001,
		"the right flank stays fixed across TWO composed anchored widens, not just one")


func test_anchor_shift_does_not_compose_correctly_if_treated_as_absolute() -> void:
	# The bug the review caught: if a caller (wrongly) uses anchor_shift's return
	# value as an ABSOLUTE offset on the second application (ignoring the unit's
	# existing offset), the held flank visibly jumps. This documents the failure
	# mode so a regression that reintroduces the absolute-overwrite bug is caught.
	var spacing := 1.0
	var files_a := 8
	var files_b := 16
	var files_c := 32
	var shift1: float = UnitFormation.anchor_shift(files_a, files_b, spacing, UnitFormation.Anchor.RIGHT)
	var right_edge_1: float = UnitFormation._half_width(files_b, spacing) + shift1
	# WRONG: treat the second shift as an absolute offset instead of composing it.
	var wrong_offset_after_2: float = UnitFormation.anchor_shift(files_b, files_c, spacing,
		UnitFormation.Anchor.RIGHT)
	var wrong_right_edge_2: float = UnitFormation._half_width(files_c, spacing) + wrong_offset_after_2
	assert_ne(wrong_right_edge_2, right_edge_1,
		"treating the shift as absolute (not composed) is the bug -- the flank jumps")


# --- close the ranks: contract frontage under heavy losses -----------

func test_should_close_ranks_triggers_at_or_below_the_contract_threshold() -> void:
	assert_true(UnitFormation.should_close_ranks(false, 50, 100),
			"exactly half strength crosses the contract threshold")
	assert_true(UnitFormation.should_close_ranks(false, 30, 100),
			"well below half strength stays contracted")
	assert_false(UnitFormation.should_close_ranks(false, 51, 100),
			"just above half strength does not yet contract")


func test_should_close_ranks_recovers_at_or_above_the_recover_threshold() -> void:
	assert_false(UnitFormation.should_close_ranks(true, 65, 100),
			"reinforced back to the recover threshold widens again")
	assert_false(UnitFormation.should_close_ranks(true, 90, 100),
			"well above the recover threshold widens again")


func test_should_close_ranks_holds_state_inside_the_hysteresis_gap() -> void:
	# Between the contract (50%) and recover (65%) fractions, neither predicate fires --
	# the unit keeps whatever state it was already in, so it can't flap tick to tick.
	assert_true(UnitFormation.should_close_ranks(true, 60, 100),
			"already contracted, still inside the gap: stays contracted")
	assert_false(UnitFormation.should_close_ranks(false, 60, 100),
			"already full width, still inside the gap: stays full width")


func test_should_close_ranks_guards_against_zero_max_soldiers() -> void:
	assert_false(UnitFormation.should_close_ranks(false, 0, 0),
			"a degenerate zero-strength unit holds its current state, no division by zero")
	assert_true(UnitFormation.should_close_ranks(true, 0, 0),
			"holds true too -- the guard preserves whatever state it was given")


func test_frontage_contracts_a_notch_once_ranks_closed() -> void:
	var u := Unit.new()
	u.max_soldiers = 120
	add_child_autofree(u)
	var full: int = UnitFormation.frontage(u)
	u._ranks_closed = true
	assert_eq(UnitFormation.frontage(u), UnitFormation.narrowed_files(full),
			"once ranks are closed the auto frontage steps down one notch")
	assert_lt(UnitFormation.frontage(u), full,
			"the contracted frontage is narrower than the full-strength line")


func test_frontage_override_still_wins_when_ranks_closed() -> void:
	# A player's explicit frontage choice is never overridden by the automatic contraction --
	# same precedence as the full-strength auto width it stands in for.
	var u := Unit.new()
	u.max_soldiers = 120
	add_child_autofree(u)
	u.frontage_override = 20
	u._ranks_closed = true
	assert_eq(UnitFormation.frontage(u), 20, "the override wins over the close-ranks contraction")


# --- casualty adaptation (recompute from the LIVE count) --------------------
# A unit can take casualties mid-maneuver, so a maneuver recomputes its target shape from
# the live soldier count every tick rather than caching it. These pin the property the
# grid-ops give it: every helper is a pure function of the count passed in, and the layout
# thins from the rear (frontage held) as men fall -- so passing the live count Just Works.

func test_block_slots_thins_from_the_rear_when_men_fall() -> void:
	# Hold the file count and drop the soldier count: the front ranks are untouched and the
	# rear rank thins -- the line keeps its width and loses depth, never reflowing the front.
	var full := UnitFormation.block_slots(40, 8, 3.4)     # 8 x 5, full
	var after := UnitFormation.block_slots(36, 8, 3.4)    # 8 x 5 with a 4-man last rank
	assert_eq(after.size(), 36, "the slot count follows the live soldier count")
	for i in range(32):                                   # the four full front ranks
		assert_true(after[i].is_equal_approx(full[i]),
			"front-rank slot %d is unchanged when the rear thins" % i)


func test_transposed_files_tracks_the_live_count() -> void:
	# The 90° turn's target frontage is the live rank count, so heavy casualties shrink it:
	# a maneuver that recomputes each tick narrows its turned frontage as men fall.
	assert_eq(UnitFormation.transposed_files(40, 8), 5, "full strength: 5 ranks -> 5 files")
	assert_eq(UnitFormation.transposed_files(24, 8), 3, "after losses: 3 ranks -> 3 files")


func test_widened_files_tracks_the_live_count() -> void:
	# Explicatio's cap is the live count, so a depleted unit can't be told to widen past a
	# single rank -- the target adapts to however many men remain.
	assert_eq(UnitFormation.widened_files(40, 8), 16, "full strength widens to 16 files")
	assert_eq(UnitFormation.widened_files(12, 8), 12, "depleted: capped at the live count")


# --- square grid (a real square footprint, not the wide-line frontage) -------------

func test_square_files_is_roughly_sqrt_n() -> void:
	assert_eq(UnitFormation.square_files(120), 11, "ceil(sqrt(120)) = 11")
	assert_eq(UnitFormation.square_files(100), 10, "a perfect square: ceil(sqrt(100)) = 10")
	assert_eq(UnitFormation.square_files(0), 1, "never fewer than one file")


func test_square_files_is_narrower_than_the_wide_line_frontage() -> void:
	# The whole point: the line frontage (_files, via UnitFormation.frontage) is
	# deliberately wider-than-deep (FORMATION_ASPECT > 1); the square is not.
	var u := Unit.new()
	u.max_soldiers = 120
	add_child_autofree(u)
	assert_lt(UnitFormation.square_files(120), UnitFormation.frontage(u),
		"the square packs narrower than the line's wide frontage")


func test_square_slots_bbox_aspect_is_about_one() -> void:
	# The defining geometric property: a real square footprint, not the 2:1
	# rectangle the wide-line frontage produces for the same count.
	var n := 120
	var files := UnitFormation.square_files(n)
	var ranks := UnitFormation.ranks_for(n, files)
	var slots := UnitFormation.square_slots(n, 9.0)
	var min_p: Vector2 = slots[0]
	var max_p: Vector2 = slots[0]
	for s in slots:
		min_p.x = minf(min_p.x, s.x)
		min_p.y = minf(min_p.y, s.y)
		max_p.x = maxf(max_p.x, s.x)
		max_p.y = maxf(max_p.y, s.y)
	var w: float = max_p.x - min_p.x
	var h: float = max_p.y - min_p.y
	assert_almost_eq(w / h, 1.0, 0.15,
		"bbox aspect (w/h=%.2f, files=%d, ranks=%d) is close to square" % [w / h, files, ranks])


func test_square_slots_has_one_slot_per_soldier() -> void:
	assert_eq(UnitFormation.square_slots(120, 9.0).size(), 120, "one slot per soldier")


func test_square_is_perimeter_flags_the_outer_ring_only() -> void:
	# A 3x3 full square (9 soldiers, 3 files): index layout is
	#   0 1 2
	#   3 4 5
	#   6 7 8
	# every slot except the dead centre (index 4) sits on the outer ring.
	for i in range(9):
		var expected: bool = i != 4
		assert_eq(UnitFormation.square_is_perimeter(i, 9, 3), expected,
			"slot %d perimeter membership" % i)


func test_square_is_perimeter_handles_a_partial_last_rank() -> void:
	# 10 soldiers at 4 files -> ranks of 4, 4, 2 (a 2-man partial last rank). The last
	# rank's two survivors are both edges of their own (2-wide) rank, so both flag as
	# perimeter; the full middle rank's inner two slots (indices 5, 6) do not.
	assert_false(UnitFormation.square_is_perimeter(5, 10, 4), "middle rank, inner-left: not perimeter")
	assert_false(UnitFormation.square_is_perimeter(6, 10, 4), "middle rank, inner-right: not perimeter")
	assert_true(UnitFormation.square_is_perimeter(8, 10, 4), "last (partial) rank: both slots perimeter")
	assert_true(UnitFormation.square_is_perimeter(9, 10, 4), "last (partial) rank: both slots perimeter")


func test_square_is_perimeter_out_of_range_is_false() -> void:
	assert_false(UnitFormation.square_is_perimeter(-1, 9, 3), "negative index")
	assert_false(UnitFormation.square_is_perimeter(9, 9, 3), "index == n is out of range")


# --- live_perimeter_indices: position-based, not slot-index-based -----------
# square_is_perimeter's index-to-position mapping goes stale once SoldierMelee.reap()
# has compacted the per-soldier arrays after a casualty (removing a dead soldier shifts
# every later index down, so index i no longer sits where block_slots originally laid
# it out). live_perimeter_indices reads ACTUAL positions instead, so it stays correct
# after compaction -- these tests exercise the geometry directly, independent of Unit.

func test_live_perimeter_indices_picks_the_farthest_points_from_centroid() -> void:
	# A plus-shape: one point at the centre, four points equidistant on the axes. The
	# centre is closest to the centroid (itself); the four arm-tips are farthest and
	# equidistant from each other, so any target_count <= 4 must exclude the centre.
	var positions := PackedVector2Array([
		Vector2(0, 0),      # 0: centre
		Vector2(10, 0),     # 1: east arm
		Vector2(-10, 0),    # 2: west arm
		Vector2(0, 10),     # 3: north arm
		Vector2(0, -10),    # 4: south arm
	])
	var picked := UnitFormation.live_perimeter_indices(positions, 4)
	assert_eq(picked.size(), 4, "picks exactly target_count points")
	assert_false(picked.has(0), "the centre point is never picked over any of the four arms")
	for i in [1, 2, 3, 4]:
		assert_true(picked.has(i), "arm-tip index %d is picked" % i)


func test_live_perimeter_indices_survives_array_compaction() -> void:
	# The concrete bug this fixes: a slot-index perimeter check computed BEFORE a
	# casualty compacts the array silently mis-selects once the array has shrunk and
	# shifted. Simulate compaction directly -- an original 3x3 grid (see
	# test_square_is_perimeter_flags_the_outer_ring_only) with its centre soldier (old
	# index 4) already reaped, so what was index 5 is now index 4, etc. Live-position
	# selection must still exclude whichever point is geometrically centremost in the
	# CURRENT array, regardless of what index it now holds.
	var full := [
		Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
		Vector2(-1, 0),  Vector2(0, 0),  Vector2(1, 0),
		Vector2(-1, 1),  Vector2(0, 1),  Vector2(1, 1),
	]
	full.remove_at(4)   # reap the centre soldier, exactly like SoldierMelee.reap()
	var positions := PackedVector2Array(full)   # 8 soldiers now, all on the outer ring
	var picked := UnitFormation.live_perimeter_indices(positions, 8)
	assert_eq(picked.size(), 8, "every surviving soldier is on the ring once the centre is gone")


func test_live_perimeter_indices_breaks_ties_by_index() -> void:
	# Two points equidistant from the centroid: deterministic tie-break picks the
	# lower index first, so replay/determinism never depends on sort stability.
	var positions := PackedVector2Array([Vector2(-5, 0), Vector2(5, 0)])
	assert_eq(UnitFormation.live_perimeter_indices(positions, 1), PackedInt32Array([0]),
		"tied distances: lower index wins")


func test_live_perimeter_indices_degenerate_inputs() -> void:
	assert_eq(UnitFormation.live_perimeter_indices(PackedVector2Array(), 3).size(), 0,
		"no positions -> nothing to pick")
	assert_eq(UnitFormation.live_perimeter_indices(PackedVector2Array([Vector2.ZERO]), 0).size(), 0,
		"target_count <= 0 -> nothing to pick")
	var positions := PackedVector2Array([Vector2(1, 0), Vector2(2, 0)])
	assert_eq(UnitFormation.live_perimeter_indices(positions, 10).size(), 2,
		"target_count beyond the array size is clamped to the array size")


func test_live_perimeter_indices_matches_a_brute_force_full_sort() -> void:
	# The real implementation is a bounded min-heap (O(n log target_count)), not a full sort
	# of every soldier -- differential test against a brute-force reference (sort every index
	# by distance descending, ties broken by index ascending, take the first target_count) on
	# an irregular point cloud, so a heap sift-up/sift-down bug can't hide behind the other
	# tests' small or symmetric inputs. Fixed, hand-picked coordinates (no RNG) so the case is
	# reproducible.
	var positions := PackedVector2Array([
		Vector2(3, 1), Vector2(-2, 4), Vector2(5, -3), Vector2(0, 0), Vector2(-4, -4),
		Vector2(2, 2), Vector2(7, 0), Vector2(-1, -6), Vector2(1, 1), Vector2(-5, 2),
		Vector2(6, 5), Vector2(0, -3), Vector2(-3, 3), Vector2(4, -1), Vector2(2, -5),
		Vector2(-6, 1), Vector2(1, 6), Vector2(3, -4), Vector2(-2, -2), Vector2(5, 3),
	])
	var centroid := Vector2.ZERO
	for p in positions:
		centroid += p
	centroid /= float(positions.size())
	var reference: Array = range(positions.size())
	reference.sort_custom(func(a: int, b: int) -> bool:
		var da: float = positions[a].distance_squared_to(centroid)
		var db: float = positions[b].distance_squared_to(centroid)
		if da == db:
			return a < b
		return da > db)
	for target_count in [1, 3, 7, 12, 20, 25]:
		var expected := PackedInt32Array()
		for i in range(mini(target_count, positions.size())):
			expected.push_back(reference[i])
		expected.sort()
		assert_eq(UnitFormation.live_perimeter_indices(positions, target_count), expected,
			"heap selection matches the brute-force reference at target_count=%d" % target_count)


func test_live_front_indices_picks_the_farthest_forward_points() -> void:
	# Five points scored against forward=Vector2.UP=(0,-1) (Unit.gd's own "front rank toward
	# -Y" convention): the two most-forward (largest projection = most-negative Y) must be
	# picked over the three that sit farther back, regardless of array order.
	var positions := PackedVector2Array([
		Vector2(0, -5),   # 0: farthest forward (score 5)
		Vector2(2, 10),   # 1: farthest back (score -10)
		Vector2(-3, -3),  # 2: forward (score 3)
		Vector2(1, 4),    # 3: back (score -4)
		Vector2(-1, 0),   # 4: middle (score 0)
	])
	var picked := UnitFormation.live_front_indices(positions, 2, Vector2.ZERO, Vector2.UP)
	assert_eq(picked, PackedInt32Array([0, 2]), "the two most-forward points are picked, sorted by index")


func test_live_front_indices_survives_array_compaction() -> void:
	# The concrete bug this fixes: a fixed "first target_count indices" front-rank selection
	# computed BEFORE a casualty compacts the array silently mis-selects once the array has
	# shrunk and shifted (SoldierMelee.reap() splices out the dead, shifting later indices
	# down). Simulate exactly that: a genuinely-front point ends up at a high array index,
	# a genuinely-rear point at a low one -- live-position selection must follow the swap.
	var positions := PackedVector2Array([
		Vector2(0, 10),   # 0: rear (was front before the simulated compaction below)
		Vector2(0, 0),
		Vector2(0, -10),  # 2: front (was rear before the simulated compaction below)
	])
	positions[0] = Vector2(0, -10)  # now index 0 holds the front-most position
	positions[2] = Vector2(0, 10)   # and index 2 holds the rear-most
	var picked := UnitFormation.live_front_indices(positions, 1, Vector2.ZERO, Vector2.UP)
	assert_eq(picked, PackedInt32Array([0]), "selection follows the live position, not the original index")


func test_live_front_indices_breaks_ties_by_index() -> void:
	# Two points with equal forward projection: deterministic tie-break picks the lower
	# index first, so replay/determinism never depends on sort stability.
	var positions := PackedVector2Array([Vector2(-5, 3), Vector2(5, 3)])
	assert_eq(UnitFormation.live_front_indices(positions, 1, Vector2.ZERO, Vector2.UP), PackedInt32Array([0]),
		"tied projections: lower index wins")


func test_live_front_indices_degenerate_inputs() -> void:
	assert_eq(UnitFormation.live_front_indices(PackedVector2Array(), 3, Vector2.ZERO, Vector2.UP).size(), 0,
		"no positions -> nothing to pick")
	assert_eq(UnitFormation.live_front_indices(PackedVector2Array([Vector2.ZERO]), 0, Vector2.ZERO, Vector2.UP).size(), 0,
		"target_count <= 0 -> nothing to pick")
	var positions := PackedVector2Array([Vector2(1, 0), Vector2(2, 0)])
	assert_eq(UnitFormation.live_front_indices(positions, 10, Vector2.ZERO, Vector2.UP).size(), 2,
		"target_count beyond the array size is clamped to the array size")


# --- sort_indices_by_projection / sort_indices_by_angle ----------------------
# The engaged/canonical pairing sort (SoldierBodies.step, via Unit.pairing_sort_indices):
# sorts a group of body indices by actual lateral position (file axis) or angular position
# (the square/schiltron ring) instead of raw array rank.

func test_sort_indices_by_projection_orders_by_lateral_position() -> void:
	# Three points scored against axis=Vector2.RIGHT=(1,0) from the origin: ascending
	# projection is ascending x, regardless of the array order the indices are handed in.
	var positions := PackedVector2Array([
		Vector2(10, 0),   # 0: rightmost
		Vector2(-10, 0),  # 1: leftmost
		Vector2(0, 0),    # 2: middle
	])
	var sorted := UnitFormation.sort_indices_by_projection(
		PackedInt32Array([0, 1, 2]), positions, Vector2.ZERO, Vector2.RIGHT)
	assert_eq(sorted, PackedInt32Array([1, 2, 0]), "leftmost to rightmost, not by array index")


func test_sort_indices_by_projection_is_a_no_op_when_already_lateral_order() -> void:
	# A group already laid out in ascending-x order (the canonical front-rank slot array,
	# by construction) sorts to itself -- proves the canonical side never actually reorders.
	var positions := PackedVector2Array([Vector2(-5, 0), Vector2(0, 0), Vector2(5, 0)])
	var indices := PackedInt32Array([0, 1, 2])
	assert_eq(UnitFormation.sort_indices_by_projection(indices, positions, Vector2.ZERO, Vector2.RIGHT),
		indices, "already-ascending input sorts to itself")


func test_sort_indices_by_projection_breaks_ties_by_index() -> void:
	var positions := PackedVector2Array([Vector2(5, 0), Vector2(5, 3)])
	assert_eq(UnitFormation.sort_indices_by_projection(
			PackedInt32Array([1, 0]), positions, Vector2.ZERO, Vector2.RIGHT),
		PackedInt32Array([0, 1]), "tied projections: lower index wins")


func test_sort_indices_by_projection_matches_a_brute_force_full_sort() -> void:
	# Differential test on an irregular point cloud, mirroring
	# test_live_perimeter_indices_matches_a_brute_force_full_sort's own coverage rationale --
	# the insertion sort's shift loop can't hide an off-by-one behind a small/symmetric input.
	var positions := PackedVector2Array([
		Vector2(3, 1), Vector2(-2, 4), Vector2(5, -3), Vector2(0, 0), Vector2(-4, -4),
		Vector2(2, 2), Vector2(7, 0), Vector2(-1, -6), Vector2(1, 1), Vector2(-5, 2),
	])
	var indices := PackedInt32Array()
	for i in range(positions.size()):
		indices.push_back(i)
	var axis := Vector2(1.0, 0.0)
	var reference: Array = range(positions.size())
	reference.sort_custom(func(a: int, b: int) -> bool:
		var sa: float = positions[a].dot(axis)
		var sb: float = positions[b].dot(axis)
		if sa == sb:
			return a < b
		return sa < sb)
	var expected := PackedInt32Array(reference)
	assert_eq(UnitFormation.sort_indices_by_projection(indices, positions, Vector2.ZERO, axis), expected,
		"insertion sort matches the brute-force reference")


func test_sort_indices_by_angle_orders_around_the_ring() -> void:
	# Four ring points at the cardinal directions: angle() runs from -PI (west, exclusive)
	# through 0 (east) to +PI (west again), so ascending angle order is north, east, south,
	# west for this exact set -- regardless of the array order the indices are handed in.
	var positions := PackedVector2Array([
		Vector2(0, -1),   # 0: north (angle -PI/2)
		Vector2(1, 0),    # 1: east (angle 0)
		Vector2(-1, 0),   # 2: west (angle PI)
		Vector2(0, 1),    # 3: south (angle PI/2)
	])
	var sorted := UnitFormation.sort_indices_by_angle(
		PackedInt32Array([3, 2, 1, 0]), positions, Vector2.ZERO)
	assert_eq(sorted, PackedInt32Array([0, 1, 3, 2]), "ascending angle: north, east, south, west")


func test_sort_indices_by_angle_breaks_ties_by_index() -> void:
	var positions := PackedVector2Array([Vector2(5, 0), Vector2(10, 0)])
	assert_eq(UnitFormation.sort_indices_by_angle(PackedInt32Array([1, 0]), positions, Vector2.ZERO),
		PackedInt32Array([0, 1]), "tied angles: lower index wins")
