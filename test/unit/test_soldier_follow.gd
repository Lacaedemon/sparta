extends GutTest
## SoldierBodies.couple: the phase-5 soldier->regiment coupling that slides a regiment's
## center toward its soldiers' centroid at a bounded velocity (never a snap). Pins: it never
## teleports (the step is capped), it converges onto the body centroid without overshoot,
## and it is silent when the bodies already sit on their slots (so a clean march isn't
## double-counted). Also pins the jog-speed cap that SoldierBodies.step() applies to idle
## units so frontage reshaping and formation changes never snap or sprint.

const DELTA: float = 1.0 / 60.0


func _make_unit(n: int = 60) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	u.seed_sim_soldiers()   # bodies on their slots, at rest
	return u


func _drift(u: Unit) -> Vector2:
	# body centroid - slot centroid, the quantity couple() drives to zero.
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var bc := Vector2.ZERO
	var sc := Vector2.ZERO
	for i in range(slots.size()):
		bc += u._sim_soldier_pos[i]
		sc += slots[i]
	return (bc - sc) / float(slots.size())


func test_couple_never_teleports() -> void:
	var u := _make_unit()
	# Shove every body far off formation, so the drift is huge.
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(1000.0, 0.0)
	var before: Vector2 = u.position
	SoldierBodies.couple(u, DELTA)
	var moved: float = u.position.distance_to(before)
	assert_lt(moved, Unit.MAX_FOLLOW_SPEED * DELTA + 1e-4,
			"the center moves at most MAX_FOLLOW_SPEED*delta -- a bounded velocity, never a snap")
	assert_gt(moved, 0.0, "but it does follow the bodies")


func test_couple_converges_without_overshoot() -> void:
	var u := _make_unit()
	# Displace bodies by a modest, fully-recoverable amount and hold them there.
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(8.0, 0.0)
	var prev: float = _drift(u).length()
	var start: float = prev
	for _step in range(120):
		SoldierBodies.couple(u, DELTA)
		var d: float = _drift(u).length()
		assert_lte(d, prev + 1e-5, "drift never grows -- no overshoot/oscillation")
		prev = d
	assert_lt(prev, start * 0.05, "the center converges onto the body centroid")


func test_couple_is_silent_on_formation() -> void:
	var u := _make_unit()
	# Bodies seeded exactly on their slots -> zero drift -> a clean march isn't deflected.
	var before: Vector2 = u.position
	SoldierBodies.couple(u, DELTA)
	assert_almost_eq(u.position.x, before.x, 1e-5, "no drift -> no follow (march-silent)")
	assert_almost_eq(u.position.y, before.y, 1e-5, "no drift -> no follow (march-silent)")


func test_couple_weights_drift_toward_engaged_bodies_while_fighting() -> void:
	# While engaged, SoldierEnemyContact only resists the engaged front rank -- so coupling
	# must weight the drift toward those bodies specifically, not dilute it across the whole
	# regiment (whose unengaged bulk stays glued to its own, still-advancing slot).
	var u := _make_unit()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)   # arms the engaged-tier latch is_engaged() reads
	var idxs: PackedInt32Array = u.engaged_soldier_indices(u.soldiers)
	assert_gt(idxs.size(), 0, "some soldiers are engaged while fighting")
	assert_lt(idxs.size(), u.soldiers,
			"and not the whole regiment -- there's an unengaged bulk to dilute against")
	# Displace ONLY the engaged bodies off their slots by a uniform amount; the unengaged
	# bulk stays exactly on slot (zero drift), so a whole-regiment average would dilute this
	# down toward zero as the unengaged count grows.
	for i in idxs:
		u._sim_soldier_pos[i] += Vector2(8.0, 0.0)
	SoldierBodies.couple(u, DELTA)
	# The engaged-only average drift is exactly (8, 0) regardless of idxs.size() (every
	# displaced body moved the same amount), so the follow step is drift * FOLLOW_RATE * delta.
	var expected: float = 8.0 * Unit.FOLLOW_RATE * DELTA
	assert_almost_eq(u.position.x, expected, 0.01,
			"coupling follows the engaged-only average, undiluted by the unengaged bulk")
	assert_almost_eq(u.position.y, 0.0, 1e-5)


func test_couple_pairs_squared_engaged_bodies_via_canonical_perimeter() -> void:
	# couple()'s engaged-centroid sum has two branches: the NORMAL-formation shortcut (sums
	# straight over the contiguous canonical range) and the Square/Schiltron branch (delegates
	# to canonical_target_slot_indices' live-perimeter selection). Exercise the Square branch
	# directly so it isn't only covered incidentally by the non-Square tests above.
	var u := _make_unit(24)
	u.set_formation(Unit.FORMATION_SQUARE)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	assert_true(u.in_square(), "sanity: the unit is in Square formation")
	assert_true(u.is_engaged(), "sanity: the unit is engaged")
	# Uniformly displace the whole regiment -- regardless of exactly which subset the live-
	# perimeter selection picks, a uniform shove moves every candidate body by the same
	# amount, so the resulting follow step is unambiguously in that direction and bounded.
	var before: Vector2 = u.position
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(8.0, 0.0)
	SoldierBodies.couple(u, DELTA)
	var moved: Vector2 = u.position - before
	assert_gt(moved.x, 0.0, "coupling follows the displaced perimeter bodies -- moves toward +x")
	# The live-perimeter selection (a heap over farthest-from-centroid, not an exact geometric
	# ring) isn't perfectly symmetric for every soldier count, so a small cross-axis component
	# is expected -- assert it stays small relative to the dominant x displacement, not exactly
	# zero.
	assert_lt(absf(moved.y), absf(moved.x) * 0.5,
		"no more than a modest lateral drift from a purely-x displacement")
	assert_lt(moved.length(), Unit.MAX_FOLLOW_SPEED * DELTA + 1e-4,
		"still a bounded follow step, never a snap, even through the Square branch")


func test_couple_still_averages_whole_regiment_when_not_engaged() -> void:
	# The friendly-collision / non-combat path is unchanged: with no engaged soldiers, the
	# fallback still averages drift over every body, exactly as before this fix.
	var u := _make_unit()
	assert_false(u.is_engaged(), "a fresh idle unit is not engaged")
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(8.0, 0.0)
	SoldierBodies.couple(u, DELTA)
	var expected: float = 8.0 * Unit.FOLLOW_RATE * DELTA
	assert_almost_eq(u.position.x, expected, 0.01,
			"uniform displacement of every body still yields the same whole-regiment average")


func test_couple_position_anchor_reaches_less_deep_than_the_old_selection_after_front_rank_casualties() -> void:
	# `position` should read off the regiment's leading edge, not an average a
	# casualty-thinned rear can pull around. A fixed-SIZE engaged budget reaches deeper into
	# the block once the true front rank is gone -- the same array splice SoldierMelee.reap()
	# performs on a real casualty -- so the survivors that fill that budget sit farther back
	# than before. couple() now anchors a settled, engaged, non-Square regiment on
	# Unit.ANCHOR_RANKS worth of near-front soldiers instead of the wider Unit.ENGAGED_RANKS
	# depth, so after the front rank falls it reaches less deep into the survivors than the
	# old, wider selection would -- read directly off the still-existing engaged_soldier_indices
	# (unchanged, still used elsewhere), not re-implemented, purely to show the contrast.
	var u := _make_unit(120)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	assert_true(u.is_engaged(), "sanity: the unit is engaged")
	assert_false(u.in_square(), "sanity: NORMAL formation -- the branch this fix narrows")
	var files: int = u.formation_files(u.soldiers)
	# Wipe out the whole front rank (indices 0..files-1 in the at-rest canonical grid) --
	# remove from the tail of the doomed range down so earlier removals don't shift the
	# indices still to be removed.
	for i in range(files - 1, -1, -1):
		u._sim_soldier_pos.remove_at(i)
	u.soldiers = u._sim_soldier_pos.size()
	var n: int = u.soldiers
	var old_indices: PackedInt32Array = u.engaged_soldier_indices(n, false)
	var new_indices: PackedInt32Array = u.near_front_soldier_indices(n)
	assert_gt(old_indices.size(), new_indices.size(),
			"sanity: the old selection is still the wider of the two")
	# "How far forward" each selection reaches: the mean of the same forward-projection score
	# UnitFormation.live_front_indices selects by (higher = closer to the enemy) -- NOT
	# distance from `position`, which sits at the whole block's geometric CENTRE (block_slots
	# centres the grid), so it isn't monotonic with depth: a soldier at the block's own
	# mid-depth can sit closer to `position` than one nearer the true front, understating a
	# wide selection's reach into the survivors if compared by raw distance instead.
	var world_angle: float = u.facing.angle() + PI * 0.5 + u._formation_angle
	var forward: Vector2 = Vector2(0.0, -1.0).rotated(world_angle)
	var old_forwardness := 0.0
	for i in old_indices:
		old_forwardness += (u._sim_soldier_pos[i] - u.position).dot(forward)
	old_forwardness /= float(old_indices.size())
	var new_forwardness := 0.0
	for i in new_indices:
		new_forwardness += (u._sim_soldier_pos[i] - u.position).dot(forward)
	new_forwardness /= float(new_indices.size())
	assert_gt(new_forwardness, old_forwardness,
			("the narrowed anchor's selection sits measurably closer to the true front " +
			"(new %.1f vs old %.1f) once the true front rank is gone -- the old, wider " +
			"selection is dragged rearward by the deeper rank it has to include") %
			[new_forwardness, old_forwardness])


func test_couple_determinism() -> void:
	var a := _make_unit()
	var b := _make_unit()
	for i in range(a._sim_soldier_pos.size()):
		a._sim_soldier_pos[i] += Vector2(5.0, -3.0)
		b._sim_soldier_pos[i] += Vector2(5.0, -3.0)
	for _s in range(10):
		SoldierBodies.couple(a, DELTA)
		SoldierBodies.couple(b, DELTA)
	assert_almost_eq(a.position.x, b.position.x, 1e-6, "identical inputs -> identical follow")
	assert_almost_eq(a.position.y, b.position.y, 1e-6)


# --- lateral pairing (SoldierBodies.step's engaged/canonical pairing) --------------------
# engaged_soldier_indices()/canonical_target_slot_indices() used to pair by raw array rank
# (the k-th live-selected index against the k-th canonical index), which tracks
# casualty-reindexed spawn order rather than a body's actual physical position. Fixed by
# sorting both sides by lateral position (Unit.pairing_sort_indices) before pairing.

func test_soldier_bodies_step_pairs_engaged_bodies_by_lateral_position_not_raw_rank() -> void:
	# A 3-soldier single-rank unit is small enough that engaged_soldier_indices trivially
	# selects every soldier in raw ascending-index order ([0, 1, 2], regardless of live
	# position -- the exact `target_count >= n` early return in live_front_indices). Swap the
	# live positions of the two end bodies -- body 0 now stands where the canonical grid's
	# RIGHTMOST file belongs (slots[2]) and body 2 stands where the LEFTMOST file belongs
	# (slots[0]) -- the same shape a casualty-driven array compaction produces: a body's
	# array index no longer tracks its physical side of the line.
	var u := _make_unit(3)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	var slots: PackedVector2Array = u.soldier_world_slots(3)
	assert_eq(slots.size(), 3, "sanity: a single rank of 3")
	assert_eq(u.engaged_soldier_indices(3), PackedInt32Array([0, 1, 2]),
		"sanity: all 3 soldiers are engaged, selected in raw ascending-index order")
	u._sim_soldier_pos[0] = slots[2]
	u._sim_soldier_pos[1] = slots[1]
	u._sim_soldier_pos[2] = slots[0]
	# Under the OLD raw-rank pairing this would have been engaged_targets = {0: slots[0],
	# 1: slots[1], 2: slots[2]} -- handing body 0 (standing at slots[2]) a target on the
	# OPPOSITE end of the line, and likewise for body 2, so both would accelerate hard toward
	# the far side every tick. The FIXED pairing sorts by actual lateral position first, so
	# body 0 (farthest right) pairs with the canonical rightmost slot (slots[2], where it
	# already stands) and body 2 (farthest left) pairs with slots[0] (ditto) -- both are
	# already exactly on their own corrected target, so neither should accelerate at all.
	for _s in range(10):
		SoldierBodies.step(u, DELTA)
		assert_lt(u._sim_body_vel[0].length(), 0.5,
			"body 0 is already on its own (corrected) lateral target -- no arrival pull")
		assert_lt(u._sim_body_vel[2].length(), 0.5,
			"body 2 is already on its own (corrected) lateral target -- no arrival pull")
	assert_almost_eq(u._sim_soldier_pos[0].x, slots[2].x, 0.1,
		"body 0 held its corrected position rather than being dragged to slots[0]")
	assert_almost_eq(u._sim_soldier_pos[2].x, slots[0].x, 0.1,
		"body 2 held its corrected position rather than being dragged to slots[2]")


func test_soldier_bodies_step_still_pairs_correctly_when_already_in_lateral_order() -> void:
	# The well-behaved (no-casualty) case is unaffected: bodies already seeded onto their own
	# slots stay exactly there, since the sort is a no-op when live order already matches
	# lateral order (see UnitFormation.sort_indices_by_projection).
	var u := _make_unit(3)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	for _s in range(10):
		SoldierBodies.step(u, DELTA)
		for i in range(3):
			assert_lt(u._sim_body_vel[i].length(), 0.5,
				"body %d is already on its own slot -- no arrival pull" % i)


# --- rate-limited engaged-target reassignment --------------------------------------------
# An earlier canonical-slot fix stopped a live-engaged body's target from being a stale
# post-casualty array index, but the PAIRING itself was still recomputed fresh every tick --
# so a body's target could still relocate by tens of world units the instant
# engaged_soldier_indices()'s live-position selection jostled by a soldier-width. These pin
# that the pairing is now held fixed for SoldierBodies.ENGAGED_TARGET_REASSIGN_TICKS instead
# of being recomputed every tick, except when a casualty invalidates it early.

func test_engaged_target_pairing_holds_fixed_within_the_reassignment_interval() -> void:
	var u := _make_unit(6)
	u.get_parent().remove_child(u)   # detach: no _physics_process interference while we await
	# physics frames below to advance Engine.get_physics_frames() -- SoldierBodies.step() is
	# driven by hand, exactly like every other test in this file.
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	assert_eq(u.engaged_soldier_indices(6).size(), 6, "sanity: all 6 are engaged")
	SoldierBodies.step(u, DELTA)
	var first_engaged: PackedInt32Array = u._engaged_target_pairing_engaged.duplicate()
	var first_canonical: PackedInt32Array = u._engaged_target_pairing_canonical.duplicate()
	assert_eq(first_engaged.size(), 6, "the first call computes and records a pairing")
	# Swap two live body positions -- if the pairing were recomputed fresh every tick, this
	# would change which canonical slot each swapped body pairs with.
	var tmp: Vector2 = u._sim_soldier_pos[0]
	u._sim_soldier_pos[0] = u._sim_soldier_pos[5]
	u._sim_soldier_pos[5] = tmp
	for _s in range(SoldierBodies.ENGAGED_TARGET_REASSIGN_TICKS - 5):
		await get_tree().physics_frame
		SoldierBodies.step(u, DELTA)
		assert_eq(u._engaged_target_pairing_engaged, first_engaged,
			"the pairing stays fixed within the reassignment interval, even as live positions moved")
		assert_eq(u._engaged_target_pairing_canonical, first_canonical)


func test_engaged_target_pairing_recomputes_once_the_interval_elapses() -> void:
	var u := _make_unit(6)
	u.get_parent().remove_child(u)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	SoldierBodies.step(u, DELTA)
	var first_engaged: PackedInt32Array = u._engaged_target_pairing_engaged.duplicate()
	var tmp: Vector2 = u._sim_soldier_pos[0]
	u._sim_soldier_pos[0] = u._sim_soldier_pos[5]
	u._sim_soldier_pos[5] = tmp
	for _s in range(SoldierBodies.ENGAGED_TARGET_REASSIGN_TICKS + 2):
		await get_tree().physics_frame
		SoldierBodies.step(u, DELTA)
	assert_ne(u._engaged_target_pairing_engaged, first_engaged,
		"once the interval elapses, the pairing recomputes and reflects the swapped positions'"
		+ " new lateral order")


func test_engaged_target_pairing_recomputes_immediately_after_a_casualty() -> void:
	# A casualty splices the per-soldier arrays (SoldierMelee.reap), so a cached pairing's
	# indices no longer mean the same bodies -- must recompute right away, not wait out the
	# interval, regardless of how recently the pairing was (re)computed.
	var u := _make_unit(6)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	SoldierBodies.step(u, DELTA)
	assert_eq(u._engaged_target_pairing_engaged.size(), 6, "sanity: the first pairing covers all 6 bodies")
	u._sim_soldier_hp[0] = 0.0
	SoldierMelee.reap(u, u)
	assert_eq(u.soldiers, 5, "sanity: one soldier fell")
	SoldierBodies.step(u, DELTA)   # same physics frame -- no await needed
	assert_eq(u._engaged_target_pairing_engaged.size(), 5,
		"the pairing recomputes immediately against the post-casualty count, not on the old cache")


func test_engaged_target_pairing_resets_on_full_disengage_then_recomputes_on_re_engage() -> void:
	# A disengage must invalidate the cached pairing -- otherwise a re-engagement within the
	# reassignment interval (no casualty in between to force a recompute) would reuse a pairing
	# built for a completely different set of engaged bodies from the prior clash, mismatching
	# which bodies get a canonical-slot target vs. their own slot.
	var u := _make_unit(6)
	u.get_parent().remove_child(u)   # detach: no _physics_process interference while we await
	# physics frames below -- also required so engaged_soldier_indices()'s own per-(frame,
	# count) cache doesn't serve a stale engaged/unengaged read across same-frame step() calls.
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	SoldierBodies.step(u, DELTA)   # engage: computes and caches the pairing
	assert_eq(u._engaged_target_pairing_engaged.size(), 6, "sanity: the first pairing covers all 6 bodies")
	# Fully disengage.
	u._engaged_linger = 0.0
	assert_false(u.is_engaged(), "sanity: the unit is no longer engaged")
	await get_tree().physics_frame
	SoldierBodies.step(u, DELTA)   # unengaged tick
	assert_true(u._engaged_target_pairing_engaged.is_empty(),
		"disengaging clears the cached pairing rather than leaving it stale")
	# Re-engage immediately -- same reassignment interval, no casualty in between.
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	await get_tree().physics_frame
	SoldierBodies.step(u, DELTA)
	assert_eq(u._engaged_target_pairing_engaged.size(), 6,
		"re-engaging forces a fresh pairing instead of reusing the stale cache from the prior" +
		" engagement")


func test_unengaged_targets_track_the_units_own_movement_even_while_pairing_is_cached() -> void:
	# Regression guard: the target-slot cache must hold only the engaged-body <-> canonical-
	# slot PAIRING, not a whole resolved target_slots array -- otherwise every unengaged
	# body's target freezes at wherever the unit stood on the last reassignment tick, and
	# stops tracking the unit's own march until the cache refreshes (the exact "snap" this
	# feature exists to prevent, just for the unengaged majority instead of the engaged rank).
	var u := _make_unit()   # default 60 -- large enough to leave a genuine unengaged bulk
	u.get_parent().remove_child(u)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(DELTA)
	var engaged: PackedInt32Array = u.engaged_soldier_indices(u.soldiers)
	assert_gt(engaged.size(), 0, "sanity: some soldiers are engaged")
	assert_lt(engaged.size(), u.soldiers, "sanity: an unengaged bulk exists to test against")
	var unengaged_idx: int = -1
	for i in range(u.soldiers):
		if not engaged.has(i):
			unengaged_idx = i
			break
	assert_ne(unengaged_idx, -1, "sanity: found an unengaged body")
	SoldierBodies.step(u, DELTA)   # first call: computes and caches the engaged pairing
	assert_lt(u._sim_body_vel[unengaged_idx].length(), 0.5,
		"sanity: the unengaged body starts at rest on its own slot")
	# March the unit forward -- its formation slots (soldier_world_slots) translate with it,
	# but the unengaged body's own live position hasn't moved yet.
	u.position += Vector2(50.0, 0.0)
	SoldierBodies.step(u, DELTA)   # still well within the reassignment interval
	# The arrival velocity is bounded by the body's own acceleration (never a snap, per this
	# repo's "no top-down gimmicks" design), so a single tick only produces a small nonzero
	# step -- but a genuinely FROZEN (stale pre-march) target would produce exactly zero, since
	# the body was sitting exactly on that old slot before the march. Any real pull confirms
	# the target updated to the post-march slot this tick.
	assert_gt(u._sim_body_vel[unengaged_idx].x, 0.1,
		"the unengaged body's target tracked the unit's march THIS tick -- not frozen at the" +
		" pre-march slot from the last pairing reassignment")


# --- integration: friendly regiments separate from the soldier layer ----------

func _block(uid: int, team: int, n: int, pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.facing = Vector2.DOWN
	u.state = Unit.State.IDLE
	u.position = pos
	u.seed_sim_soldiers()
	return u


## One full soldier sub-tick, exactly as Battle._on_soldier_tick sequences it.
func _soldier_tick(units: Array, frame: int) -> void:
	SoldierSteering.accumulate(units, frame)
	Unit.step_all_sim_soldiers(units, DELTA)
	Unit.couple_all_sim_soldiers(units, DELTA)


## The closest cross-regiment soldier distance (the worst overlap between two blocks).
func _min_cross(a: Unit, b: Unit) -> float:
	var m := INF
	for pa: Vector2 in a._sim_soldier_pos:
		for pb: Vector2 in b._sim_soldier_pos:
			m = minf(m, pa.distance_to(pb))
	return m


func test_friendly_regiments_separate_via_soldier_layer() -> void:
	# Two heavily-overlapping idle friendlies, with NO regiment-circle separation (it skips
	# friendlies now). Running the soldier sub-tick (steering -> bodies -> coupling) pushes
	# the interpenetrating soldiers apart and slides the centers off each other -- friendly
	# collision emerges entirely from the soldier layer.
	var a := _block(0, 0, 12, Vector2(0.0, 0.0))
	var b := _block(1, 0, 12, Vector2(4.0, 0.0))   # blocks heavily overlap
	var start_gap: float = a.position.distance_to(b.position)
	var start_cross: float = _min_cross(a, b)
	# Bodies now separate under bounded arrival/steering acceleration rather than an instant
	# velocity snap, so give the sub-tick more frames to push the blocks apart. As the blocks
	# slide past each other the two closest soldiers stay near contact, so the dominant
	# separation signal is the centres sliding off (a large gap growth); the min cross-distance
	# grows more modestly.
	for f in range(1200):
		_soldier_tick([a, b], f + 1)
	assert_gt(_min_cross(a, b), start_cross + 0.5,
			"the interpenetrating soldiers are pushed apart")
	assert_gt(a.position.distance_to(b.position), start_gap + 2.0,
			"and the regiment centers slide substantially off each other")
	assert_lt(a.position.x, b.position.x, "they fan apart along their offset, not through each other")


func test_soldier_layer_separation_is_deterministic() -> void:
	var a1 := _block(0, 0, 12, Vector2(0.0, 0.0))
	var b1 := _block(1, 0, 12, Vector2(4.0, 0.0))
	var a2 := _block(0, 0, 12, Vector2(0.0, 0.0))
	var b2 := _block(1, 0, 12, Vector2(4.0, 0.0))
	for f in range(80):
		_soldier_tick([a1, b1], f + 1)
		_soldier_tick([a2, b2], f + 1)
	assert_almost_eq(a1.position.x, a2.position.x, 1e-5, "identical runs separate identically (x)")
	assert_almost_eq(a1.position.y, a2.position.y, 1e-5, "identical runs separate identically (y)")
	assert_almost_eq(b1.position.x, b2.position.x, 1e-5, "and the partner too")


# --- jog-speed cap during idle reshape (frontage changes, centre pivots) ------

func test_idle_soldier_bodies_capped_at_jog_speed() -> void:
	# Displace bodies far from their slots (simulating a large frontage change) and let the
	# bounded arrival ramp their speed up over many ticks. SoldierBodies.step() must never
	# let any soldier body exceed the unit's own jog_speed when the unit is IDLE — orderly
	# reshape, no sprinting.
	var u := _make_unit()
	u.state = Unit.State.IDLE
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 0.0)   # far from slots
	for _s in range(240):   # ~4 s: long enough for arrival to reach top speed
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			assert_lte(u._sim_body_vel[i].length(), u.jog_speed + 1e-4,
					"idle soldier speed is capped at jog_speed during reshape")


func test_moving_soldier_bodies_not_speed_capped() -> void:
	# A marching unit's bodies must be allowed to exceed jog_speed so they keep up with
	# moving slots: the march feed-forward is already at full jog, and the arrival term
	# toward a far lateral slot stacks on top of it. The jog cap must NOT apply when
	# state == MOVING, so the combined speed can exceed jog. Ramp over several ticks so
	# the bounded arrival builds the lateral component up.
	var u := _make_unit()
	u.state = Unit.State.MOVING
	var march := Vector2(0.0, u.jog_speed)             # full jog already from march
	u._approach_velocity = march
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 0.0)   # large lateral offset adds to march speed
	var any_above_cap := false
	for _s in range(240):   # ~4 s: let the bounded arrival ramp the lateral term well in
		u.position += march * DELTA                    # slots translate with the march...
		u._approach_velocity = march                   # ...and the feed-forward tracks it
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			# march (jog) downfield + lateral arrival (up to jog) toward the slot combine
			# to well above jog overall, which a capped body could never reach.
			if u._sim_body_vel[i].length() > u.jog_speed + 1.0:
				any_above_cap = true
	assert_true(any_above_cap, "marching bodies can exceed jog speed — no cap while MOVING")


# --- backward-walk speed cap during a maneuver --------------------------------

## Set up an idle unit whose bodies are displaced so arrival pulls every body ALONG the
## given displacement direction, ramp for enough ticks to reach the capped top speed, and
## return the peak body speed along the direction of travel (component of velocity toward
## the slot) seen across the run. The displacement is far enough that the arrival term is
## jog-capped, so the steady-state speed is set by whichever cap applies (forward jog vs.
## backward jog*fraction), not by the arrival's decel taper.
func _peak_speed_along_travel(u: Unit, displace: Vector2) -> float:
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += displace
	var travel: Vector2 = (-displace).normalized()   # slot is opposite the displacement
	var peak := 0.0
	for _s in range(240):   # ~4 s: ramp the bounded arrival up to the capped top speed
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			peak = maxf(peak, u._sim_body_vel[i].dot(travel))
	return peak


func test_backward_moving_body_capped_slower_than_forward() -> void:
	# facing = DOWN. A body whose slot lies BEHIND it (above, -y) must back up against
	# its facing, and the cap slows that to jog_speed * back_speed_fraction. A body whose
	# slot lies AHEAD (below, +y) steps forward and keeps the full jog cap. Same offset
	# magnitude both ways, so the arrival force is identical -- only the cap differs.
	var back_u := _make_unit()
	back_u.state = Unit.State.IDLE
	# Displace bodies DOWN so their slots sit behind (above) them -> they back up.
	var back_peak: float = _peak_speed_along_travel(back_u, Vector2(0.0, 200.0))

	var fwd_u := _make_unit()
	fwd_u.state = Unit.State.IDLE
	# Displace bodies UP so their slots sit ahead (below) them -> they step forward.
	var fwd_peak: float = _peak_speed_along_travel(fwd_u, Vector2(0.0, -200.0))

	assert_almost_eq(fwd_peak, fwd_u.jog_speed, 1e-3,
			"a body stepping forward is capped at the full jog speed")
	assert_almost_eq(back_peak, back_u.jog_speed * back_u.back_speed_fraction, 1e-3,
			"a body backing up is capped to the slower backward pace")
	assert_lt(back_peak, fwd_peak - 1.0,
			"backward motion is meaningfully slower than forward motion")


func test_sideways_body_keeps_full_jog_cap() -> void:
	# facing = DOWN. A body displaced purely sideways (x) moves perpendicular to its
	# facing -- neither forward nor backward -- so it keeps the full jog cap, unslowed.
	var u := _make_unit()
	u.state = Unit.State.IDLE
	var peak: float = _peak_speed_along_travel(u, Vector2(200.0, 0.0))
	assert_almost_eq(peak, u.jog_speed, 1e-3,
			"purely sideways motion keeps the full jog cap (no backward penalty)")


func test_diagonal_backward_body_stays_within_jog_cap() -> void:
	# facing = DOWN. A body whose slot lies behind-and-to-the-side must back up AND sidestep
	# at once, so the arrival produces a velocity with both a backward and a sideways
	# component. Capping the two axes independently could let the combined speed exceed jog;
	# the final limit_length keeps total speed within the jog ceiling, while the backward
	# axis is still slowed so the body isn't simply running at full jog.
	var u := _make_unit()
	u.state = Unit.State.IDLE
	# Displace bodies DOWN-and-RIGHT so their slots sit behind-and-left -> back up + sidestep.
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 200.0)
	var facing := Vector2.DOWN
	# Ramp the bounded arrival up to its capped top speed over several ticks, checking the
	# cap holds every tick (not just after one step, where the body has barely accelerated).
	for _s in range(120):
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			var v: Vector2 = u._sim_body_vel[i]
			assert_lte(v.length(), u.jog_speed + 1e-3,
					"a diagonal backward-and-sideways body stays within the jog ceiling")
			# The backward (against-facing) axis is capped to the slower pace, so the body's
			# reverse speed can't reach the full jog even though it's also sliding sideways.
			var back_speed: float = -v.dot(facing)   # positive = backing up
			assert_lte(back_speed, u.jog_speed * u.back_speed_fraction + 1e-3,
					"and its backward-axis speed is still capped to the slower backward pace")


func test_backward_cap_is_deterministic() -> void:
	var a := _make_unit()
	a.state = Unit.State.IDLE
	var b := _make_unit()
	b.state = Unit.State.IDLE
	var pa: float = _peak_speed_along_travel(a, Vector2(0.0, 200.0))
	var pb: float = _peak_speed_along_travel(b, Vector2(0.0, 200.0))
	assert_almost_eq(pa, pb, 1e-9, "identical setups cap identically -- replay-safe")
