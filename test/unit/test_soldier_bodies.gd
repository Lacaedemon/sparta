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


# --- superphysical speed clamp -----------------------------------------------------
# The arrival correction alone is capped at jog_speed, but the march feed-forward stacks
# on top of it with no cap of its own -- a body chasing a slot that keeps receding at full
# march can integrate feed-forward (up to move_speed) PLUS arrival (up to jog_speed)
# simultaneously. Reproduce that stacking directly: displace one body far BEHIND its slot,
# along the same axis the whole regiment is marching, so the arrival term and the march
# feed-forward point the same way instead of cancelling.

func test_body_speed_never_exceeds_the_sprint_based_cap_while_its_slot_recedes_at_full_march() -> void:
	var dt: float = 1.0 / Replay.PHYSICS_TPS
	var u := _make_unit(31, 4)
	u.state = Unit.State.MOVING
	# A large accel is fixture-only (not a physical claim about this unit type): it lets the
	# body's velocity ramp fully onto the stacked feed-forward + arrival ceiling within a
	# handful of ticks instead of the several seconds a normal accel would take, without
	# changing which velocity the clamp has to bound.
	u.accel = 4000.0
	u.seed_sim_soldiers()
	# facing is DOWN (+Y) -- see _make_unit -- so "behind" the march direction is -Y. The gap
	# (600 wu) stays far larger than jog_speed can close in a handful of ticks, so the arrival
	# term saturates at jog_speed (its own cap) for the whole run, exactly like a body whose
	# slot keeps receding out from under it.
	u._sim_soldier_pos[0] -= Vector2(0.0, 600.0)
	u._approach_velocity = u.facing * u.move_speed   # marching at full sprint
	var cap: float = u.move_speed * u.superphysical_speed_frac
	var worst_speed := 0.0
	for _tick in range(15):
		var before: Vector2 = u._sim_soldier_pos[0]
		SoldierBodies.step(u, dt)
		u.position += u._approach_velocity * dt   # the whole regiment marches too
		worst_speed = maxf(worst_speed, before.distance_to(u._sim_soldier_pos[0]) / dt)
	assert_true(worst_speed <= cap + 0.01,
		"soldier 0's fastest integrated speed (%.2f wu/s) must stay within move_speed * superphysical_speed_frac (%.2f wu/s) even while chasing a receding slot at full march" % [worst_speed, cap])


func test_body_speed_cap_uses_move_speed_times_the_units_own_frac() -> void:
	# The cap tracks whatever this unit's own fields say, not a hard-coded number -- a unit
	# with a different move_speed or a tuned frac gets a correspondingly different ceiling.
	var dt: float = 1.0 / Replay.PHYSICS_TPS
	var u := _make_unit(32, 4)
	u.state = Unit.State.MOVING
	u.accel = 4000.0
	u.move_speed = 120.0
	u.superphysical_speed_frac = 1.3
	u.seed_sim_soldiers()
	u._sim_soldier_pos[0] -= Vector2(0.0, 600.0)
	u._approach_velocity = u.facing * u.move_speed
	var cap: float = u.move_speed * u.superphysical_speed_frac
	var worst_speed := 0.0
	for _tick in range(15):
		var before: Vector2 = u._sim_soldier_pos[0]
		SoldierBodies.step(u, dt)
		u.position += u._approach_velocity * dt
		worst_speed = maxf(worst_speed, before.distance_to(u._sim_soldier_pos[0]) / dt)
	assert_true(worst_speed <= cap + 0.01,
		"the cap follows this unit's own move_speed (%.1f) and superphysical_speed_frac (%.2f), not a fixed constant"
			% [u.move_speed, u.superphysical_speed_frac])


# --- on-slot carried velocity (knockback preservation) ------------------------------
# When a body sits exactly on its formation slot (dist <= MIN_DIST), an external impulse
# such as melee knockback or collision push must not be discarded by on-slot arrival
# clamping -- the carried velocity must decay naturally via friction and steering.

func test_on_slot_body_preserves_carried_knockback_velocity_through_step() -> void:
	var dt: float = 1.0 / Replay.PHYSICS_TPS
	var u := _make_unit(40, 4)
	u.state = Unit.State.FIGHTING
	u.seed_sim_soldiers()
	# Body 0 sits exactly on its slot (dist == 0.0 after seeding).
	var initial_slot: Vector2 = u.soldier_world_slots(u.soldiers)[0]
	assert_eq(u._sim_soldier_pos[0], initial_slot, "body 0 starts exactly on slot")

	# Apply an external knockback impulse to the stationary on-slot body.
	var knockback := Vector2(100.0, 0.0)
	u._sim_body_vel[0] = knockback

	SoldierBodies.step(u, dt)

	# The velocity should be preserved, having only decayed by one tick of friction and steering.
	var resulting_speed: float = u._sim_body_vel[0].length()
	assert_true(resulting_speed > 95.0,
		"carried knockback speed (%.2f wu/s) must not be zeroed on an on-slot body" % resulting_speed)
	assert_true(u._sim_soldier_pos[0].distance_to(initial_slot) > 1.0,
		"on-slot body carrying knockback must advance away from slot by its integrated displacement")


# --- corridor routing inward rank approach & rear rank arrivals --------------------

func test_corridor_to_slot_inward_approach_does_not_fling_to_flank() -> void:
	var u := _make_unit(50, 40)
	u.seed_sim_soldiers()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	# Pick an interior front-rank slot (e.g. index 3, which is 2 files away from the flank).
	var slot_idx: int = 3
	var own_slot: Vector2 = slots[slot_idx]
	var ang: float = u.soldier_block_world_angle()
	var rank_pitch: float = u.rank_pitch_wu()
	var spacing: float = u.file_pitch_wu()

	# Position body slightly displaced inward along the rank lane (1.0 * spacing outboard),
	# but marginally behind the front rank by 0.6 * rank_pitch (exceeding depth * 0.5 threshold).
	var t_local: Vector2 = (own_slot - u.position).rotated(-ang)
	var flank_sign: float = 1.0 if t_local.x >= 0.0 else -1.0
	var p_local: Vector2 = Vector2(t_local.x + flank_sign * spacing * 1.0, t_local.y + rank_pitch * 0.6)
	u._sim_soldier_pos[slot_idx] = u.position + p_local.rotated(ang)

	var to_target: Vector2 = SoldierBodies._corridor_to_slot(u, slot_idx, own_slot, u.soldiers)
	var target_pos: Vector2 = u._sim_soldier_pos[slot_idx] + to_target
	var target_local: Vector2 = (target_pos - u.position).rotated(-ang)

	# Target lateral x should be t_local.x (the slot's column), NOT target_flank_x on the outer edge
	assert_almost_eq(target_local.x, t_local.x, 0.1,
		"a body walking inward along its target rank must steer inward to its slot column (%.2f), not outward to outer flank" % target_local.x)


func test_corridor_to_slot_rear_rank_arrival_routes_directly() -> void:
	var u := _make_unit(51, 40)
	u.seed_sim_soldiers()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	# Slot 39 is in the rear rank. Displace body 39 slightly behind the rear rank.
	var rear_idx: int = u.soldiers - 1
	var own_slot: Vector2 = slots[rear_idx]
	var ang: float = u.soldier_block_world_angle()
	var depth: float = u.rank_pitch_wu()
	var spacing: float = u.file_pitch_wu()

	var t_local: Vector2 = (own_slot - u.position).rotated(-ang)
	# Displaced 1 rank behind rear rank and 1 file laterally:
	var p_local: Vector2 = Vector2(t_local.x + spacing * 1.0, t_local.y + depth * 1.0)
	u._sim_soldier_pos[rear_idx] = u.position + p_local.rotated(ang)

	var to_target: Vector2 = SoldierBodies._corridor_to_slot(u, rear_idx, own_slot, u.soldiers)
	var target_pos: Vector2 = u._sim_soldier_pos[rear_idx] + to_target
	var target_local: Vector2 = (target_pos - u.position).rotated(-ang)

	# Target lateral x should be t_local.x (the rear slot's column along the rear corridor),
	# not the outer flank of the unit:
	assert_almost_eq(target_local.x, t_local.x, 0.1,
		"rear-rank slot arrival routes along rear corridor directly to slot file (%.2f), not to outer flank" % target_local.x)


func test_corridor_to_slot_far_outboard_routes_to_flank_corridor() -> void:
	var u := _make_unit(52, 40)
	u.seed_sim_soldiers()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	# Center front-rank slot (e.g. index 4, at or near center file):
	var slot_idx: int = 4
	var own_slot: Vector2 = slots[slot_idx]
	var ang: float = u.soldier_block_world_angle()
	var rank_pitch: float = u.rank_pitch_wu()
	var spacing: float = u.file_pitch_wu()

	# Position body far outboard (4 file spacings laterally toward flank) and behind the rank:
	var t_local: Vector2 = (own_slot - u.position).rotated(-ang)
	var flank_sign: float = 1.0 if t_local.x >= 0.0 else -1.0
	var p_local: Vector2 = Vector2(t_local.x + flank_sign * spacing * 4.0, t_local.y + rank_pitch * 0.6)
	u._sim_soldier_pos[slot_idx] = u.position + p_local.rotated(ang)

	var to_target: Vector2 = SoldierBodies._corridor_to_slot(u, slot_idx, own_slot, u.soldiers)
	var target_pos: Vector2 = u._sim_soldier_pos[slot_idx] + to_target
	var target_local: Vector2 = (target_pos - u.position).rotated(-ang)

	# The target lateral position must route to the outer flank corridor, NOT straight to t_local.x:
	var dx_to_slot: float = absf(target_local.x - t_local.x)
	assert_true(dx_to_slot > spacing * 1.5,
		"a body far outboard from an interior slot (4 spacings away) must route via flank corridor (dx=%.2f), not cut through standing ranks" % dx_to_slot)


func test_corridor_to_slot_marching_moderate_lag_routes_directly() -> void:
	var u := _make_unit(53, 40)
	u.state = Unit.State.MOVING
	u._approach_velocity = u.facing * u.move_speed   # marching actively
	u.seed_sim_soldiers()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var slot_idx: int = 4
	var own_slot: Vector2 = slots[slot_idx]
	var ang: float = u.soldier_block_world_angle()
	var rank_pitch: float = u.rank_pitch_wu()
	var spacing: float = u.file_pitch_wu()

	# Displace body by 1.8 depth and 0.9 spacing (hypot = 2.01 > 1.5 * spacing, escaping the
	# unconditional radial check; lateral offset 0.9 <= spacing * 1.0 is within the marching
	# file-crossing threshold, so the marching gate does not trigger):
	var t_local: Vector2 = (own_slot - u.position).rotated(-ang)
	var flank_sign: float = 1.0 if t_local.x >= 0.0 else -1.0
	var p_local: Vector2 = Vector2(t_local.x + flank_sign * spacing * 0.9, t_local.y + rank_pitch * 1.8)
	u._sim_soldier_pos[slot_idx] = u.position + p_local.rotated(ang)

	var to_target: Vector2 = SoldierBodies._corridor_to_slot(u, slot_idx, own_slot, u.soldiers)
	var target_pos: Vector2 = u._sim_soldier_pos[slot_idx] + to_target
	var target_local: Vector2 = (target_pos - u.position).rotated(-ang)

	# Under marching, remaining within min_file_spacing (spacing * 1.0) routes directly to own slot:
	assert_almost_eq(target_local.x, t_local.x, 0.1,
		"a marching body with moderate file lag must walk direct (%.2f), not trigger a flank detour" % target_local.x)


func test_corridor_to_slot_stationary_moderate_lag_routes_via_corridor() -> void:
	var u := _make_unit(54, 40)
	u.state = Unit.State.IDLE
	u._approach_velocity = Vector2.ZERO   # stationary drill/reform
	u.seed_sim_soldiers()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var slot_idx: int = 4
	var own_slot: Vector2 = slots[slot_idx]
	var ang: float = u.soldier_block_world_angle()
	var rank_pitch: float = u.rank_pitch_wu()
	var spacing: float = u.file_pitch_wu()

	# Identical displacement (1.8 depth, 0.9 spacing):
	var t_local: Vector2 = (own_slot - u.position).rotated(-ang)
	var flank_sign: float = 1.0 if t_local.x >= 0.0 else -1.0
	var p_local: Vector2 = Vector2(t_local.x + flank_sign * spacing * 0.9, t_local.y + rank_pitch * 1.8)
	u._sim_soldier_pos[slot_idx] = u.position + p_local.rotated(ang)

	var to_target: Vector2 = SoldierBodies._corridor_to_slot(u, slot_idx, own_slot, u.soldiers)
	var target_pos: Vector2 = u._sim_soldier_pos[slot_idx] + to_target
	var target_local: Vector2 = (target_pos - u.position).rotated(-ang)

	# Under stationary conditions, exceeding (depth * 0.5, spacing * 0.5) routes via flank corridor:
	var dx_to_slot: float = absf(target_local.x - t_local.x)
	assert_true(dx_to_slot > spacing * 1.0,
		"a stationary reform body exceeding stationary thresholds must route via corridor (dx=%.2f), not cut through standing ranks" % dx_to_slot)


func test_corridor_to_slot_monotonic_scaling_routes_direct() -> void:
	var u := _make_unit(55, 60)
	u.seed_sim_soldiers()
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var slot_idx: int = 0
	var own_slot: Vector2 = slots[slot_idx]
	var ang: float = u.soldier_block_world_angle()
	var rank_pitch: float = u.rank_pitch_wu()
	var spacing: float = u.file_pitch_wu()

	# Place body in the same quadrant with inward contraction displacement:
	var t_local: Vector2 = (own_slot - u.position).rotated(-ang)
	var p_local: Vector2 = Vector2(t_local.x * 1.5, t_local.y * 1.5)
	u._sim_soldier_pos[slot_idx] = u.position + p_local.rotated(ang)

	var to_target: Vector2 = SoldierBodies._corridor_to_slot(u, slot_idx, own_slot, u.soldiers)
	var target_pos: Vector2 = u._sim_soldier_pos[slot_idx] + to_target
	var target_local: Vector2 = (target_pos - u.position).rotated(-ang)

	assert_almost_eq(target_local.x, t_local.x, 0.1,
		"monotonic quadrant contraction must route directly to slot, not detour via flank")
	assert_almost_eq(target_local.y, t_local.y, 0.1,
		"monotonic quadrant contraction must route directly to slot y")







