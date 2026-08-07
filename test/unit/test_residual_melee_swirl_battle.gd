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


func test_matched_infantry_clash_keeps_facing_close_to_its_start_heading() -> void:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 800, "y": 440, "count": 100},
		{"team": 1, "type": "Infantry", "x": 800, "y": 560, "count": 100},
	]
	add_child(_battle)
	await get_tree().physics_frame

	var a: Unit = _team_unit(0)
	var b: Unit = _team_unit(1)
	assert_not_null(a, "team 0's regiment deployed")
	assert_not_null(b, "team 1's regiment deployed")
	if a == null or b == null:
		return

	var start_facing_a: Vector2 = a.facing
	var start_facing_b: Vector2 = b.facing

	for _tick in range(700):
		await get_tree().physics_frame

	assert_true(a.state == Unit.State.FIGHTING or a.state == Unit.State.DEAD,
		"team 0's regiment made and held contact within the window")

	var turned_a: float = rad_to_deg(absf(a.facing.angle_to(start_facing_a)))
	var turned_b: float = rad_to_deg(absf(b.facing.angle_to(start_facing_b)))
	# Pre-canonical-slot-fix this scenario/seed rotates ~46° by tick 700; the canonical-slot
	# fix (the fix this file was originally written for) brought it down to ~37°. A further
	# fix -- pairing the engaged group with its canonical target slots rank-major (depth tier
	# first, then actual lateral position within the tier) instead of by raw array rank --
	# brings this same seed down to ~20°; the other two seeds used during that investigation
	# (99999, 424242) dropped to ~12° and ~10° respectively. 28° sits with margin below the
	# pre-this-fix ~37° and above the measured ~20° worst case across all three seeds, and the
	# mechanism is deterministic (not RNG-driven), so this is a real regression guard, not a
	# flaky threshold.
	assert_lt(turned_a, 28.0,
		"team 0's regiment does not visibly pivot around the clash point (turned %.1f°)" % turned_a)
	assert_lt(turned_b, 28.0,
		"team 1's regiment does not visibly pivot around the clash point (turned %.1f°)" % turned_b)
