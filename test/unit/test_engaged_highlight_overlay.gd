extends GutTest
## Render smoke test for the engaged-soldier highlight (Unit._refresh_flock_render's
## per-instance color dispatch): a dev/debug visual gated behind
## `Settings.show_engaged_highlight`. Purely cosmetic -- no sim/combat exercised beyond what
## `engaged_soldier_indices()` itself already reads. Drive it the way the engine does (add a
## live unit to the tree, request a redraw, let a frame pass) so `_refresh_flock_render`
## actually runs and builds the engaged lookup, per the render-only overlay pattern's own
## coverage approach (see .claude/memories/sparta.md) -- MultiMesh instance data isn't
## synchronously readable back in headless tests, so these assert the dispatch runs without
## error, not the drawn colors themselves (`_soldier_render_color`'s own tests in
## test_unit.gd cover the actual color logic).


func _engaged_square_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 30
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.set_formation(Unit.FORMATION_SQUARE)
	u.seed_sim_soldiers()
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.0)
	return u


func test_engaged_highlight_draws_without_error_when_enabled() -> void:
	var u := _engaged_square_unit()
	Settings._loading = true
	Settings.show_engaged_highlight = true
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings._loading = true
	Settings.show_engaged_highlight = false
	Settings._loading = false
	assert_true(u.is_engaged(), "still engaged after draw")


func test_engaged_highlight_is_a_no_op_when_setting_is_off() -> void:
	var u := _engaged_square_unit()
	Settings._loading = true
	Settings.show_engaged_highlight = false
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(Settings.show_engaged_highlight, "overlay setting stays off")


func test_engaged_highlight_draws_without_error_on_a_far_tier_unit() -> void:
	# Far-tier units have no simulated bodies (_render_body_count() reads `soldiers`, not
	# _sim_soldier_pos), so the highlight must no-op there rather than call
	# engaged_soldier_indices() against a stale/empty position array.
	var u := _engaged_square_unit()
	u.tier = FormationTier.FAR
	Settings._loading = true
	Settings.show_engaged_highlight = true
	Settings._loading = false
	u.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	Settings._loading = true
	Settings.show_engaged_highlight = false
	Settings._loading = false
	assert_eq(u.tier, FormationTier.FAR, "still far-tier after draw")
