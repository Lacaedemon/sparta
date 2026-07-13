extends GutTest
## Passage of lines (Polybius's triplex acies): distributed relief. When several fresh
## units are ordered onto an engaged friendly line with the group-order distribution
## mode set to DISTRIBUTED, each fresh unit takes over a DIFFERENT tired unit's fight
## instead of every reliever swapping with the one unit clicked. Drives a real,
## in-tree Battle (get_tree().get_nodes_in_group is how the candidate pool is built,
## so a headless _by_uid-only Battle can't exercise this path) rather than asserting
## against an isolated unit.

const BattleScript = preload("res://scripts/Battle.gd")


func after_each() -> void:
	# Free this test's battle before the next test spawns, so units don't linger in
	# the shared "units" group and pollute a later test's group scan. Also unpause --
	# belt-and-suspenders alongside drill_mode below, since a paused tree would stall
	# every later test's own await get_tree().physics_frame.
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


var _battle: Node = null


## Three fresh (IDLE) team-0 units and three engaged (FIGHTING) team-0 units, spread so
## proximity-to-target sorting is unambiguous (no tie distances). Fresh units sit in a
## row well ahead of the tired row -- a real passage-of-lines click would land much
## closer, but the test issues the order directly via _apply_order_cmd rather than
## through SelectionManager's click resolution, so nothing depends on that distance.
## A small "count" keeps each block's footprint narrow, so the wide spacing between
## units comfortably clears unit-level separation and no position drifts before the
## first physics tick this test reads positions after. No team-1 units are spawned --
## engagement state is armed directly (see below) -- so drill_mode must be set, or
## Battle._check_victory sees no opposing team in play and ends the battle (pausing
## the tree) on the very first tick.
func _spawn_line_relief_battle() -> Node:
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": 20, "x": 300, "y": 200},   # fresh 1
		{"team": 0, "type": "Infantry", "count": 20, "x": 600, "y": 200},   # fresh 2
		{"team": 0, "type": "Infantry", "count": 20, "x": 900, "y": 200},   # fresh 3
		{"team": 0, "type": "Infantry", "count": 20, "x": 280, "y": 600},   # tired A -- 320px from tired B
		{"team": 0, "type": "Infantry", "count": 20, "x": 600, "y": 600},   # tired B -- the clicked target
		{"team": 0, "type": "Infantry", "count": 20, "x": 950, "y": 600},   # tired C -- 350px from tired B
	]
	add_child(_battle)
	return _battle


func _units_at(battle: Node, positions: Array) -> Array:
	var out: Array = []
	for pos in positions:
		var found: Unit = null
		for node in battle.get_tree().get_nodes_in_group("units"):
			var u: Unit = node as Unit
			if u != null and u.position.is_equal_approx(pos):
				found = u
				break
		out.append(found)
	return out


func test_distributed_relief_pairs_each_fresh_unit_with_a_different_tired_unit() -> void:
	var battle := _spawn_line_relief_battle()
	await get_tree().physics_frame   # _ready spawns the scenario units

	var found := _units_at(battle, [
		Vector2(300, 200), Vector2(600, 200), Vector2(900, 200),
		Vector2(280, 600), Vector2(600, 600), Vector2(950, 600),
	])
	var fresh1: Unit = found[0]
	var fresh2: Unit = found[1]
	var fresh3: Unit = found[2]
	var tired_a: Unit = found[3]
	var tired_b: Unit = found[4]   # the clicked target
	var tired_c: Unit = found[5]
	for u in found:
		assert_not_null(u, "every scenario unit spawned")

	# Every tired unit is engaged -- a relief target is supposed to be a unit actually
	# holding a fight, not an idle one.
	tired_a.state = Unit.State.FIGHTING
	tired_b.state = Unit.State.FIGHTING
	tired_c.state = Unit.State.FIGHTING

	battle._apply_order_cmd({
		"units": [fresh1.uid, fresh2.uid, fresh3.uid],
		"x": tired_b.position.x, "y": tired_b.position.y,
		"target": tired_b.uid,
		"mode": BattleScript.OrderMode.NORMAL,
		"group_attack": BattleScript.GroupAttackMode.DISTRIBUTED,
	})

	# Proximity to the clicked target (tired_b, distance 0) sorts the candidate pool
	# [tired_b, tired_a (320px), tired_c (350px)]; slot order follows the "units" array
	# passed above, so fresh1 -> tired_b, fresh2 -> tired_a, fresh3 -> tired_c.
	var pairing := {
		fresh1: tired_b,
		fresh2: tired_a,
		fresh3: tired_c,
	}
	for fresh in pairing:
		var tired: Unit = pairing[fresh]
		assert_eq(fresh.current_order.type, Order.Type.RELIEF,
				"%s gets its own RELIEF order" % fresh.unit_name)
		assert_eq(fresh.current_order.friendly_target, tired,
				"%s's swap link points at its own tired partner, not the clicked unit" % fresh.unit_name)
		assert_true(fresh._separation_exempt(tired),
				"the pass-through exemption is armed for %s's pairing" % fresh.unit_name)
		assert_eq(tired.current_order.type, Order.Type.MOVE,
				"%s's tired partner gets a real retreat order" % fresh.unit_name)

	# Every pairing is genuinely distinct -- the whole point of the maneuver.
	var partners := [tired_b, tired_a, tired_c]
	assert_eq(partners.size(), 3, "sanity: three tired units named")
	assert_ne(partners[0], partners[1], "fresh1 and fresh2 relieve different units")
	assert_ne(partners[0], partners[2], "fresh1 and fresh3 relieve different units")
	assert_ne(partners[1], partners[2], "fresh2 and fresh3 relieve different units")


func test_distributed_relief_falls_back_to_single_pair_with_only_one_engaged_candidate() -> void:
	# When only the clicked friendly is actually engaged (the other two "tired" units in
	# this scenario are left IDLE), the candidate pool has exactly one member, so every
	# reliever should behave exactly like the pre-existing FOCUSED path: the first swaps,
	# the rest pile onto its fight -- distributed relief never manufactures a swap with an
	# idle unit just to keep every fresh unit busy.
	var battle := _spawn_line_relief_battle()
	await get_tree().physics_frame

	var found := _units_at(battle, [
		Vector2(300, 200), Vector2(600, 200), Vector2(900, 200),
		Vector2(280, 600), Vector2(600, 600), Vector2(950, 600),
	])
	var fresh1: Unit = found[0]
	var fresh2: Unit = found[1]
	var tired_b: Unit = found[4]   # the only engaged unit, and the clicked target
	tired_b.state = Unit.State.FIGHTING
	# tired_a / tired_c stay IDLE -- not valid relief candidates. tired_b needs a real
	# foe: UnitRelief.begin's single-pair path only issues the pile-on attack order to
	# a second reliever when it resolves one, matching how a genuinely engaged unit
	# would already have (or be able to find) an opponent.
	var foe := Unit.new()
	add_child_autofree(foe)
	foe.uid = 999
	foe.team = 1
	foe.position = tired_b.position + Vector2(0, 60)
	tired_b.target_enemy = foe

	battle._apply_order_cmd({
		"units": [fresh1.uid, fresh2.uid],
		"x": tired_b.position.x, "y": tired_b.position.y,
		"target": tired_b.uid,
		"mode": BattleScript.OrderMode.NORMAL,
		"group_attack": BattleScript.GroupAttackMode.DISTRIBUTED,
	})

	assert_eq(fresh1.current_order.type, Order.Type.RELIEF, "the primary reliever swaps")
	assert_eq(fresh1.current_order.friendly_target, tired_b,
			"with the only engaged friendly -- the one actually clicked")
	assert_eq(fresh2.current_order.type, Order.Type.ATTACK,
			"the second fresh unit piles onto the same fight instead of relieving an idle unit")


func test_distributed_relief_excludes_an_ordered_unit_from_being_a_relief_target() -> void:
	# A box-select that sweeps up a fresh reserve line AND part of the engaged line ahead
	# of it is an ordinary player action -- nothing stops a box from catching both. Before
	# the relief_targets scan excluded candidates already among cmd["units"], an
	# already-FIGHTING unit caught in that same box could be picked as ANOTHER reliever's
	# tired partner while it was also about to receive its own order later in the same
	# "for uid in cmd['units']" loop -- whichever write landed last (its own order, or the
	# retreat UnitRelief.begin() hands it as someone else's target) silently clobbered the
	# other. Here "already_fighting" and "fresh" are both ordered; "tired_target" is the
	# clicked friendly outside the selection.
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": 20, "x": 300, "y": 200},   # already-fighting, box-selected
		{"team": 0, "type": "Infantry", "count": 20, "x": 600, "y": 200},   # fresh, box-selected
		{"team": 0, "type": "Infantry", "count": 20, "x": 600, "y": 600},   # the clicked target
	]
	add_child(_battle)
	await get_tree().physics_frame   # _ready spawns the scenario units

	var found := _units_at(_battle, [
		Vector2(300, 200), Vector2(600, 200), Vector2(600, 600),
	])
	var already_fighting: Unit = found[0]
	var fresh: Unit = found[1]
	var tired_target: Unit = found[2]
	for u in found:
		assert_not_null(u, "every scenario unit spawned")

	# Both already_fighting and tired_target are genuinely engaged. tired_target needs a
	# real foe, same as the single-pair test above, so UnitRelief.begin resolves one for
	# whichever unit ends up relieving it.
	already_fighting.state = Unit.State.FIGHTING
	tired_target.state = Unit.State.FIGHTING
	var foe := Unit.new()
	add_child_autofree(foe)
	foe.uid = 999
	foe.team = 1
	foe.position = tired_target.position + Vector2(0, 60)
	tired_target.target_enemy = foe

	_battle._apply_order_cmd({
		"units": [already_fighting.uid, fresh.uid],
		"x": tired_target.position.x, "y": tired_target.position.y,
		"target": tired_target.uid,
		"mode": BattleScript.OrderMode.NORMAL,
		"group_attack": BattleScript.GroupAttackMode.DISTRIBUTED,
	})

	# already_fighting is itself one of the ordered units -- it must keep the order its
	# OWN turn in the loop gave it (relieving tired_target, as the primary/first
	# reliever, since it's the only valid relief candidate once itself is excluded from
	# the pool), never a retreat MOVE order from being picked as fresh's relief target.
	assert_eq(already_fighting.current_order.type, Order.Type.RELIEF,
			"the already-fighting ordered unit keeps its own order, not a retreat")
	assert_eq(already_fighting.current_order.friendly_target, tired_target,
			"and it relieves the clicked target -- it is never treated as a relief target itself")
	assert_eq(fresh.current_order.type, Order.Type.ATTACK,
			"the second ordered unit piles onto the same fight instead of relieving already_fighting")
