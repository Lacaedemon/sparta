extends GutTest
## Spawn-facing-flip formation churn: a unit that spawns facing one way and is
## immediately drawn into combat roughly the opposite way used to have every soldier's
## formation slot swap to the far side of the block in one tick (soldier_world_slots rotates
## the local slot grid by the unit's CURRENT facing). Soldiers ARRIVE at slots under bounded
## force (SoldierBodies.step), not teleport, so the whole block visibly compressed then
## re-expanded over 1.5-3 s as everyone walked to their new side -- "pulsing".
##
## The fix folds a large instant facing snap (_face_dir, beyond FACING_SNAP_ABSORB_THRESHOLD)
## into _formation_angle -- the same absorb mechanism the drill turns (conversio/quarter-turn)
## and the engage re-face already use -- so soldier_world_slots reproduces each body's own
## pre-snap slot under the new facing instead of swapping every slot to the other side. These
## tests pin it two ways: an isolated-unit unit test on _face_dir/_formation_angle directly
## (fast, exact), and a LIVE Battle scene replay of demos/inputs/spawn-facing-flip-fixed.json
## (a minimal, cavalry-only reproduction), tick-by-tick, asserting the bbox never collapses
## (this repo's "verify by state, not by eyeballing a GIF" convention).


func _bbox(ps: PackedVector2Array) -> Vector2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in ps:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return mx - mn


# --- isolated-unit: a large facing snap absorbs into _formation_angle, no slot swap ------

func _unit(uid: int, team: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)            # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.seed_sim_soldiers()
	return u


func test_large_facing_snap_keeps_every_body_on_its_own_slot() -> void:
	# Spawn facing north, then snap to facing ~south (a ~167 degree flip, matching the
	# issue's repro) in a single call -- exactly what the auto-advance chase path used to
	# do via _face_dir with no protection.
	var u := _unit(1, 0, Vector2(500, 500), Vector2.UP)
	var start_bbox: Vector2 = _bbox(u._sim_soldier_pos)
	var before: PackedVector2Array = u._sim_soldier_pos.duplicate()

	u._face_dir(Vector2(0.23, 0.97))   # the issue's exact post-flip facing

	# The snap itself must not move a single body -- only the facing and the compensating
	# _formation_angle change; positions are untouched until the next SoldierBodies.step.
	for i in range(before.size()):
		assert_eq(u._sim_soldier_pos[i], before[i],
			"facing snap alone must not move body %d" % i)
	assert_ne(u._formation_angle, 0.0,
		"a large snap is absorbed into _formation_angle instead of moving the grid")

	# Now the formation grid (soldier_world_slots) must reproduce each body's CURRENT slot
	# under the new facing -- i.e. arrival has ~nothing to do, so nothing walks anywhere.
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(slots.size()):
		assert_almost_eq(slots[i].x, u._sim_soldier_pos[i].x, 0.5)
		assert_almost_eq(slots[i].y, u._sim_soldier_pos[i].y, 0.5)

	# Stepping the bodies forward several ticks must not shrink the footprint at all -- the
	# pre-fix bug shrank a very similar block from ~99x54 down to ~32x30 over ~90 ticks.
	for _i in range(90):
		SoldierBodies.step(u, 1.0 / 60.0)
	var mid_bbox: Vector2 = _bbox(u._sim_soldier_pos)
	assert_almost_eq(mid_bbox.x, start_bbox.x, 1.0,
		"the block width does not collapse after a large facing snap")
	assert_almost_eq(mid_bbox.y, start_bbox.y, 1.0,
		"the block depth does not collapse after a large facing snap")


func test_small_facing_correction_still_snaps_immediately() -> void:
	# A small drift (well under the threshold) must behave exactly as before: an instant
	# snap with no _formation_angle change -- close-quarters responsiveness is unaffected.
	var u := _unit(1, 0, Vector2(500, 500), Vector2.DOWN)
	u._face_dir(Vector2(0.05, 0.999).normalized())   # a few degrees off DOWN
	assert_eq(u._formation_angle, 0.0,
		"a small correction snaps outright -- nothing to absorb")
	assert_true(u.facing.is_equal_approx(Vector2(0.05, 0.999).normalized()))


func test_rout_flee_facing_snap_keeps_every_body_on_its_own_slot() -> void:
	# _process_rout's flee-facing update used to assign `facing = flee` directly, bypassing
	# _face_dir's snap-absorb entirely -- so a unit that starts routing facing sharply away
	# from its flee direction reproduced the same churn this file guards against for the
	# move-order path, just via a different call site (scripts/Unit.gd's ROUTING branch).
	var u := _unit(1, 0, Vector2(500, 500), Vector2.DOWN)   # facing south
	u._shattered = true   # flee-forever, so nothing rallies mid-observation
	var start_bbox: Vector2 = _bbox(u._sim_soldier_pos)

	# Team 0 flees Vector2.UP (north) -- facing DOWN is a ~180 degree flip on the first tick.
	u._process_rout(1.0 / 60.0)
	assert_ne(u._formation_angle, 0.0,
		"the rout-triggered flip absorbs into _formation_angle, same as _face_dir's own snap")

	var min_bbox_area: float = start_bbox.x * start_bbox.y
	for _i in range(90):
		u._process_rout(1.0 / 60.0)
		SoldierBodies.step(u, 1.0 / 60.0)
		var area: Vector2 = _bbox(u._sim_soldier_pos)
		min_bbox_area = minf(min_bbox_area, area.x * area.y)

	var start_area: float = start_bbox.x * start_bbox.y
	assert_gt(min_bbox_area, start_area * 0.75,
		("the formation's footprint never collapses by more than ~25%% when a routing unit's "
			+ "flee direction sharply differs from its facing at the moment it starts fleeing "
			+ "(start %.0f, min %.0f sq px)") % [start_area, min_bbox_area])


func test_degenerate_zero_length_dir_leaves_facing_unchanged() -> void:
	# A zero-length dir (e.g. a body exactly on its target point) is a no-op -- the guard
	# clause predates this fix and must still hold, with no _formation_angle side effect.
	var u := _unit(1, 0, Vector2(500, 500), Vector2.DOWN)
	u._face_dir(Vector2.ZERO)
	assert_true(u.facing.is_equal_approx(Vector2.DOWN), "facing is untouched by a zero dir")
	assert_eq(u._formation_angle, 0.0, "nothing to absorb from a no-op snap")


# --- live Battle replay of the issue's repro (demos/inputs/spawn-facing-flip-fixed.json) --

## Enough ticks for the pre-fix churn to fully play out (the issue measured the compress/
## expand cycle bottoming out around tick 90-95 and regrowing by 150, measured from the
## cavalry's own spawn -- comfortably inside this cap).
const _SAMPLE_TICKS := 160


func test_demo_no_bbox_collapse_on_spawn_facing_flip() -> void:
	# A minimal, cavalry-only scenario (no player input at all) isolates the auto-advance
	# facing flip from any unrelated setup step, per this repo's demo-simplicity convention.
	OS.set_environment("SPARTA_DEMO_INPUT", "demos/inputs/spawn-facing-flip-fixed.json")
	var recorder: Node = load("res://tools/demo/DemoInputRecorder.tscn").instantiate()
	add_child_autofree(recorder)
	# The recorder defers spawning Battle (_start_battle.call_deferred()), so it isn't a
	# child yet on this frame.
	await get_tree().physics_frame
	var battle: Node = recorder.get_node("Battle")

	var cavalry: Unit = null
	# The scenario spawns on Battle._ready (called synchronously when Battle is added under
	# _start_battle, itself deferred from the recorder's _ready), so poll a few frames rather
	# than assuming either the unit or its seeded soldier bodies exist on the very next frame.
	for _k in range(20):
		if cavalry == null:
			for u in get_tree().get_nodes_in_group("units"):
				var unit: Unit = u as Unit
				if unit != null and unit.team == 1:
					cavalry = unit
					break
		if cavalry != null and not cavalry._sim_soldier_pos.is_empty():
			break
		await get_tree().physics_frame
	assert_not_null(cavalry, "the scenario spawned a team-1 cavalry unit")
	if cavalry == null:
		return
	assert_false(cavalry._sim_soldier_pos.is_empty(), "the cavalry's soldier bodies are seeded")
	if cavalry._sim_soldier_pos.is_empty():
		return

	var start_facing: Vector2 = cavalry.facing
	var start_bbox: Vector2 = _bbox(cavalry._sim_soldier_pos)
	assert_true(start_facing.y < 0.0, "cavalry spawns facing north/up, per the scenario")

	var min_bbox_area: float = start_bbox.x * start_bbox.y
	var max_bbox_area: float = min_bbox_area
	var flipped := false
	while battle.current_tick() < _SAMPLE_TICKS:
		await get_tree().physics_frame
		if not flipped and absf(angle_difference(start_facing.angle(), cavalry.facing.angle())) \
				> deg_to_rad(90.0):
			flipped = true
		var area: float = _bbox(cavalry._sim_soldier_pos).x * _bbox(cavalry._sim_soldier_pos).y
		min_bbox_area = minf(min_bbox_area, area)
		max_bbox_area = maxf(max_bbox_area, area)

	assert_true(flipped,
		"the enemy AI's auto-advance flipped the cavalry's facing by more than 90 degrees, "
		+ "reproducing the issue's setup")
	# Pre-fix this collapsed from ~99x54 (5346 sq px) to a minimum around ~32x30 (960 sq
	# px) before regrowing -- roughly an 82% area drop. Guard against any large collapse,
	# not just that exact number, so the test still catches a partial regression.
	var start_area: float = start_bbox.x * start_bbox.y
	assert_gt(min_bbox_area, start_area * 0.75,
		"the formation's footprint never collapses by more than ~25%% (start %.0f, min %.0f sq px)"
			% [start_area, min_bbox_area])
