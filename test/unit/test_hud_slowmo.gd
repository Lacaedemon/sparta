extends GutTest
## F5 slow-motion tick-speed cycle: Engine.time_scale drives the mechanism (see HUD.gd's
## SLOWMO_PRESETS doc comment for why that scales delta rather than tick frequency), with
## a persistent on-screen indicator and Shift+F5 reversing the cycle. Engine.time_scale is
## a global engine singleton -- not scoped to any one HUD/Battle instance -- so every test
## here restores it in after_each; otherwise a test that leaves it non-1.0 would silently
## affect every later test in the same suite run.

const HUDScript = preload("res://scripts/HUD.gd")

var _orig_time_scale: float


func before_each() -> void:
	_orig_time_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _orig_time_scale
	Replay.reset()
	Replay.forced_seed = -1


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)
	return hud


func _key_event(physical_keycode: int, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = true
	event.shift_pressed = shift
	return event


func test_starts_at_normal_speed_with_the_indicator_hidden() -> void:
	var hud := _hud()
	assert_eq(hud._slowmo_index, 0, "a fresh HUD starts at the normal-speed preset")
	assert_false(hud._slowmo_label.visible, "the indicator is hidden at normal speed")


func test_f5_cycles_forward_through_the_presets_and_sets_time_scale() -> void:
	var hud := _hud()
	hud._cycle_slowmo()
	assert_eq(hud._slowmo_index, 1, "first press advances to the second preset")
	assert_eq(Engine.time_scale, HUDScript.SLOWMO_PRESETS[1], "time_scale matches the new preset")
	assert_true(hud._slowmo_label.visible, "the indicator shows once off normal speed")

	hud._cycle_slowmo()
	hud._cycle_slowmo()
	assert_eq(hud._slowmo_index, 3, "three presses reach the last (10%) preset")
	assert_eq(Engine.time_scale, HUDScript.SLOWMO_PRESETS[3])

	hud._cycle_slowmo()
	assert_eq(hud._slowmo_index, 0, "a fourth press wraps back to normal speed")
	assert_eq(Engine.time_scale, 1.0)
	assert_false(hud._slowmo_label.visible, "the indicator hides again at normal speed")


func test_shift_f5_cycles_backward() -> void:
	var hud := _hud()
	hud._cycle_slowmo(true)
	assert_eq(hud._slowmo_index, HUDScript.SLOWMO_PRESETS.size() - 1,
			"cycling backward from normal speed wraps to the last preset")
	assert_eq(Engine.time_scale, HUDScript.SLOWMO_PRESETS[-1])

	hud._cycle_slowmo(true)
	assert_eq(hud._slowmo_index, HUDScript.SLOWMO_PRESETS.size() - 2,
			"a second backward press steps to the preceding preset")


func test_unhandled_input_dispatches_f5_and_shift_f5() -> void:
	var hud := _hud()
	hud._unhandled_input(_key_event(KEY_F5))
	assert_eq(hud._slowmo_index, 1, "a bare F5 press cycles forward via _unhandled_input")

	hud._unhandled_input(_key_event(KEY_F5, true))
	assert_eq(hud._slowmo_index, 0, "Shift+F5 cycles backward via _unhandled_input")


func test_is_slowmo_keypress_only_matches_a_real_f5_key_press() -> void:
	var hud := _hud()
	assert_true(hud._is_slowmo_keypress(_key_event(KEY_F5)), "a plain F5 press matches")
	assert_true(hud._is_slowmo_keypress(_key_event(KEY_F5, true)),
			"a Shift+F5 press also matches -- shift only decides direction, not whether it fires")
	assert_false(hud._is_slowmo_keypress(_key_event(KEY_F4)), "a different function key doesn't match")

	var released := _key_event(KEY_F5)
	released.pressed = false
	assert_false(hud._is_slowmo_keypress(released), "a key-release event doesn't match")

	var echoed := _key_event(KEY_F5)
	echoed.echo = true
	assert_false(hud._is_slowmo_keypress(echoed), "an echoed (held-down) key repeat doesn't match")


func test_label_text_reports_the_percentage() -> void:
	var hud := _hud()
	hud._cycle_slowmo()
	hud._cycle_slowmo()
	assert_true(hud._slowmo_label.text.contains("25%"),
			"the indicator names the current preset's percentage")


## The record_time_scale_change() call is gated on having a real Battle parent
## (get_parent() as BattleRef), so every test above -- which spawns a bare, unparented HUD
## -- never reaches it. Confirm the wiring separately, on a real Battle, so a saved replay
## actually carries the change (see test_replay_time_scale.gd for the fuller round-trip
## proof through save/load).
func test_cycle_slowmo_records_the_change_when_parented_to_a_live_battle() -> void:
	Replay.forced_seed = 33221
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.scenario = [{"team": 0, "type": "Infantry", "x": 500, "y": 500}]
	add_child_autofree(battle)
	for _k in range(5):
		await get_tree().physics_frame
	var hud: Node = battle.get_node("HUD")
	var tick_before: int = battle.current_tick()

	hud._cycle_slowmo()

	assert_eq(Replay._time_scale_track.size(), 1,
			"the change is recorded once the HUD is parented to a real, recording battle")
	assert_eq(int(Replay._time_scale_track[0]["tick"]), tick_before,
			"recorded at the battle's own current tick")
	assert_almost_eq(float(Replay._time_scale_track[0]["value"]), HUDScript.SLOWMO_PRESETS[1],
			0.0001, "and carries the new preset's value")


func test_exit_tree_resets_time_scale_so_it_cannot_leak_into_the_next_battle() -> void:
	var hud = HUDScript.new()
	add_child(hud)
	hud._cycle_slowmo()
	hud._cycle_slowmo()
	assert_ne(Engine.time_scale, 1.0, "sanity: slow-mo is actually active before teardown")

	hud.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_eq(Engine.time_scale, 1.0,
			"freeing the HUD resets time_scale so a later battle/test isn't silently slowed")
