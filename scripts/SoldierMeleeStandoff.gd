class_name SoldierMeleeStandoff
## Sustained reach-asymmetric melee standoff. The per-soldier reach model already gives a
## longer-reach weapon (e.g. spear, reach 48) the opening-strike advantage on approach over a
## shorter-reach weapon (e.g. sword, reach 26) -- the spear lands hits before the sword is in
## range at all. What's missing is the SUSTAINED case: once both sides lock in melee,
## SoldierEnemyContact's per-tick contact impulses and Unit._separate()'s reach-independent
## front-depth floor (deliberately reach-independent -- see its own comment, "a spear's reach
## standoff is meant to emerge from knockback, not a separation rule") together settle both
## sides to a common distance regardless of weapon. This pass makes the standoff actually
## HOLD: it writes a per-soldier velocity bias into each engaged soldier's `_sim_steer` that
## backs a longer-reach soldier away once its shorter-reach foe closes in, and pushes a
## shorter-reach soldier forward until it closes inside its OWN reach -- composing with the
## existing physics (formation arrival, friendly steering, enemy contact, knockback) rather
## than a regiment-level kite, which the design doc (docs/individual-collision-design.md)
## explicitly rejects as risking oscillation/jitter at the regiment level.
##
## Determinism: each engaged soldier's bias is computed independently from the frozen
## SoldierEnemyProximity snapshot (itself a pure function of positions already fixed for this
## tick) and written only into that soldier's own unit's `_sim_steer` entry -- unlike
## SoldierSteering/SoldierEnemyContact, there is no shared accumulator or cross-unit pairing
## to canonicalize, so the order `units` is iterated in doesn't affect the result. No RNG, no
## instance-id / wall-clock -- replay-safe like the rest of the soldier layer.

# Bias magnitude (world units/sec) a fully-committed standoff applies -- similar in spirit to
# SoldierSteering.STEER_STRENGTH (60.0). Started at 40.0 (a bit below the friendly-steering
# strength, since this composes ON TOP of it and both feed the same bounded-accel arrival) and
# held there: verified empirically against a two-unit reference demo (a stationary spear
# regiment locked against a marching sword regiment) that it holds a real standoff gap without
# blowing past sane per-soldier speeds or fighting the arrival/couple physics into oscillation.
const STANDOFF_STRENGTH: float = 40.0


## The reach-asymmetric standoff bias for one soldier at `pos` (reach `my_reach`) against its
## nearest enemy at `enemy_pos` (reach `enemy_reach`).
##
## - Equal reach: always zero -- the symmetric case is untouched; nothing to hold either way.
## - I outreach the enemy (`my_reach > enemy_reach`): zero while the enemy is still beyond MY
##   OWN reach (nothing to hold yet -- I'm not even threatened). Once it has closed inside my
##   reach, back AWAY, ramping from zero right at my own reach edge to full strength once the
##   enemy has closed all the way to ITS OWN reach -- the point a step further and it becomes a
##   real reciprocal threat, not just a target I can still hit from a safe remove.
## - I'm outreached (`my_reach < enemy_reach`): zero once the enemy is already within MY OWN
##   reach (I can already strike back -- closing further gains nothing). Otherwise press
##   TOWARD the enemy at full strength, closing the gap to get inside my own reach and negate
##   their advantage.
##
## A co-located pair (d ~ 0) has no defined bearing to back away along or press toward.
## Falls back to a fixed direction (Vector2.RIGHT) rather than dividing by zero -- mirroring
## the co-located fallback convention SoldierSteering._pair_push and SoldierEnemyContact.
## accumulate already use elsewhere in the soldier layer. This is a near-measure-zero case in
## practice (a real reach mismatch that also happens to land exactly co-located), so the
## fallback only needs to be stable, not physically meaningful -- and in the one branch that
## can actually reach it (backing away, since the pressing branch returns zero once d <= my_reach
## and 0 is always <= a positive reach), it still produces a real nonzero bias in some
## direction rather than silently doing nothing.
static func standoff_bias(pos: Vector2, enemy_pos: Vector2, my_reach: float, enemy_reach: float) -> Vector2:
	if is_equal_approx(my_reach, enemy_reach):
		return Vector2.ZERO
	var offset: Vector2 = pos - enemy_pos
	var d: float = offset.length()
	var away_dir: Vector2 = offset / d if d > 0.01 else Vector2.RIGHT
	if my_reach > enemy_reach:
		if d >= my_reach:
			return Vector2.ZERO   # not even in my own reach -- nothing to hold
		var closed_frac: float = clampf((my_reach - d) / maxf(my_reach - enemy_reach, 0.01), 0.0, 1.0)
		return away_dir * (STANDOFF_STRENGTH * closed_frac)
	else:
		if d <= my_reach:
			return Vector2.ZERO   # already inside my own reach -- I can already strike
		return -away_dir * STANDOFF_STRENGTH


## Recompute the standoff bias for every engaged soldier this tick, ADDING it into
## `_sim_steer` (never overwriting). Must run AFTER SoldierSteering.accumulate (which
## clears+rewrites the array with the friendly-avoidance bias -- this composes on top of it,
## it doesn't replace it) and BEFORE UnitRef.step_all_sim_soldiers reads `_sim_steer` as this
## tick's feed-forward. `frame` keys SoldierEnemyProximity's rebuild -- callers should pass
## the SAME frame value SoldierSteering.accumulate already used this tick (not a distinct
## offset key, unlike SoldierEnemyContact's own cache key), so a SQUARE unit's
## engaged_soldier_indices() call elsewhere in the same tick shares this rebuild instead of
## re-scanning every living soldier a second time.
static func accumulate(units: Array, frame: int) -> void:
	SoldierEnemyProximity.rebuild(units, frame)
	for o in units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD:
			continue
		var n: int = u._sim_soldier_pos.size()
		if n == 0 or u._sim_steer.size() != n:
			continue
		var r: float = u.soldier_body_radius()
		var reach: float = u.soldier_reach()
		for i in u.engaged_soldier_indices(n):
			var enemy: Dictionary = SoldierEnemyProximity.nearest_enemy(u._sim_soldier_pos[i], u.team, r, reach)
			if enemy.is_empty():
				continue
			u._sim_steer[i] += standoff_bias(u._sim_soldier_pos[i], enemy["position"], reach, enemy["reach"])
