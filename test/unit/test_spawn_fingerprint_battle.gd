extends GutTest
## The spawn-fingerprint stamp/check wired into the live battle lifecycle (Battle._ready +
## Replay): a recording publishes the fingerprint of the layout it ran on, and a playback whose
## loaded stamp no longer matches this build's spawn flags a mismatch. Standing up the full
## Battle scene is heavy, so each case spawns one default battle and asserts pre-tick.

const BATTLE_SCENE_PATH := "res://scenes/Battle.tscn"


func after_each() -> void:
	# Every case leaves global Replay state (mode/stamps) that a later test's battle would
	# inherit, so reset it. reset() only touches mode/camera flags; clear the stamp fields too.
	Replay.reset()
	Replay.spawn_fingerprint = ""
	Replay.loaded_spawn_fingerprint = ""
	Replay.last_load_spawn_mismatch = ""


func _spawn_default_battle() -> Node:
	var battle: Node = load(BATTLE_SCENE_PATH).instantiate()
	# add_child runs Battle._ready() synchronously, which spawns both default lines and then
	# stamps/checks the fingerprint. Assert immediately, before any physics frame.
	add_child_autofree(battle)
	return battle


func test_recording_publishes_the_live_layout_fingerprint() -> void:
	Replay.forced_seed = 12345   # deterministic, though the fingerprint is seed-independent
	_spawn_default_battle()
	assert_ne(Replay.spawn_fingerprint, "",
			"a live recording publishes a non-empty spawn fingerprint")
	assert_eq(Replay.spawn_fingerprint, SpawnFingerprint.of_tree(get_tree()),
			"the published fingerprint is exactly the freshly-spawned layout's")


func test_playback_of_an_unstamped_replay_is_not_gated() -> void:
	# A replay recorded before the stamp existed carries no fingerprint; the check must skip it
	# (the additive-field back-compat contract), never flag a mismatch.
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.rng.seed = 12345
	Replay.loaded_spawn_fingerprint = ""
	Replay.last_load_spawn_mismatch = ""
	_spawn_default_battle()
	assert_eq(Replay.last_load_spawn_mismatch, "",
			"an unstamped replay plays back without a spawn-mismatch flag")


func test_playback_of_a_stale_stamp_flags_a_mismatch() -> void:
	# A stamp that no longer matches this build's spawn layout (a spawn-table drift) is a real desync
	# signal: the orders were recorded against unit positions this build no longer produces.
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.rng.seed = 12345
	Replay.loaded_spawn_fingerprint = "stale-fingerprint-from-an-older-build"
	Replay.last_load_spawn_mismatch = ""
	_spawn_default_battle()
	assert_eq(Replay.last_load_spawn_mismatch, "stale-fingerprint-from-an-older-build",
			"a stale stamp raises the spawn-mismatch flag with the recorded fingerprint")
