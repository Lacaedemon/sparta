extends GutTest
## tools/benchmark/BenchmarkRunner.gd -- the live battle-driving part isn't unit-testable
## (same reason DemoInputRecorder.gd's scene-driving isn't; see tools/benchmark/README.md), so
## this only covers the one piece of _ready() that runs synchronously before the battle starts
## and doesn't need a live battle: forcing SFX off for the run.
##
## Regression guard for #628: a benchmark run can leak an AudioStreamWAV/AudioStreamPlaybackWAV
## at process exit if a pooled Sfx voice is still mid-playback when get_tree().quit() tears
## down the tree. BenchmarkRunner never intends to produce audio (it measures physics-step
## time only), so it forces Settings.sfx_enabled off for the run -- which also prevents any
## voice from ever starting a live playback, eliminating the leak at the source rather than
## trying to stop voices after the fact.

const BenchmarkRunnerScene := preload("res://tools/benchmark/BenchmarkRunner.tscn")

var _prior_sfx_enabled: bool


func before_each() -> void:
	# set_sfx_enabled_session() doesn't persist to disk, but it does mutate the live
	# Settings.sfx_enabled property (shared autoload state) -- save/restore around the test
	# so this doesn't leak into other tests, mirroring the Settings-safety pattern used
	# elsewhere in this suite.
	_prior_sfx_enabled = Settings.sfx_enabled
	Settings.set_sfx_enabled_session(true)   # start "on" so the assertion is meaningful


func after_each() -> void:
	Settings.set_sfx_enabled_session(_prior_sfx_enabled)


func test_ready_forces_sfx_off_for_the_run() -> void:
	var runner: Node = BenchmarkRunnerScene.instantiate()
	# _ready() runs synchronously on add_child(); the actual battle only starts on the
	# call_deferred() queued at the end of _ready(), so freeing right after add_child()
	# never lets a battle spin up.
	add_child_autofree(runner)
	assert_false(Settings.sfx_enabled,
		"BenchmarkRunner disables SFX for the run so no voice can leak a stream at exit")
