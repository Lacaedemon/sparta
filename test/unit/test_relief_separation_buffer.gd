extends GutTest
## Regression guard for the relief-separation exemption's clearing buffer
## (UnitRelief.update): a live battle, driven tick by tick through a real
## line-relief swap, asserting on the actual soldier-body positions rather
## than just the coarse regiment-center distance the old bug hid behind.
##
## SoldierSteering skips separation for every soldier-body pair between the
## relieving pair while Order.friendly_target is armed (the swap link), so
## the exemption is all-or-nothing across the two whole regiments. If
## UnitRelief.update clears that link based only on the regiments' CENTER
## distance and each type's flat separation_radius, a wide/loose-order
## block's soldiers can still be well within each other's bodies when
## separation snaps back on for the entire pair at once -- the chaotic
## swirl this test guards against. The fix instead adds each unit's own
## soldier_block_extent() (the same reach the render/shadow already size
## off), so the clearing distance actually accounts for how far the blocks
## themselves extend, not just their type's fixed collision radius.


func _spawn_battle() -> Node:
	Replay.forced_seed = 12345   # the standard 5v5 showcase spawn, before add_child
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	return battle


func _unit_by_uid(battle: Node, uid: int) -> Unit:
	for node in battle.get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.uid == uid:
			return u
	return null


## Closest center-to-center distance between any of unit_a's live soldier bodies
## and any of unit_b's -- the ground truth for "are the two blocks actually clear
## of each other", independent of the regiments' own center-distance math.
func _min_body_distance(unit_a: Unit, unit_b: Unit) -> float:
	var best := INF
	for pa in unit_a._sim_soldier_pos:
		for pb in unit_b._sim_soldier_pos:
			best = minf(best, pa.distance_to(pb))
	return best


func test_relief_exemption_clears_only_once_soldier_bodies_are_actually_clear() -> void:
	var battle := _spawn_battle()
	for _k in range(10):
		await get_tree().physics_frame

	# uid 0 and uid 1 are adjacent team-0 regiments in the standard spawn (Spearmen,
	# Infantry) -- a realistic line-relief pairing. uid 5 is team 1's opposite-flank
	# counterpart: give the tired unit a real live foe before the swap, exactly as
	# Battle only ever arms a relief on a unit already in contact (see
	# Battle._apply_order_cmd) -- with no foe, UnitRelief.begin instead walks the
	# reliever onto the tired unit's now-vacated spot, which never separates the pair.
	var unit_a: Unit = _unit_by_uid(battle, 0)
	var unit_b: Unit = _unit_by_uid(battle, 1)
	var foe: Unit = _unit_by_uid(battle, 5)
	assert_not_null(unit_a, "found unit uid 0")
	assert_not_null(unit_b, "found unit uid 1")
	assert_not_null(foe, "found unit uid 5")
	if unit_a == null or unit_b == null or foe == null:
		return
	unit_b.target_enemy = foe
	# Put the reliever right on top of the tired unit -- the moment mid-swap when the
	# blocks are actually overlapping (a real relief closes this gap during the pass-
	# through), so the test exercises the case the buffer exists for instead of two
	# blocks that were never close enough to interpenetrate in the first place.
	unit_a.position = unit_b.position
	unit_a.seed_sim_soldiers()

	var relief_order := Order.new_relief(unit_b.uid)
	unit_a.set_current_order(relief_order)
	UnitRelief.begin(unit_a, unit_b, relief_order)

	assert_eq(unit_a.current_order.friendly_target, unit_b, "relief exemption should be armed")
	assert_eq(unit_a.target_enemy, foe, "the reliever takes over the tired unit's fight")

	var body_radius_sum: float = unit_a.soldier_body_radius() + unit_b.soldier_body_radius()
	var exemption_cleared_at_tick: int = -1
	var ceiling: int = battle.current_tick() + 1200

	while battle.current_tick() < ceiling:
		await battle.get_tree().physics_frame
		if unit_a.current_order == null or unit_a.current_order.friendly_target == null:
			exemption_cleared_at_tick = battle.current_tick()
			break

	assert_gt(exemption_cleared_at_tick, -1, "relief exemption should eventually clear")
	if exemption_cleared_at_tick == -1:
		return

	# The real invariant the buffer exists for: once the exemption is gone and
	# separation resumes for every soldier-body pair between the two regiments at
	# once, none of those pairs may already be interpenetrating -- otherwise every
	# overlapping pair gets shoved apart on the same tick, the chaotic swirl.
	var min_dist: float = _min_body_distance(unit_a, unit_b)
	assert_gt(min_dist, body_radius_sum,
			"no soldier body should still overlap another when separation resumes (min dist %.1f, body radii sum %.1f)"
					% [min_dist, body_radius_sum])


func test_relief_interruptible_on_dead() -> void:
	## Verify that relief exemption clears immediately if the partner dies.
	var battle := _spawn_battle()
	for _k in range(10):
		await get_tree().physics_frame

	var unit_a: Unit = _unit_by_uid(battle, 0)
	var unit_b: Unit = _unit_by_uid(battle, 1)
	assert_not_null(unit_a, "found unit uid 0")
	assert_not_null(unit_b, "found unit uid 1")
	if unit_a == null or unit_b == null:
		return

	var relief_order := Order.new_relief(unit_b.uid)
	unit_a.set_current_order(relief_order)
	UnitRelief.begin(unit_a, unit_b, relief_order)
	assert_eq(unit_a.current_order.friendly_target, unit_b, "relief should be armed")

	unit_b.state = Unit.State.DEAD
	UnitRelief.update(unit_a)

	assert_null(unit_a.current_order.friendly_target, "exemption should clear when partner dies")


func test_self_relief_refused() -> void:
	## Verify that a unit can't relieve itself (no-op).
	var battle := _spawn_battle()
	for _k in range(10):
		await get_tree().physics_frame

	var unit_a: Unit = _unit_by_uid(battle, 0)
	assert_not_null(unit_a, "found unit uid 0")
	if unit_a == null:
		return

	var relief_order := Order.new_relief(unit_a.uid)
	UnitRelief.begin(unit_a, unit_a, relief_order)

	assert_null(relief_order.friendly_target, "self-relief should not arm exemption")
