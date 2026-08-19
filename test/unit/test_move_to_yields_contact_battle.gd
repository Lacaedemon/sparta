extends GutTest
## Orderly kinematic advance yields to contact in a LIVE battle: drive the committed
## disengaged-march-through-contact demo (the same clip that documented the remaining
## gap) and confirm that once the front arrests, the rear ranks do not keep compressing
## into it. Complements test_unit.gd's isolated _move_to yield pins: this is the full
## simulation (couple + soldier contact + the real order pipeline) where the over-
## compression actually showed up.


func _team_unit(p_team: int) -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var unit: Unit = node as Unit
		if unit != null and unit.team == p_team:
			return unit
	return null


func _block_depth(u: Unit) -> float:
	if u._sim_soldier_pos.is_empty():
		return 0.0
	var lo: float = INF
	var hi: float = -INF
	for p in u._sim_soldier_pos:
		var d: float = p.dot(u.facing)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return hi - lo


func test_disengaged_march_through_contact_does_not_over_compress_after_arrest() -> void:
	OS.set_environment("SPARTA_DEMO_INPUT", "demos/inputs/disengaged-march-through-contact.json")
	var recorder: Node = load("res://tools/demo/DemoInputRecorder.tscn").instantiate()
	add_child_autofree(recorder)
	await get_tree().physics_frame
	var battle: Node = recorder.get_node("Battle")

	# Arrest is already clear by ~340 on this seed (see the demo input's own _comment).
	while battle.current_tick() < 340:
		await get_tree().physics_frame
	var walker := _team_unit(0)
	assert_not_null(walker, "the disengaging Infantry is on the field")
	if walker == null:
		return
	assert_true(walker._in_enemy_contact,
			"sanity: the march is in physical contact by the documented arrest tick")
	var depth_at_arrest: float = _block_depth(walker)
	assert_gt(depth_at_arrest, Unit.FORMATION_SPACING,
			"sanity: the block still has rank depth at arrest")

	while battle.current_tick() < 400:
		await get_tree().physics_frame
	assert_true(is_instance_valid(walker), "the disengaging unit is still on the field")
	if not is_instance_valid(walker):
		return
	var depth_after: float = _block_depth(walker)
	assert_gte(depth_after, depth_at_arrest * 0.8,
			"rear ranks do not keep compressing into the arrested front after yield (depth %.1f -> %.1f)"
			% [depth_at_arrest, depth_after])
