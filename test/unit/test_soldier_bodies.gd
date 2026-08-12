extends GutTest
## Phase 1 of individual-level collision (see docs/individual-collision-design.md):
## the parallel, deterministic soldier-body layer seeded from the regiment's
## formation slots. These pin the scaffold's invariants — stable ids,
## deterministic (replay-safe) seeding, containment within the regiment block,
## and correct facing — before later phases make the layer authoritative.
##
## The layer is active (Unit.INDIVIDUAL_COLLISION == true) but non-authoritative:
## it's seeded, separated, and debug-rendered in parallel, yet combat, movement,
## and morale still read the regiment circle, so gameplay is unchanged. These call
## the seeding functions directly, as the separation tests call _separate() directly.


func _make_unit(uid: int, max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_soldier_layer_is_active_but_non_authoritative() -> void:
	assert_true(Unit.INDIVIDUAL_COLLISION,
		"the soldier layer is on — seeded, separated, and debug-rendered in parallel")
	# Non-authoritative is the contract the rest of the suite enforces: the combat,
	# movement, and morale tests assert unchanged outcomes with the flag on.


func test_soldier_ids_are_unique_within_a_regiment() -> void:
	var u := _make_unit(3)
	var seen := {}
	for i in range(u.soldiers):
		var id: int = u.soldier_id(i)
		assert_false(seen.has(id), "soldier id %d is unique within the regiment" % id)
		seen[id] = true


func test_soldier_id_ranges_are_disjoint_across_regiments() -> void:
	# The stride exceeds max_soldiers, so two regiments' id ranges never overlap.
	var a := _make_unit(0)
	var b := _make_unit(1)
	var a_max: int = a.soldier_id(a.soldiers - 1)
	var b_min: int = b.soldier_id(0)
	assert_true(a_max < b_min, "regiment 0's ids fall entirely below regiment 1's")


func test_seeding_count_matches_living_soldiers() -> void:
	var u := _make_unit(5, 80)
	u.seed_sim_soldiers()
	assert_eq(u._sim_soldier_pos.size(), u.soldiers, "one simulated body per living soldier")


func test_seeding_is_deterministic_across_identical_regiments() -> void:
	# Replay safety: identical (uid, position, facing, soldiers) => identical bodies,
	# with no dependence on RNG or frame timing.
	var a := _make_unit(7, 60)
	var b := _make_unit(7, 60)
	a.position = Vector2(123, -45)
	b.position = Vector2(123, -45)
	a.facing = Vector2(0.6, 0.8).normalized()
	b.facing = Vector2(0.6, 0.8).normalized()
	assert_eq(a.soldier_world_slots(a.soldiers), b.soldier_world_slots(b.soldiers),
		"identical regiments seed identical soldier positions")


func test_soldiers_stay_within_the_regiment_block() -> void:
	var u := _make_unit(9, 120)
	u.position = Vector2(200, 50)
	var slots := u.soldier_world_slots(u.soldiers)
	var extent: float = u.soldier_block_extent()
	for s in slots:
		assert_true(u.position.distance_to(s) <= extent,
			"each soldier stays within the block extent of the regiment center")


func test_front_rank_sits_toward_the_facing() -> void:
	# Slot 0 is the front rank (local -Y), so after rotation it must lie on the
	# facing side of the regiment center.
	var u := _make_unit(11, 120)
	u.facing = Vector2.DOWN
	var slots := u.soldier_world_slots(u.soldiers)
	var ahead: float = (slots[0] - u.position).dot(u.facing)
	assert_true(ahead > 0.0, "the front-rank soldier sits ahead of center, toward the facing")


# --- step() -> couple() slot handoff (performance) --------------------------
# SoldierBodies.step() and SoldierBodies.couple() are separate per-unit passes over
# every unit each physics tick, and both independently need soldier_world_slots(soldiers)
# -- step() hands its own computation to couple() instead of letting it recompute the
# identical result a moment later. See Unit._step_slots_for_couple's own doc comment.

func test_step_hands_its_slots_to_couple_without_recomputing() -> void:
	var u := _make_unit(13, 24)
	u.seed_sim_soldiers()
	assert_false(u._step_slots_for_couple_valid, "no handoff before step() has ever run")
	var expected: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	SoldierBodies.step(u, 1.0 / 60.0)
	assert_true(u._step_slots_for_couple_valid, "step() leaves a valid handoff for couple()")
	assert_eq(u._step_slots_for_couple, expected,
		"the handed-off slots match a fresh soldier_world_slots() computation")
	SoldierBodies.couple(u, 1.0 / 60.0)
	assert_false(u._step_slots_for_couple_valid,
		"couple() consumes the handoff so a later, unrelated call can't reuse it stale")


func test_couple_behaves_identically_whether_or_not_the_handoff_is_present() -> void:
	# The handoff is a pure optimisation: couple()'s own outcome (how far it slides
	# `position` toward the bodies' centroid) must not depend on whether it reused a
	# pre-populated handoff or computed the slots itself. Populate the handoff directly
	# (rather than by calling step(), which ALSO integrates body positions one tick --
	# a real side effect that would legitimately change the centroid and confound this
	# comparison) so the two fixtures start from byte-identical body positions and the
	# ONLY difference is whether _step_slots_for_couple is present. Perturb one body off
	# its slot after seeding (seeding alone leaves every body exactly on-slot, which would
	# make the coupling a trivial no-op either way) so there is an actual centroid drift
	# for coupling to react to.
	var with_handoff := _make_unit(14, 24)
	with_handoff.seed_sim_soldiers()
	with_handoff._sim_soldier_pos[0] += Vector2(5.0, 0.0)
	with_handoff._step_slots_for_couple = with_handoff.soldier_world_slots(with_handoff.soldiers)
	with_handoff._step_slots_for_couple_valid = true
	SoldierBodies.couple(with_handoff, 1.0 / 60.0)

	var without_handoff := _make_unit(15, 24)
	without_handoff.seed_sim_soldiers()
	without_handoff._sim_soldier_pos[0] += Vector2(5.0, 0.0)
	assert_false(without_handoff._step_slots_for_couple_valid,
		"sanity: no handoff populated for this fixture")
	SoldierBodies.couple(without_handoff, 1.0 / 60.0)

	assert_eq(with_handoff.position, without_handoff.position,
		"couple()'s coupling outcome is identical whether it reused a pre-populated handoff or fell back to computing its own slots")
