extends GutTest
## HUD surfaces a loaded replay's spawn-layout mismatch. Battle._ready sets
## Replay.last_load_spawn_mismatch AFTER it spawns -- later than this HUD's own _ready, since
## HUD is a child of Battle -- so HUD schedules the check one idle frame later. These cover the
## deferred warning and its one-shot clear.

const HUDScript = preload("res://scripts/HUD.gd")


func after_each() -> void:
	Replay.reset()
	Replay.last_load_spawn_mismatch = ""


func _hud() -> CanvasLayer:
	var hud = HUDScript.new()
	add_child_autofree(hud)
	return hud


func test_a_flagged_mismatch_warns_once_and_clears_the_flag() -> void:
	# A HUD coming up in playback with the flag already set warns on the next idle frame (once
	# Battle._ready's deferred-set flag is visible) and clears it one-shot.
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.last_load_spawn_mismatch = "stale-fingerprint"
	_hud()
	await get_tree().process_frame   # let the deferred _warn_spawn_layout_mismatch run
	await get_tree().process_frame
	assert_eq(Replay.last_load_spawn_mismatch, "",
			"the deferred warning fires once and clears the flag")


func test_no_flag_is_a_no_op() -> void:
	# The clean-load case: the deferred check with no flag set returns without warning.
	var hud := _hud()
	Replay.last_load_spawn_mismatch = ""
	hud._warn_spawn_layout_mismatch()
	assert_eq(Replay.last_load_spawn_mismatch, "", "no flag set means nothing happens")
