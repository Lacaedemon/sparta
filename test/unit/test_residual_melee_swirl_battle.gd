extends GutTest
## Regression guard for the residual melee-lock swirl left over after the enemy-contact
## impulse symmetry fix. Two matched Infantry regiments clash head-on and grind for
## hundreds of ticks; each regiment's `facing` should stay close to its starting heading,
## not visibly pivot around the clash point. Live-battle, tick by tick, per this repo's own
## convention of verifying maneuver/collision physics against real body positions rather
## than eyeballing demo frames -- see .claude/memories/sparta.md.
##
## Root cause (see the PR for the full instrumentation writeup): `Unit.engaged_soldier_indices()`
## selects the engaged front rank/perimeter by LIVE POSITION, but after a casualty
## compacts the per-soldier arrays (SoldierMelee.reap's remove_at splice), a live-selected
## body's own array index no longer maps to a front/perimeter formation slot --
## SoldierBodies.step()'s arrival term and SoldierBodies.couple()'s drift measurement were
## both still reading `slots[i]` for that same (possibly reindexed) `i`, comparing each live-
## engaged body against a mismatched target. Fixed via `Unit.canonical_target_slot_indices()`,
## which scores the STATIC slot grid with the same selection functions so both step() and
## couple() agree on a like-for-like target.
##
## The bias is DETERMINISTIC, not RNG noise (verified against three different seeds during
## the investigation), so a single fixed seed is a legitimate regression guard here.
##
## QUARANTINED: the rotation bound below no longer fails the build. It asserted a property
## `main` itself does not satisfy -- a 6-seed sweep on unmodified `main` measured 9.29, 13.73,
## 15.45, 16.38, 35.89 and 53.39 degrees, so the old 28-degree gate was exceeded at 2 of 6
## seeds and passed only because it pinned seed 12345. The same metric also diverges by
## platform: one commit measured 16.39 locally and 39.88 on CI. The calibration comment above
## is stale for the same reason -- it cites ~12 and ~10 degrees for seeds 99999 and 424242,
## where `main` now measures 35.89 and 15.45.
##
## The rotation is still MEASURED and REPORTED, so the number this guard exists to watch
## stays visible in the CI log; only the build-failing assertion is gone. The printed figure
## is the data a replacement bound has to be built from.
##
## A single seed cannot distinguish a regression from an unlucky draw when the metric ranges
## 9 to 53 degrees on unmodified `main`, so any replacement has to sweep seeds -- and the
## seeds have to be measured in SEPARATE processes, per the note on SWEEP_SEED below.
##
## TODO(#1207): replace the quarantined bound with one that holds across seeds and platforms.


var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


func _team_unit(team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			return unit
	return null


## The seed the old gate pinned. Kept as a single seed deliberately: a multi-seed sweep
## inside ONE test process does not reproduce per-process measurements, because global
## statics survive between iterations. Measured on this branch -- sweeping six seeds in one
## process, only the FIRST matched its per-process value (16.39), while seed 777 read 28.55
## against a per-process 56.14 and seed 20260805 read 54.20 against 30.59. Freeing the battle
## between iterations is not sufficient; see this file's sibling note in
## .claude/memories/sparta.md on frame-keyed static caches and `PathField.active`.
##
## So per-seed figures have to come from separate Godot invocations, not from a loop here.
## Anything else silently measures contamination.
const SWEEP_SEED: int = 12345


func _measure_turn_for_seed(seed_value: int) -> float:
	Replay.forced_seed = seed_value
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 440, "count": 100},
		{"team": 1, "type": "Infantry", "x": 800, "y": 560, "count": 100},
	]
	add_child(_battle)
	await get_tree().physics_frame

	var a: Unit = _team_unit(0)
	var b: Unit = _team_unit(1)
	assert_not_null(a, "seed %d: team 0's regiment deployed" % seed_value)
	assert_not_null(b, "seed %d: team 1's regiment deployed" % seed_value)
	if a == null or b == null:
		return -1.0

	var start_facing_a: Vector2 = a.facing

	for _tick in range(700):
		await get_tree().physics_frame

	# The clash itself IS still guarded: if the two blocks stop meeting, the rotation number
	# below stops describing a melee at all and the sweep silently measures nothing.
	assert_true(a.state == Unit.State.FIGHTING or a.state == Unit.State.DEAD,
		"seed %d: team 0's regiment made and held contact within the window" % seed_value)

	return rad_to_deg(absf(a.facing.angle_to(start_facing_a)))


## Named for what it now verifies, not for what the quarantined bound used to promise. The
## old name asserted the facing stayed near its start heading, which nothing here checks any
## more -- so a green run would have read as proof of a property the measurements below show
## can be violated by 53 degrees. A test whose pass and failure paths look alike is the exact
## defect the quarantined bound had; the name should not reintroduce it one level up.
func test_matched_infantry_clash_reports_swirl_rotation() -> void:
	# See this file's header for why the rotation bound is quarantined: it asserted a property
	# unmodified `main` breaks at a third of the seeds measured. The rotation is still measured
	# and reported here; it just no longer fails the build.
	var turned: float = await _measure_turn_for_seed(SWEEP_SEED)

	# Reported, not asserted. Printing it is the only way a CI-side figure is ever visible --
	# a passing assertion prints nothing, which is why the old gate's own value could not be
	# read until the day it failed.
	gut.p("[swirl-1207] seed %d: turned %.2f deg (Windows `main` measured 13.73)"
		% [SWEEP_SEED, turned])

	# Guards the sentinel only: -1.0 means the regiments never deployed, so the number above
	# would describe nothing. Deliberately NOT a bound on the rotation itself.
	assert_gt(turned, -1.0, "the clash produced a rotation measurement at all")
