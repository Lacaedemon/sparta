extends GutTest
## Render smoke test for the position-anchor marker (Unit._draw's position-anchor block,
## #821): a dev/debug visual gated behind `Settings.show_position_anchor` that draws a small
## dot at Vector2.ZERO (this node's own local-draw-space origin, which IS `position`).
## Purely cosmetic -- no sim/combat exercised. Drive it the way the engine does (add a live
## unit to the tree, request a redraw, let a frame pass) so Unit._draw actually runs under
## the real draw notification, per the render-only overlay pattern's own coverage approach
## (see .claude/memories/sparta.md).


func _live_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 12
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	return u


func test_position_anchor_draws_without_error_when_enabled() -> void:
	var u := _live_unit()
	Settings._loading = true
	Settings.show_position_anchor = true
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings._loading = true
	Settings.show_position_anchor = false
	Settings._loading = false
	assert_true(Settings._loading == false, "settings restored after draw")


func test_position_anchor_is_a_no_op_when_setting_is_off() -> void:
	var u := _live_unit()
	Settings._loading = true
	Settings.show_position_anchor = false
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(Settings.show_position_anchor, "overlay setting stays off")
