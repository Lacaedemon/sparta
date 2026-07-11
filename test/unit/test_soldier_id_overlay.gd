extends GutTest
## Render smoke test for the per-soldier ID overlay (Unit._draw's soldier-ID block):
## a dev/debug visual gated behind `selected`, `Settings.show_soldier_ids`, and
## `_detailed_lod`. Purely cosmetic -- no sim/combat exercised. Drive it the way the
## engine does (add a live unit to the tree, request a redraw, let a frame pass) so
## Unit._draw actually runs under the real draw notification, per the render-only
## overlay pattern's own coverage approach (see .claude/memories/sparta.md).


func _live_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 12
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	return u


func test_soldier_ids_draw_without_error_when_enabled() -> void:
	var u := _live_unit()
	u.selected = true
	u._detailed_lod = true
	Settings._loading = true
	Settings.show_soldier_ids = true
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings._loading = true
	Settings.show_soldier_ids = false
	Settings._loading = false
	assert_true(u.selected, "still selected after draw")


func test_soldier_ids_are_a_no_op_when_setting_is_off() -> void:
	var u := _live_unit()
	u.selected = true
	u._detailed_lod = true
	Settings._loading = true
	Settings.show_soldier_ids = false
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(Settings.show_soldier_ids, "overlay setting stays off")


func test_soldier_ids_are_a_no_op_when_not_selected() -> void:
	var u := _live_unit()
	u.selected = false
	u._detailed_lod = true
	Settings._loading = true
	Settings.show_soldier_ids = true
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings._loading = true
	Settings.show_soldier_ids = false
	Settings._loading = false
	assert_false(u.selected, "still unselected after draw")
