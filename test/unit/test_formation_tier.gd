extends GutTest
## FormationTier (docs/large-scale-simulation-design.md phase 1): pure, node-free tests for
## the tier ids, the name table, and the placeholder promotion/demotion distance predicates —
## plus the representational tier marker on Unit. Nothing here exercises sim behavior, because
## phase 1 wires none: these pin the data model in isolation.


func test_tier_ids_are_distinct() -> void:
	assert_ne(FormationTier.CLOSE, FormationTier.FAR)


func test_tier_name_maps_every_known_tier() -> void:
	assert_eq(FormationTier.tier_name(FormationTier.CLOSE), "CLOSE")
	assert_eq(FormationTier.tier_name(FormationTier.FAR), "FAR")


func test_tier_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(FormationTier.tier_name(99), "TIER(99)")


func test_demote_range_exceeds_promote_range() -> void:
	# The hysteresis gap the design requires: a formation sitting at one boundary must not
	# thrash tiers, so the demote threshold must sit strictly beyond the promote threshold.
	assert_gt(FormationTier.DEMOTE_RANGE, FormationTier.PROMOTE_RANGE)


func test_promotes_inside_promote_range() -> void:
	var pos := Vector2(100.0, 200.0)
	var enemy := pos + Vector2(FormationTier.PROMOTE_RANGE - 1.0, 0.0)
	assert_true(FormationTier.should_promote(pos, enemy))


func test_does_not_promote_at_or_beyond_promote_range() -> void:
	var pos := Vector2(100.0, 200.0)
	var at_threshold := pos + Vector2(0.0, FormationTier.PROMOTE_RANGE)
	var beyond := pos + Vector2(0.0, FormationTier.PROMOTE_RANGE + 1.0)
	assert_false(FormationTier.should_promote(pos, at_threshold))
	assert_false(FormationTier.should_promote(pos, beyond))


func test_demotes_beyond_demote_range() -> void:
	var pos := Vector2(-300.0, 50.0)
	var enemy := pos + Vector2(0.0, FormationTier.DEMOTE_RANGE + 1.0)
	assert_true(FormationTier.should_demote(pos, enemy))


func test_does_not_demote_at_or_inside_demote_range() -> void:
	var pos := Vector2(-300.0, 50.0)
	var at_threshold := pos + Vector2(FormationTier.DEMOTE_RANGE, 0.0)
	var inside := pos + Vector2(FormationTier.DEMOTE_RANGE - 1.0, 0.0)
	assert_false(FormationTier.should_demote(pos, at_threshold))
	assert_false(FormationTier.should_demote(pos, inside))


func test_hysteresis_band_fires_neither_predicate() -> void:
	# A formation between the two thresholds keeps whatever tier it already has.
	var pos := Vector2(400.0, -120.0)
	var mid: float = (FormationTier.PROMOTE_RANGE + FormationTier.DEMOTE_RANGE) * 0.5
	var enemy := pos + Vector2(mid, 0.0)
	assert_false(FormationTier.should_promote(pos, enemy))
	assert_false(FormationTier.should_demote(pos, enemy))


func test_predicates_depend_on_distance_not_direction() -> void:
	# Same separation along different axes and quadrants must decide identically — the
	# trigger is a pure function of the scalar distance between the two positions.
	var pos := Vector2(1000.0, 1000.0)
	var d: float = FormationTier.PROMOTE_RANGE - 1.0
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]:
		assert_true(FormationTier.should_promote(pos, pos + dir * d))
		assert_false(FormationTier.should_demote(pos, pos + dir * d))


func test_unit_defaults_to_close_tier() -> void:
	var u: Unit = Unit.new()
	u.max_soldiers = 4
	add_child_autofree(u)
	assert_eq(u.tier, FormationTier.CLOSE)


func test_unit_can_be_constructed_in_the_far_tier() -> void:
	# The phase-1 done-check: a formation can carry either tier, with no behavior wired to
	# the distinction — the marker stores and reads back, and nothing else changes.
	var u: Unit = Unit.new()
	u.max_soldiers = 4
	u.tier = FormationTier.FAR
	add_child_autofree(u)
	assert_eq(u.tier, FormationTier.FAR)
	assert_eq(u.soldiers, 4)   # the close-tier per-soldier path still ran regardless


func test_edge_gap_subtracts_both_reaches_and_never_goes_negative() -> void:
	assert_eq(FormationTier.edge_gap(1000.0, 480.0, 70.0), 450.0, "centre distance less both reaches")
	assert_eq(FormationTier.edge_gap(100.0, 480.0, 70.0), 0.0, "overlapping blocks read as touching")


func test_tier_reach_matches_the_formation_slots_reach() -> void:
	# Checked against the slots the soldiers actually stand in, not against the headcount
	# half-extents tier_reach is built from: face on and to the flank the rectangle's
	# reach is exactly the farthest slot's; obliquely it is never less.
	var u := Unit.new()
	u.max_soldiers = 80
	u.is_cavalry = true
	u.file_pitch = 20.0
	u.rank_pitch = 60.0
	u.facing = Vector2.DOWN
	add_child_autofree(u)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for dir in [Vector2.DOWN, Vector2.UP, Vector2.RIGHT * 5.0, Vector2.LEFT]:
		assert_almost_eq(u.tier_reach(dir), _slot_reach(u, slots, dir), 0.01,
				"face-on or flank reach toward %s is the farthest slot's" % dir)
	var diag: Vector2 = Vector2(1, 1)
	assert_true(u.tier_reach(diag) >= _slot_reach(u, slots, diag) - 0.01,
			"an oblique reach never falls short of the farthest slot")
	assert_gt(u.tier_reach(Vector2.DOWN), u.tier_reach(Vector2.RIGHT),
			"a cavalry squadron reaches farther to its front than to its flank")
	assert_eq(u.tier_reach(Vector2.ZERO), 0.0, "no direction, no reach")


func _slot_reach(u: Unit, slots: PackedVector2Array, dir: Vector2) -> float:
	var best: float = -INF
	for p in slots:
		best = maxf(best, (p - u.position).dot(dir.normalized()))
	return best
