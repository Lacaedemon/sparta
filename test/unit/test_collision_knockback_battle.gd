extends GutTest
## Knockback stays bounded through a full line collision in a LIVE battle: run the
## landing-page showcase matchup (seed 12345, default 5v5 line spawn, no orders) tick by
## tick through the melee press and assert that no engaged soldier body is ever launched —
## its per-tick displacement stays under a bound derived from the sim's own constants.
## Regression guard for the flying-soldier bug: unbounded stacking of per-strike knockback
## impulses (several attackers shoving the same body in one cadence) drove bodies to
## ~200 wu/s, which the bounded 30 wu/s^2 recovery took seconds — and most of the
## battlefield — to bleed off. With the per-strike cumulative cap, an engaged body's speed can
## never exceed the knockback ceiling on top of its own steering + arrival budget.
##
## The bound, from the dynamics themselves (SoldierBodies.step): an engaged body's desired
## velocity is friendly-avoidance steering (~STEER_STRENGTH) plus the arrival term (capped
## at the unit's jog pace); a knockback can raise its speed to at most
## max(previous speed, KNOCKBACK_SPEED_MAX); and one tick of bounded acceleration on top.
## March carry-in (a body still bleeding charge speed from before contact) decays at
## BODY_ACCEL_FLOOR, so each unit is only asserted once it has been engaged continuously
## long enough for that carry-in to have decayed below the bound.

# Run through the infantry press of the seed-12345 showcase: the launches observed
# before the fix (bodies at 210+ wu/s in the mid-press, around ticks ~600-880 — the
# exact tick drifts as unrelated sim features land, most recently ~853 at 216 wu/s)
# fall inside this window, well past every foot unit's settle time, so a regression
# trips the assert deterministically.
const CLASH_END_TICK: int = 900


func test_no_soldier_launches_through_the_showcase_line_collision() -> void:
	Replay.forced_seed = 12345   # the landing-page showcase battle, before add_child
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)

	var delta: float = 1.0 / float(Replay.PHYSICS_TPS)
	var engaged_since := {}   # Unit -> tick its current continuous engagement began
	var prev_pos := {}        # Unit -> PackedVector2Array (last tick's body positions)
	var prev_tick: int = battle.current_tick()
	var worst_excess: float = -INF   # max over all samples of (step - bound); < 0 = clean
	var worst_note := ""

	while battle.current_tick() < CLASH_END_TICK:
		await get_tree().physics_frame
		var tick: int = battle.current_tick()
		var stepped_one: bool = tick == prev_tick + 1
		for node in get_tree().get_nodes_in_group("units"):
			var u: Unit = node as Unit
			if u == null or u.state == Unit.State.DEAD:
				continue
			# Track continuous engagement; any gap restarts the settle clock.
			if u.is_engaged():
				if not engaged_since.has(u):
					engaged_since[u] = tick
			else:
				engaged_since.erase(u)
			var n: int = u._sim_soldier_pos.size()
			var prev: Variant = prev_pos.get(u)
			# Assert only on a clean single-tick step with no casualty compaction (a death
			# re-packs the arrays, so indices no longer pair up across the two snapshots).
			if stepped_one and prev != null and (prev as PackedVector2Array).size() == n \
					and engaged_since.has(u) and tick - int(engaged_since[u]) >= _settle_ticks(u):
				var bound: float = _engaged_step_bound(u, delta)
				var prev_arr: PackedVector2Array = prev
				for i in u.engaged_soldier_indices(n):
					var step: float = prev_arr[i].distance_to(u._sim_soldier_pos[i])
					if step - bound > worst_excess:
						worst_excess = step - bound
						worst_note = "tick %d unit uid%d soldier %d: %.3f wu/tick (bound %.3f)" \
								% [tick, u.uid, i, step, bound]
			prev_pos[u] = u._sim_soldier_pos.duplicate()
		prev_tick = tick

	assert_true(worst_excess <= 0.0,
			"no engaged body ever exceeds its per-tick knockback/steering/arrival budget through the line collision (worst: %s)" % worst_note)


## Per-tick displacement bound for an ENGAGED body of `u` (world units per tick): the
## knockback ceiling, plus the enemy-contact ceiling (SoldierEnemyContact -- capped at the
## same KNOCKBACK_SPEED_MAX, see SoldierCollision.enemy_contact_impulse), plus the
## friendly-avoidance steering feed-forward, plus the arrival term at the unit's jog pace,
## plus one tick of bounded acceleration of slack. Every term comes from the shipped
## constants, so the bound moves with any future retuning.
func _engaged_step_bound(u: Unit, delta: float) -> float:
	var body_accel: float = maxf(u.accel, SoldierBodies.BODY_ACCEL_FLOOR)
	var speed_bound: float = SoldierCombat.KNOCKBACK_SPEED_MAX + SoldierCombat.KNOCKBACK_SPEED_MAX \
			+ SoldierSteering.STEER_STRENGTH + u.jog_speed + body_accel * delta
	return speed_bound * delta


## Ticks after first contact before `u`'s bodies are asserted: long enough for a body
## still carrying full march speed from the approach (up to move_speed, above the
## knockback ceiling) to have bled the surplus at the bounded recovery acceleration,
## plus half a second of margin.
func _settle_ticks(u: Unit) -> int:
	var surplus: float = maxf(0.0, u.move_speed - SoldierCombat.KNOCKBACK_SPEED_MAX)
	var decay_s: float = surplus / SoldierBodies.BODY_ACCEL_FLOOR
	return int(ceil(decay_s * float(Replay.PHYSICS_TPS))) + Replay.PHYSICS_TPS / 2
