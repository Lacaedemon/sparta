extends GutTest
## Lockstep A/B sim-hash instrument (0 A.D.'s -rejointest pattern), two-pass form.
##
## Runs the SAME seed + scenario through scenes/Battle.tscn TWICE -- pass A to completion
## capturing a per-tick hash stream, a HARD RESET of every global sim static in between,
## then pass B -- and asserts the two streams are byte-identical via
## DemoHashStream.compare_streams. A divergence localizes the leaking static to the exact
## tick (and tier) it first appears.
##
## This categorically catches the "sim reads state that isn't part of the replay inputs"
## bug class this codebase has otherwise only found incident-by-incident: a global static
## left set between runs (PathField.active / ProjectileField.active), a frame-keyed cache
## whose reset discipline broke (SoldierSpatialHash / SoldierEnemyProximity /
## SoldierEngagedEnemyProximity), or Replay.rng seed leakage. If a future sim change starts
## reading un-reset global state, or a new static is added without a matching reset here,
## the two passes diverge and this test names the tick.
##
## Two-pass (not true same-tick lockstep) is the deliberate first cut: two live Battle
## instances in one process share Replay (an autoload, so one RNG stream) and the
## process-global sim statics, so a genuine simultaneous A/B needs those made per-instance
## first -- an architectural change out of scope here. The two-pass form still catches the
## static-leakage / suite-order class; it does not catch same-tick interference between two
## concurrently-stepping battles (a possible future upgrade if the sim statics ever become
## per-instance).

## A seed with an eventful, non-trivial clash under it -- team 1's AI advances into the
## stationary team 0 and both trade RNG-drawn strikes, so the hash exercises real combat
## state (positions, casualties, morale, the RNG), not an idle field.
const SEED := 424242
## Enough ticks for the two blocks to close, clash, and fight for a stretch, while staying
## short of annihilation so neither battle ends early (an ended battle stops advancing
## current_tick(), which would stutter the stream).
const TICKS := 150

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	# Leave the sim statics clean for the next test regardless of how this one exited.
	_reset_all_sim_statics()
	await get_tree().physics_frame


## Hard-reset every process-global sim static between the two passes -- the authoritative
## "everything the sim could read across runs is zeroed" list, so this test doubles as the
## living registry of that state. Battle's own _exit_tree() already releases
## PathField/ProjectileField and resets SpatialHash / SoldierSpatialHash; the
## SoldierEnemyProximity / SoldierEngagedEnemyProximity frame-keyed caches it does NOT reset
## self-heal here anyway (they key on the monotonic Engine.get_physics_frames(), which never
## repeats across two sequential passes), so resetting them is defense-in-depth rather than
## load-bearing today. Both are listed regardless: a FUTURE static keyed on something
## battle-local (a per-tick counter that restarts at 0, say) would leak between passes, and
## the whole point of this instrument is that adding such a static without a matching reset
## here makes the two passes diverge loudly instead of flaking a later test by suite order.
func _reset_all_sim_statics() -> void:
	PathField.active = null
	ProjectileField.active = null
	SpatialHash.reset()
	SoldierSpatialHash.reset()
	SoldierEnemyProximity.reset()
	SoldierEngagedEnemyProximity.reset()


## Run one battle pass from `seed` and return its per-tick hash stream (the same
## {tick, cheap, full?} entry shape DemoHashStream writes to disk and compare_streams
## reads). `full` is present only on the FULL_EVERY cadence, matching the on-disk stream.
## `seed` is the argument so a positive-control test can deliberately mis-seed one pass.
func _run_pass(seed: int) -> Array:
	Replay.forced_seed = seed   # consumed by Battle._ready's start_recording(); re-seeds Replay.rng
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 520, "count": 60},
		{"team": 1, "type": "Infantry", "x": 800, "y": 360, "count": 60},
	]
	# Add the battle while the tree is PAUSED, then unpause on a frame boundary, so both
	# _physics_process (which advances _tick) and _on_soldier_tick (which steps the soldier
	# bodies) begin together on the same frame in BOTH passes. Without this, whether
	# _on_soldier_tick fires on the same frame as the first _physics_process is a startup
	# phase race -- it leaves the two passes with a one-step offset between the body-step
	# count and _tick, so identical seeds produce sub-pixel-divergent settling at the same
	# tick number. Pausing suppresses both (the soldier tick early-returns while paused,
	# _physics_process doesn't run at all), so the unpause is the single shared start line.
	get_tree().paused = true
	add_child(_battle)
	await get_tree().physics_frame   # spawn the armies; nothing steps while paused
	get_tree().paused = false

	var stream: Array = []
	var last_tick: int = -1
	for _i in range(TICKS):
		await get_tree().physics_frame
		var tick: int = _battle.current_tick()
		if tick == last_tick:
			break   # battle ended -- current_tick() has stopped advancing; stop sampling
		last_tick = tick
		var entry: Dictionary = {"tick": tick, "cheap": DemoStateHash.cheap_tick_hash(get_tree())}
		if tick % DemoHashStream.FULL_EVERY == 0:
			entry["full"] = DemoStateHash.full_tick_hash(get_tree(), Replay.rng.state)
		stream.append(entry)

	_battle.free()
	_battle = null
	await get_tree().physics_frame
	return stream


func test_two_pass_ab_hash_streams_are_identical() -> void:
	var stream_a: Array = await _run_pass(SEED)
	_reset_all_sim_statics()
	var stream_b: Array = await _run_pass(SEED)

	var verdict: Dictionary = DemoHashStream.compare_streams(stream_a, stream_b)

	# A meaningful window actually ran -- guards against a scenario that ends instantly or a
	# loop that no-ops, either of which would make an "identical" verdict vacuous.
	assert_gt(int(verdict["compared"]), 100,
			"the two passes compared a meaningful number of ticks (got %d)" % int(verdict["compared"]))
	assert_false(verdict["divergent"],
			"two same-seed passes with every global sim static reset between them produce " \
			+ "byte-identical per-tick hash streams -- a divergence means the sim read " \
			+ "state outside the replay inputs (verdict: %s)" % str(verdict))


## Positive control: the instrument is only a guard if it actually fails when the two runs
## genuinely diverge. Seeding pass B differently feeds Replay.rng (the shared autoload the
## whole sim draws combat randomness from) a different stream, so the two battles reach
## different strike outcomes and their hash streams must diverge. This proves the test above
## isn't vacuously green -- a future change that made the hash a constant, or compare_streams
## always-clean, would fail HERE.
func test_the_instrument_detects_a_divergence() -> void:
	var stream_a: Array = await _run_pass(SEED)
	_reset_all_sim_statics()
	var stream_b: Array = await _run_pass(SEED + 1)   # a different RNG stream

	var verdict: Dictionary = DemoHashStream.compare_streams(stream_a, stream_b)

	assert_true(verdict["divergent"],
			"two DIFFERENTLY-seeded passes must diverge -- if this passes as 'not divergent' " \
			+ "the instrument is blind and the identical-streams test above is meaningless " \
			+ "(verdict: %s)" % str(verdict))
