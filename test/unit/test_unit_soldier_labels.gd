extends GutTest
## Pure geometry of the dev/debug soldier-ID overlay (UnitSoldierLabels): the per-soldier
## label anchor points, a function of the sim positions/unit position/mark radius only,
## checked directly without a live unit or a render pass. Purely cosmetic/diagnostic --
## no sim/combat is exercised. See sparta#675.

const UnitScript = preload("res://scripts/Unit.gd")


func test_label_anchors_offsets_each_point_above_its_mark() -> void:
	# unit_position ZERO: each anchor is just the sim position shifted up (-Y) by mark_r.
	var sim := PackedVector2Array([Vector2(0, 0), Vector2(10, 20)])
	var anchors := UnitSoldierLabels.label_anchors(sim, Vector2.ZERO, 4.5)
	assert_eq(anchors.size(), sim.size(), "one anchor per soldier position")
	assert_eq(anchors[0], Vector2(0, -4.5), "anchor sits mark_r above the soldier")
	assert_eq(anchors[1], Vector2(10, 15.5), "offset applies uniformly to every soldier")


func test_label_anchors_are_relative_to_the_units_own_position() -> void:
	# unit_position is subtracted -- this is the same conversion _refresh_flock_render
	# uses (_sim_soldier_pos[i] - position) to land a parent-local sim point in the
	# unit's own _draw() local frame, NOT to_local().
	var sim := PackedVector2Array([Vector2(100, 200)])
	var anchors := UnitSoldierLabels.label_anchors(sim, Vector2(100, 200), 10.0)
	assert_eq(anchors[0], Vector2(0, -10.0),
		"a soldier standing exactly at the unit's own position anchors at the origin, offset up")


func test_label_anchors_empty_for_no_soldiers() -> void:
	var anchors := UnitSoldierLabels.label_anchors(PackedVector2Array(), Vector2.ZERO, 4.5)
	assert_eq(anchors.size(), 0, "no soldiers -> no anchors")


func test_label_anchors_preserve_soldier_index_order() -> void:
	# The anchor at index i must correspond to soldier i -- the whole point of the
	# overlay is that the drawn digit i matches _sim_soldier_pos's index i.
	var sim := PackedVector2Array([Vector2(0, 0), Vector2(5, 5), Vector2(-5, 5)])
	var anchors := UnitSoldierLabels.label_anchors(sim, Vector2.ZERO, 0.0)
	for i in range(sim.size()):
		assert_eq(anchors[i], sim[i], "anchor %d matches sim position %d (mark_r=0)" % [i, i])


# --- Unit's own accessor -------------------------------------------------------

func test_unit_soldier_sim_positions_accessor_exposes_the_sim_array() -> void:
	# soldier_sim_positions() is the read-only accessor UnitSoldierLabels.draw() calls;
	# pin that it returns the live _sim_soldier_pos array (empty before any physics tick
	# seeds it -- no live Battle is running in this test).
	var u := UnitScript.new()
	autofree(u)
	assert_eq(u.soldier_sim_positions(), u._sim_soldier_pos,
		"the public accessor mirrors the private sim array")


# --- render smoke: the overlay draws without error -----------------------------
# UnitSoldierLabels.draw() issues draw_string() calls, which are only valid inside a
# CanvasItem's own _draw(). Drive it the way the engine does: a live unit in the tree,
# a queue_redraw(), and a couple of awaited frames -- the same pattern
# test_unit_shields.gd uses for UnitShields.draw(). A tiny Unit subclass calls the
# overlay unconditionally from _draw() so this smoke test is independent of the
# selected/Settings/_detailed_lod gate in Unit._draw() itself (that gate is three
# trivial boolean checks, not overlay logic).
class _SoldierIdUnit:
	extends Unit
	func _draw() -> void:
		super._draw()
		UnitSoldierLabels.draw(self)


func test_soldier_id_overlay_draws_without_error() -> void:
	var u: Unit = _SoldierIdUnit.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(u), "the unit is still alive after drawing the overlay")


func test_soldier_id_overlay_draws_with_no_soldiers_seeded() -> void:
	# Before any physics tick, _sim_soldier_pos is empty -- the overlay must be a
	# no-op loop, not an error, when there's nothing to label yet.
	var u: Unit = _SoldierIdUnit.new()
	add_child_autofree(u)
	assert_eq(u.soldier_sim_positions().size(), 0, "setup: no sim bodies seeded yet")
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(u), "drawing with zero soldiers is a harmless no-op")
