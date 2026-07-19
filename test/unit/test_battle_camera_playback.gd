extends GutTest
## Battle._physics_process's own camera-track playback: when Replay drives a recorded
## presentation track (demo/replay), the live camera eases toward each keyframe at
## Battle.camera_smoothing's rate (default Battle.CAMERA_SMOOTHING) rather than snapping.
## Covers the lerp application itself -- CameraController's separate "input yields to a
## presentation track" behavior is tested in test_camera_controller.gd; Replay's own
## camera_for_tick keyframe-stepping logic is tested in test_replay.gd.

const BattleScript = preload("res://scripts/Battle.gd")


## Arms a two-keyframe presentation track (tick 0 at the origin framing, tick 1 far away),
## spawns a live battle with the given camera_smoothing, and waits through tick 1's own
## _physics_process (the one that eases toward the second keyframe) before reading the
## camera's resulting position. Restores the shared Replay autoload afterward.
func _drive_one_keyframe_step(camera_smoothing: float) -> Vector2:
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.drive_camera = true
	Replay._camera_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0},
		{"tick": 1, "x": 500.0, "y": 500.0, "zoom": 2.0},
	]
	Replay._camera_index = 0

	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.camera_smoothing = camera_smoothing
	add_child_autofree(battle)

	# Wait through tick 1's own _physics_process (the one that reads the second keyframe
	# and eases toward it) -- a bare single await races _tick's post-processing increment.
	while battle.current_tick() <= 1:
		await get_tree().physics_frame

	var pos: Vector2 = battle._camera.position
	Replay._camera_track = []
	Replay.reset()
	return pos


func test_camera_smoothing_default_matches_the_documented_const() -> void:
	var pos: Vector2 = await _drive_one_keyframe_step(BattleScript.CAMERA_SMOOTHING)
	assert_almost_eq(pos.x, 500.0 * BattleScript.CAMERA_SMOOTHING, 0.5,
			"the default camera_smoothing field eases by exactly CAMERA_SMOOTHING's fraction")


func test_camera_smoothing_override_snaps_fully_when_set_to_one() -> void:
	var pos: Vector2 = await _drive_one_keyframe_step(1.0)
	assert_almost_eq(pos.x, 500.0, 0.01,
			"overriding camera_smoothing to 1.0 fully closes the distance to the recorded keyframe in one tick")
