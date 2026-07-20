extends GutTest
## Disengage and step back, in a LIVE battle: drive the real committed demo
## (demos/inputs/disengage-step-back.json) through the actual scripted-input recorder --
## the same one CI uses -- and confirm the Ctrl+Down hotkey genuinely breaks contact on a
## real, currently-FIGHTING regiment. Complements test_disengage_maneuver.gd's bare-unit
## coverage the way test_wheel_battle.gd complements test_wheel.gd: this guards the demo
## (and its hotkey) against silent breakage, in the full simulation context.


func _team0_unit() -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 0:
			return unit
	return null


func _team1_unit() -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == 1:
			return unit
	return null


func test_disengage_demo_input_breaks_contact() -> void:
	OS.set_environment("SPARTA_DEMO_INPUT", "demos/inputs/disengage-step-back.json")
	var recorder: Node = load("res://tools/demo/DemoInputRecorder.tscn").instantiate()
	add_child_autofree(recorder)
	await get_tree().physics_frame   # the recorder spawns Battle deferred
	var battle: Node = recorder.get_node("Battle")

	# Step to just past the scripted Ctrl+Down (tick 300, per the demo script), confirming
	# real melee contact was established first -- otherwise the disengage test below would
	# be vacuous.
	while battle.current_tick() < 250:
		await get_tree().physics_frame
	var defender := _team0_unit()
	assert_not_null(defender, "the player Infantry regiment is on the field")
	if defender == null:
		return
	assert_eq(defender.state, Unit.State.FIGHTING,
		"real contact is established well before the scripted disengage order fires")

	while battle.current_tick() < 305:
		await get_tree().physics_frame
	assert_null(defender.target_enemy,
		"the scripted Ctrl+Down cleared target_enemy -- the disengage signal took")
	assert_true(defender.has_move_target, "a step-back move order is armed")

	# Poll until contact genuinely breaks (engaged() goes false), or a generous cap trips --
	# matches test_wheel_battle.gd's own poll-for-the-real-end-condition idiom rather than a
	# fixed tick count, so this doesn't race a slower runner. Empirically (dump-state.sh)
	# this settles around tick 340 on this seed.
	var settle_ticks := 0
	while defender.is_engaged() and settle_ticks < 300:
		await get_tree().physics_frame
		settle_ticks += 1
	assert_false(defender.is_engaged(),
		"the disengaging unit genuinely breaks contact within budget (settled after %d ticks)"
			% settle_ticks)
	assert_ne(defender.state, Unit.State.FIGHTING,
		"it's marching, not fighting, once contact is broken")

	# The enemy's own attack order never releases just because we disengaged (that's the
	# already-documented cost -- see Unit.disengage()'s own doc comment): it's expected to
	# still be on the field, still committed to the same foe.
	var attacker := _team1_unit()
	assert_not_null(attacker, "the enemy regiment is still on the field")
	if attacker != null and defender != null:
		assert_eq(attacker.target_enemy, defender,
			"the enemy keeps its own attack order on the disengaging unit")
