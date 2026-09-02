extends GutTest
## Tests for the Replay presentation (camera) track: recording with dedup, playback
## stepping, save/load round-trip, and back-compat with replays that have no track.
## Also the per-order optional fields' record/save/load/apply round trips, including the
## one seam that needs a real ticking Battle: the per-tick recording drain.

const ReplayScript = preload("res://scripts/Replay.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")


## A fresh, isolated Replay instance so tests never touch the live autoload's state.
func _fresh() -> Node:
	var r: Node = ReplayScript.new()
	add_child_autofree(r)
	return r


## A Unit registered under `uid`, and a bare Battle that knows about it -- the same
## script-only fixture test_battle.gd uses to exercise _apply_order_cmd without standing up
## a full battle scene (the dispatch reads only _by_uid and the static formation helpers).
## reform_before_move is defaulted off so a bare order marches immediately, matching that
## suite's convention.
func _battle_with_unit(uid: int, pos: Vector2) -> Array:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	u.uid = uid
	u.position = pos
	u.reform_before_move = false
	var b = BattleScript.new()
	autofree(b)
	b._by_uid[uid] = u
	return [b, u]


func test_record_camera_dedups_static_frames() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_camera(0, Vector2(100, 100), 1.0)
	r.record_camera(1, Vector2(100, 100), 1.0)   # unchanged -> dropped
	r.record_camera(2, Vector2(150, 100), 1.5)   # moved -> kept
	assert_eq(r._camera_track.size(), 2,
			"a still camera dedups to one keyframe; a move adds another")
	assert_true(r.has_camera_track(), "a recorded track reports present")


func test_record_camera_is_noop_outside_record() -> void:
	var r := _fresh()   # mode IDLE
	r.record_camera(0, Vector2(10, 10), 1.0)
	assert_eq(r._camera_track.size(), 0, "no camera is captured outside RECORD")
	assert_false(r.has_camera_track(), "no track without recording")


func test_camera_for_tick_holds_last_keyframe() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0},
		{"tick": 10, "x": 100.0, "y": 0.0, "zoom": 2.0},
	]
	assert_eq(r.camera_for_tick(0)["zoom"], 1.0, "tick 0 uses the first keyframe")
	assert_eq(r.camera_for_tick(5)["zoom"], 1.0, "between keyframes it holds the earlier one")
	assert_eq(r.camera_for_tick(10)["x"], 100.0, "at the next keyframe's tick it switches")
	assert_eq(r.camera_for_tick(99)["x"], 100.0, "past the last keyframe it holds the last")


func test_camera_for_tick_before_first_keyframe_holds_first() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [{"tick": 5, "x": 7.0, "y": 8.0, "zoom": 1.5}]
	assert_eq(r.camera_for_tick(0)["x"], 7.0,
			"a tick before the first keyframe holds the first framing")


func test_camera_for_tick_rewinds_on_step_back() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0},
		{"tick": 10, "x": 100.0, "y": 0.0, "zoom": 2.0},
	]
	assert_eq(r.camera_for_tick(10)["x"], 100.0, "advance the cursor to the later keyframe")
	assert_eq(r.camera_for_tick(0)["x"], 0.0, "a step back to tick 0 rewinds to the first keyframe")


func test_camera_for_tick_empty_without_track_or_playback() -> void:
	var r := _fresh()   # IDLE, no track
	assert_eq(r.camera_for_tick(0), {}, "no track / not playing back -> empty")


func test_save_load_round_trips_the_camera_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_camera(0, Vector2(10.0, 20.0), 0.8)
	r.record_camera(3, Vector2(40.0, 20.0), 1.2)
	var path: String = r.save("Test", 3)
	assert_ne(path, "", "the recording saves to a path")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	assert_true(loaded.has_camera_track(), "the camera track survives save/load")
	assert_almost_eq(loaded.camera_for_tick(0)["zoom"], 0.8, 0.0001, "zoom round-trips")
	assert_almost_eq(loaded.camera_for_tick(3)["x"], 40.0, 0.0001, "position round-trips")


func test_replay_without_camera_moves_has_no_track() -> void:
	# A recording that never moves (records) the camera omits the track entirely, so it
	# loads exactly like a pre-camera replay: no track, default static camera on playback.
	var r := _fresh()
	r.start_recording()
	var path: String = r.save("Test", 0)
	assert_ne(path, "", "the recording saves even with no camera track")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "it loads")
	assert_false(loaded.has_camera_track(), "no camera keyframes -> no presentation track")
	assert_eq(loaded.camera_for_tick(0), {}, "playback drives nothing -> static camera")


func test_save_load_round_trips_an_anchored_frontage_orders_anchor_offset() -> void:
	# Regression test: an asymmetric (anchored) explicatio/duplicatio's anchor_offset must
	# survive a save/load round trip like every other order field, or a saved-and-replayed
	# anchored widen silently re-centres instead of holding the flank (live-vs-replay desync
	# -- the anchor read correctly in a live session, since Battle.enqueue_file_double applies
	# it immediately, but a *replayed* recording of the same session would drop it, since
	# record_order never carried it to the saved file).
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -4, 0, 0, 32, INF, 0, -72.0)   # -4 = ORDER_FRONTAGE_ONLY
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the frontage order round-trips")
	assert_almost_eq(float(due[0].get("anchor_offset", 0.0)), -72.0, 0.0001,
			"the anchor offset round-trips through save/load, not just live recording")


func test_a_centred_frontage_order_omits_anchor_offset_on_round_trip() -> void:
	# The plain (centred) case -- anchor_offset 0.0 -- stays omitted on save (matching the
	# in-memory record_order behaviour for every other optional field) and reads back as the
	# same 0.0 default, so an old replay recorded before this field existed still loads and
	# plays exactly like a fresh centred resize.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -4, 0, 0, 16)   # -4 = ORDER_FRONTAGE_ONLY, no anchor
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the frontage order round-trips")
	assert_false(due[0].has("anchor_offset"),
			"a centred resize's order carries no anchor_offset key at all, like a pre-anchor replay")


func test_save_load_round_trips_a_multi_unit_form_up_group_id() -> void:
	# docs/atomic-order-decomposition-design.md: a multi-unit drag-line form-up's shared
	# group id must survive save/load like any other order field, or a replayed recording
	# would rebuild every per-unit order as ungrouped (losing the FORM_UP tree structure)
	# even though the live session grouped them.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [11], Vector2(10, 20), -1, 0, 0, 4, 0.5, 0, 0.0, 2)
	r.record_order(5, [12], Vector2(30, 20), -1, 0, 0, 4, 0.5, 0, 0.0, 2)
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 2, "both grouped orders round-trip")
	assert_eq(int(due[0].get("form_up_group", -1)), 2, "the group id round-trips, not just live")
	assert_eq(int(due[1].get("form_up_group", -1)), 2,
			"both units' orders read back tagged with the SAME group id")


func test_an_ungrouped_form_up_omits_form_up_group_on_round_trip() -> void:
	# A single-unit form-up (or any other order) carries no group id at all, matching the
	# in-memory record_order behaviour for every other optional field -- an old replay
	# recorded before this field existed still loads with no group id, same as a fresh
	# single-unit deploy.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -1, 0, 0, 4, 0.5)   # a plain (ungrouped) form-up
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1)
	assert_false(due[0].has("form_up_group"),
			"an ungrouped order carries no form_up_group key at all, like a pre-grouping replay")


func test_save_load_round_trips_a_unit_settings_orders_toggles() -> void:
	# A mid-battle walk_advance/reform_before_move toggle is its own recordable order
	# (Battle.enqueue_unit_settings, target ORDER_UNIT_SETTINGS_ONLY = -9) -- the toggle
	# itself, not just its downstream effect, must survive save/load like every other order
	# field, or a replayed recording would silently drop the toggle and desync from the
	# unit state the live session actually reached.
	var r := _fresh()
	r.start_recording()
	# -9 = Battle.ORDER_UNIT_SETTINGS_ONLY; 1 = UnitSettingToggle.ON, 2 = UnitSettingToggle.OFF.
	r.record_order(5, [0], Vector2.ZERO, -9, 0, 0, 0, INF, 0, 0.0, -1, 1, 2)
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the unit-settings order round-trips")
	assert_eq(int(due[0].get("walk_advance_toggle", 0)), 1,
			"the walk_advance toggle (ON) round-trips through save/load")
	assert_eq(int(due[0].get("reform_toggle", 0)), 2,
			"the reform_before_move toggle (OFF) round-trips through save/load")


func test_a_leave_toggle_omits_the_unit_settings_keys_on_round_trip() -> void:
	# The all-LEAVE case (0) stays omitted on save, matching the in-memory record_order
	# behaviour for every other optional field -- an old replay recorded before this
	# migration still loads and plays exactly like a fresh order that never touches
	# either setting.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -1, 0, 0, 4, 0.5)   # a plain move, no toggles at all
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1)
	assert_false(due[0].has("walk_advance_toggle"),
			"a LEAVE toggle carries no walk_advance_toggle key at all, like an old-format replay")
	assert_false(due[0].has("reform_toggle"),
			"a LEAVE toggle carries no reform_toggle key at all, like an old-format replay")


func test_save_load_round_trips_a_delegation_orders_group_id() -> void:
	# Battle AI phase 4 (docs/battle-ai-design.md): a player-delegation toggle
	# (Battle.enqueue_delegation, target ORDER_DELEGATION_ONLY = -12) rides the "frontage"
	# field as group_id + 1 -- see enqueue_delegation's own doc comment for why the +1 shift
	# is load-bearing, not incidental.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -12, 0, 0, 6)   # -12 = ORDER_DELEGATION_ONLY, group 5
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the delegation order round-trips")
	assert_eq(int(due[0].get("frontage", 0)) - 1, 5,
			"the encoded group id (5) round-trips through save/load")


func test_delegating_to_group_0_round_trips_distinctly_from_an_omitted_frontage() -> void:
	# Regression coverage for the exact hazard enqueue_delegation's own doc comment names:
	# Replay.record_order OMITS "frontage" from the saved entry whenever the value is exactly
	# 0 (its own "old replays stay compact" convention), and group id 0 IS a legitimate
	# delegation target (Ctrl+Shift+0) -- without the +1 encoding shift, delegating to group 0
	# would round-trip identically to an order that never touched delegation at all, silently
	# decoding back as a revoke instead of "delegated to group 0".
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -12, 0, 0, 1)   # group 0 encoded as frontage=1
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1)
	assert_true(due[0].has("frontage"),
		"group 0 encodes as a nonzero frontage (1), so it's never omitted -- unlike an actual "
		+ "revoke (group_id Unit.UNDELEGATED = -1 encodes to frontage 0, which IS omitted, and "
		+ "correctly decodes right back to UNDELEGATED on an absent key)")
	assert_eq(int(due[0]["frontage"]) - 1, 0, "decodes back to group 0, not UNDELEGATED (-1)")


func test_save_load_round_trips_a_checkerboard_form_ups_line_index() -> void:
	# A checkerboard (acies triplex) deploy assigns each slice a persistent line index
	# (Unit.line_index, carried on the order as "line" -- see Battle.enqueue_form_up). That
	# assignment has to survive save/load like every other order field: without it a REPLAYED
	# recording of the same deploy reaches Battle._apply_order_cmd with no "line" key at all,
	# which reads as LINE_INDEX_UNCHANGED, so every unit keeps whatever line it already had
	# and the recorded front/reserve split silently vanishes -- a live-vs-replay divergence,
	# since the live session assigned the lines the instant the drag was released.
	var r := _fresh()
	r.start_recording()
	# Two slices of one checkerboard drag (shared form-up group 2): front line, then reserve.
	r.record_order(5, [11], Vector2(10, 20), -1, 0, 0, 4, 0.5, 0, 0.0, 2, 0, 0, -1, 0)
	r.record_order(5, [12], Vector2(30, 60), -1, 0, 0, 4, 0.5, 0, 0.0, 2, 0, 0, -1, 1)
	var path: String = r.save("Test", 5)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 2, "both checkerboard slices round-trip")
	assert_eq(int(due[0].get("line", -1)), 0,
			"the front-line slice's line index round-trips through save/load, not just live")
	assert_eq(int(due[1].get("line", -1)), 1,
			"the reserve slice reads back on line 1, not demoted to the front line")


func test_a_plain_form_up_omits_the_line_index_on_round_trip() -> void:
	# An ordinary drag-to-form-up assigns no line of its own, so it records the
	# LINE_INDEX_UNCHANGED sentinel (-1) and the key is omitted on save -- matching the
	# in-memory record_order behaviour for every other optional field, and keeping a replayed
	# plain drag from demoting a reserve-line unit back to the front line.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [0], Vector2.ZERO, -1, 0, 0, 4, 0.5)   # a plain form-up, no line
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1)
	assert_false(due[0].has("line"),
			"a plain form-up carries no line key at all, like a pre-line-index replay")


func test_a_replay_recorded_before_the_line_index_field_still_loads() -> void:
	# Back-compat: a replay saved before this field existed has no "line" key on any order.
	# It must still load and play, with no key invented on the way in -- _apply_order_cmd's
	# missing-key read is the same "leave it alone" case as the explicit sentinel, so those
	# replays behave exactly as they did before.
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [11], Vector2(10, 20), -1, 0, 0, 4, 0.5, 0, 0.0, 2, 0, 0, -1, 1)
	var path: String = r.save("Test", 5)
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for o in data["orders"]:
		o.erase("line")   # simulate a replay file saved before the field existed
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

	var loaded := _fresh()
	assert_true(loaded.start_playback(path),
			"a replay with no line key on any order still loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the order itself round-trips unchanged")
	assert_false(due[0].has("line"),
			"no line key is invented on load -- the order reads as LINE_INDEX_UNCHANGED")


func test_a_loaded_replays_line_index_reaches_the_unit_through_apply_order_cmd() -> void:
	# End to end along the path Battle actually takes on playback: record a checkerboard
	# slice deploying a unit to a reserve line, save it, load it, pull the order back with
	# orders_for_tick, and hand that order to Battle._apply_order_cmd -- which is exactly
	# what Battle._physics_process does for every recorded order. The unit has to come out
	# on the RECORDED line: drop the "line" key anywhere between record_order and the load
	# and _apply_order_cmd reads LINE_INDEX_UNCHANGED instead, silently leaving the unit on
	# whatever line it already had (0, the front line, for a freshly spawned one).
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [7], Vector2(200, 300), -1, 0, 0, 4, 0.5, 0, 0.0, -1, 0, 0, -1, 2)
	var path: String = r.save("Test", 5)

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var due: Array = loaded.orders_for_tick(5)
	assert_eq(due.size(), 1, "the form-up order is due at its recorded tick")

	var fixture: Array = _battle_with_unit(7, Vector2.ZERO)
	var b = fixture[0]
	var u: Unit = fixture[1]
	assert_eq(u.line_index, 0, "a freshly spawned unit starts on the front line")

	b._apply_order_cmd(due[0])
	assert_eq(u.line_index, 2,
			"the recorded line index survives save/load and is written onto the unit by " +
			"the same _apply_order_cmd call playback makes -- not only by a live order")


func test_the_recording_drain_carries_a_form_ups_line_index_into_the_replay() -> void:
	# The one seam the script-only tests above can't reach: Battle._physics_process's own
	# per-tick drain, which is what actually hands a live order to Replay.record_order. A
	# real ticking Battle is needed because the drain reads _pending_orders on the tick
	# AFTER the order is enqueued. Drop the line argument from that call and every other
	# test here still passes -- the order simply reaches the replay stream with no "line"
	# key, and the recorded deployment loses its front/reserve split on playback.
	var prev_mode: int = Replay.mode
	Replay.forced_seed = 148401
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [{"team": 0, "type": "Infantry", "x": 500, "y": 700, "count": 20}]
	# No team 1, so nothing ends the battle out from under us. Set BEFORE the node enters
	# the tree, per drill_mode's own doc comment -- _ready() is what reads it.
	battle.drill_mode = true
	add_child_autofree(battle)   # _ready() -> Replay.start_recording(): mode = RECORD
	await get_tree().physics_frame

	var spawned: Array = get_tree().get_nodes_in_group("units")
	assert_gt(spawned.size(), 0, "the scenario spawned a unit to order")
	var u: Unit = spawned[0] as Unit
	var uid: int = u.uid
	battle.enqueue_form_up([uid], Vector2(500, 600), 0.0, 5,
			BattleScript.OrderMode.NORMAL, false, -1, 1)
	await get_tree().physics_frame   # the drain records the pending order on the next tick

	var recorded: Dictionary = {}
	for o in Replay._orders:
		if int(o.get("target", 0)) == -1 and (o["units"] as Array).has(uid):
			recorded = o
	assert_false(recorded.is_empty(), "the form-up order reached the replay stream")
	assert_eq(int(recorded.get("line", BattleScript.LINE_INDEX_UNCHANGED)), 1,
			"the drain forwards the pending form-up's line index to Replay.record_order, " +
			"so the recorded order carries the reserve line the deploy assigned")

	Replay.mode = prev_mode
