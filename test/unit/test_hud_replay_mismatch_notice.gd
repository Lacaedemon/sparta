extends GutTest
## HUD._ready() shows a one-shot notice when Replay.last_load_sha_mismatch is set going into
## a PLAYBACK scene load, then clears it so a later _ready() (a fresh scene reload that
## didn't just load a mismatched file) doesn't re-show a stale message.

const HUDScript = preload("res://scripts/HUD.gd")
const BuildInfoScript = preload("res://scripts/BuildInfo.gd")


func after_each() -> void:
	Replay.reset()
	Replay.last_load_sha_mismatch = ""


func test_shows_the_mismatch_notice_during_playback() -> void:
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.last_load_sha_mismatch = "deadbeef"

	var h := HUDScript.new()
	add_child_autofree(h)

	assert_true(h._error_dialog.visible, "the mismatch is surfaced to the player")
	assert_true(h._error_dialog.dialog_text.contains("deadbeef"),
			"names the recorded replay's commit")
	assert_true(h._error_dialog.dialog_text.contains(BuildInfoScript.COMMIT_SHA),
			"...and this build's commit for comparison")


func test_clears_the_notice_so_it_is_one_shot() -> void:
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.last_load_sha_mismatch = "deadbeef"

	var h := HUDScript.new()
	add_child_autofree(h)

	assert_eq(Replay.last_load_sha_mismatch, "",
			"cleared immediately so a later _ready() doesn't re-show a stale message")


func test_no_notice_when_nothing_mismatched() -> void:
	Replay.mode = Replay.Mode.RECORD
	Replay.last_load_sha_mismatch = ""

	var h := HUDScript.new()
	add_child_autofree(h)

	assert_false(h._error_dialog.visible, "no mismatch, no notice")


func test_no_notice_outside_playback_even_with_a_stale_mismatch_value() -> void:
	# Defense-in-depth: a leftover mismatch value from a prior playback shouldn't resurface
	# during ordinary live-battle recording.
	Replay.mode = Replay.Mode.RECORD
	Replay.last_load_sha_mismatch = "deadbeef"

	var h := HUDScript.new()
	add_child_autofree(h)

	assert_false(h._error_dialog.visible, "only PLAYBACK mode triggers the notice")
