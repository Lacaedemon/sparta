extends GutTest
## March to contact, in a LIVE battle: an off-axis engage turn (a bearing well past
## ENGAGE_TURN_THRESHOLD) abandoned mid-turn when the foe breaks contact used to strand
## _engage_turn_target for good -- SoldierBodies.step's slot-approach term stays frozen
## forever (is_maneuver_turning() gates it), producing a blob/smear instead of a clean
## march resumption. Complements test_march_to_contact_order.gd's bare-unit coverage the
## way test_wheel_battle.gd complements test_wheel.gd: proves the fix in the full
## simulation context, with real soldier bodies actually converging back onto their
## marching slots afterward, not just an internal flag reading zero.

const SETTLE_BUDGET: int = 90


## Mean distance from each live soldier body to its own canonical formation slot -- how far
## the block is from actually standing on its marching grid. Index-aligned (no best-fit
## realignment needed): by the time this is sampled, facing already matches the settled
## turn's target, so the raw slot grid lines up directly.
func _mean_slot_deviation(u: Unit) -> float:
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var bodies: PackedVector2Array = u._sim_soldier_pos
	var n: int = mini(slots.size(), bodies.size())
	if n == 0:
		return 0.0
	var total := 0.0
	for i in range(n):
		total += bodies[i].distance_to(slots[i])
	return total / n


func test_march_to_contact_settles_a_stranded_off_axis_engage_turn_in_a_live_battle() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true   # the hostile never acts on its own -- isolates the mover
	battle.drill_mode = true          # the sim keeps running once the lone hostile is gone
	battle.terrain = []               # flat field: no pathfinding detour to confound the geometry
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 500, "y": 300, "count": 50, "facing": [0, 1]},
		# Due EAST of the mover: a 90-degree bearing off its DOWN facing, well past
		# ENGAGE_TURN_THRESHOLD (75 degrees) -- and close enough to be in melee contact
		# from the very first tick.
		{"team": 1, "type": "Infantry", "x": 530, "y": 300, "count": 12},
	]
	add_child_autofree(battle)
	for _k in range(3):
		await get_tree().physics_frame   # let the armies spawn

	var mover: Unit = null
	var foe: Unit = null
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u == null:
			continue
		if u.team == 0:
			mover = u
		else:
			foe = u
	assert_not_null(mover, "the mover spawned")
	assert_not_null(foe, "the hostile spawned")
	if mover == null or foe == null:
		return

	mover.order_mode = Unit.ORDER_MARCH_TO_CONTACT
	mover.has_move_target = true
	mover.move_target = Vector2(500, 900)   # ahead of its own facing, away from the foe's bearing
	mover.target_enemy = null

	# A few ticks: the off-axis contact engages and the turn begins, but doesn't finish
	# (CONVERSIO_TURN_RATE needs ~15 ticks for a full 90-degree swing).
	for _k in range(5):
		await get_tree().physics_frame
	assert_eq(mover.state, Unit.State.FIGHTING, "sanity: real contact engaged the mover")
	assert_true(mover.is_maneuver_turning(),
		"sanity: the off-axis engage turn is genuinely in progress")

	# The foe breaks contact before the turn completes -- teleported out of range, still
	# alive. MARCH_TO_CONTACT never commits target_enemy, so the resumed-move branch is the
	# only remaining path back to marching.
	foe.position = Vector2(3000, 3000)

	var settled := false
	for _k in range(SETTLE_BUDGET):
		await get_tree().physics_frame
		if not mover.is_maneuver_turning():
			settled = true
			break
	assert_true(settled, "the stranded engage turn settles within budget once contact breaks")
	assert_eq(mover._engage_turn_target, Vector2.ZERO, "...and _engage_turn_target reads zero")

	# The practical symptom, not just the flag: let the bodies run a while longer and confirm
	# they're actually standing near their marching slots -- SoldierBodies.step's
	# slot-approach term genuinely resumed, rather than the block staying smeared forever.
	for _k in range(60):
		await get_tree().physics_frame
	var deviation: float = _mean_slot_deviation(mover)
	assert_lt(deviation, Unit.FORMATION_SPACING * 2.0,
		"soldier bodies converge back onto their marching slots (mean deviation %.2f wu)" % deviation)
