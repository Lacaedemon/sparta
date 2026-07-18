class_name SoldierMeleeStandoff
## Sustained reach-asymmetric melee standoff. The per-soldier reach model already gives a
## longer-reach weapon (e.g. spear, reach 48) the opening-strike advantage on approach over a
## shorter-reach weapon (e.g. sword, reach 26) -- the spear lands hits before the sword is in
## range at all. That advantage already carries through the SUSTAINED case too, on its own:
## a soldier landing free hits (its enemy can't strike back until it closes the gap) keeps
## landing them, and every landed strike already applies real, physically-motivated knockback
## (SoldierMelee/SoldierCombat) that pushes the outreached enemy back -- ground-holding while
## the free hits land IS the longer-reach side's half of the standoff, with no extra force
## needed. This pass supplies only the OTHER half: a shorter-reach soldier actively presses
## toward its nearest enemy until it closes inside its own reach, so the outreached side
## doesn't simply stand still trading free hits for nothing -- it closes the gap to negate the
## mismatch. The longer-reach side never gets a synthetic backing-away bias -- an earlier
## version of this pass added one, but the "no top-down gimmicks" philosophy (see
## .claude/memories/sparta.md) treats existing knockback-from-landed-hits as the real,
## physically-motivated push-back mechanism; a second, synthetic shove on top of it would be
## exactly the kind of top-down gimmick that philosophy exists to avoid. (A "give ground" order
## -- an explicit player-facing stance that DOES retreat to hold reach distance, as a deliberate
## tactical choice rather than the passive default -- is tracked as a separate follow-up.)
## Per-individual, built on the individual-soldier collision layer.
##
## Determinism: each engaged soldier's bias is computed independently from the frozen
## SoldierEngagedEnemyProximity snapshot (itself a pure function of positions already fixed
## for this tick) and written only into that soldier's own unit's `_sim_steer` entry --
## unlike SoldierSteering/SoldierEnemyContact, there is no shared accumulator or cross-unit
## pairing to canonicalize, so the order `units` is iterated in doesn't affect the result. No
## RNG, no instance-id / wall-clock -- replay-safe like the rest of the soldier layer.

# Bias magnitude (world units/sec) a fully-committed press applies -- similar in spirit to
# SoldierSteering.STEER_STRENGTH (60.0). Started at 40.0 (a bit below the friendly-steering
# strength, since this composes ON TOP of it and both feed the same bounded-accel arrival) and
# held there: verified empirically against a two-unit reference demo (a stationary spear
# regiment locked against a marching sword regiment) that it holds a real standoff without
# blowing past sane per-soldier speeds or fighting the arrival/couple physics into oscillation.
const STANDOFF_STRENGTH: float = 40.0


## The reach-asymmetric standoff bias for one soldier at `pos` (reach `my_reach`) against its
## nearest enemy at `enemy_pos` (reach `enemy_reach`).
##
## - Equal-or-longer reach (`my_reach >= enemy_reach`): always zero. This soldier already
##   outreaches (or matches) its nearest enemy, so it does NOT back away to hold distance --
##   see this class's own doc comment for why: the existing landed-strike knockback already
##   IS the push-back mechanism, and this pass adds nothing on top of it for this side.
## - Outreached (`my_reach < enemy_reach`): zero once the enemy is already within MY OWN
##   reach (I can already strike back -- closing further gains nothing). Otherwise press
##   TOWARD the enemy at full strength, closing the gap to get inside my own reach and negate
##   their advantage.
##
## A co-located pair (d ~ 0) can never reach the division below: `d <= my_reach` (0 <= any
## non-negative reach) always returns zero first, so there's no live path where `d` is both
## past `my_reach` and near zero for any realistic (non-negative) reach value. `maxf(d, 0.01)`
## on the divisor is purely defensive -- it costs nothing and guards a theoretical
## negative-reach bug elsewhere, without needing a separate dead fallback branch.
static func standoff_bias(pos: Vector2, enemy_pos: Vector2, my_reach: float, enemy_reach: float) -> Vector2:
	if my_reach >= enemy_reach:
		return Vector2.ZERO
	var offset: Vector2 = enemy_pos - pos
	var d: float = offset.length()
	if d <= my_reach:
		return Vector2.ZERO   # already inside my own reach -- I can already strike
	return (offset / maxf(d, 0.01)) * STANDOFF_STRENGTH


## Recompute the standoff bias for every engaged soldier this tick, ADDING it into
## `_sim_steer` (never overwriting). Must run AFTER SoldierSteering.accumulate (which
## clears+rewrites the array with the friendly-avoidance bias -- this composes on top of it,
## it doesn't replace it) and BEFORE UnitRef.step_all_sim_soldiers reads `_sim_steer` as this
## tick's feed-forward.
##
## Since standoff_bias is now UNCONDITIONALLY zero whenever `my_reach >= enemy_reach` (see its
## own doc comment), only a soldier that could plausibly be OUTREACHED by some engaged enemy
## needs a nearest-enemy lookup at all -- a soldier whose own unit already has the longest
## reach among every opposing engaged unit can never get a nonzero bias, so querying for it
## would just resolve to zero every time. Pass 1 below computes each team's MIN and MAX reach
## among its own currently-engaged units (a cheap O(units) scan, no soldier-level work); pass 2
## gathers the full engaged tier (both teams) as CANDIDATES -- any of them could be the
## nearest enemy a plausibly-outreached soldier finds -- but only marks a unit's soldiers as
## QUERIERS (the ones that actually get a lookup + bias write) when that unit's reach is less
## than the max reach among the OTHER team(s)' engaged units. In the common case where every
## currently-engaged pairing shares the same reach (e.g. spear-vs-spear, or any single-type
## engagement), no team can outreach another and the whole pass skips straight past the
## per-soldier gather/rebuild/query entirely -- see _any_team_could_be_outreached below.
##
## The gathered candidate pool still spans BOTH teams' full engaged tier regardless of which
## side is querying -- a querying soldier's true nearest engaged enemy might turn out to have
## equal-or-shorter reach (bias resolves to zero for that specific pairing, same as before),
## but it's still the geometrically correct "nearest enemy" to evaluate against, so it can't
## be excluded from the candidate pool up front. Only the QUERY side is pruned.
static func accumulate(units: Array, frame: int) -> void:
	var min_reach_by_team: Dictionary = {}   # team (int) -> min soldier_reach() among its engaged units
	var max_reach_by_team: Dictionary = {}   # team (int) -> max soldier_reach() among its engaged units
	for o in units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD or not u.is_engaged():
			continue
		var r: float = u.soldier_reach()
		if r > max_reach_by_team.get(u.team, -1.0):
			max_reach_by_team[u.team] = r
		if not min_reach_by_team.has(u.team) or r < min_reach_by_team[u.team]:
			min_reach_by_team[u.team] = r

	if not _any_team_could_be_outreached(min_reach_by_team, max_reach_by_team):
		return   # every engaged team's own WEAKEST-reach unit already matches or dominates
				 # every opposing team's best reach -- nobody could possibly be outreached
				 # this tick. Gating on the team's MAX (a mixed-loadout army's own best
				 # unit) instead of its MIN would let that best unit's reach mask a
				 # different, shorter-reach unit on the same team that genuinely needs to
				 # press -- e.g. a spear+infantry army facing an enemy spear: the team's
				 # own max (spear, 48) ties the enemy's max (48), but the team's infantry
				 # (26) is still outreached by that enemy spear and must not be skipped.

	var epos := PackedVector2Array()
	var eteam := PackedInt32Array()
	var eradius := PackedFloat32Array()
	var ereach := PackedFloat32Array()
	var eowners: Array = []          # owning Unit per entry
	var eslots := PackedInt32Array() # local index into the owner's _sim_soldier_pos/_sim_steer
	var queriers := PackedInt32Array()   # indices into the arrays above that need a lookup
	for o in units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD:
			continue
		var n: int = u._sim_soldier_pos.size()
		if n == 0 or u._sim_steer.size() != n:
			continue
		var idxs: PackedInt32Array = u.engaged_soldier_indices(n)
		if idxs.is_empty():
			continue
		var r: float = u.soldier_body_radius()
		var reach: float = u.soldier_reach()
		var could_be_outreached: bool = reach < _max_opposing_reach(max_reach_by_team, u.team)
		for i in idxs:
			if could_be_outreached:
				queriers.push_back(epos.size())
			epos.push_back(u._sim_soldier_pos[i])
			eteam.push_back(u.team)
			eradius.push_back(r)
			ereach.push_back(reach)
			eowners.push_back(u)
			eslots.push_back(i)

	if queriers.is_empty():
		return   # pass 1's team-level check can under-prune relative to which SPECIFIC
				 # soldiers ended up engaged this tick (e.g. an engaged unit contributing zero
				 # indices) -- this catches that case before the rebuild below

	SoldierEngagedEnemyProximity.rebuild(epos, eteam, eradius, ereach, frame)
	for k in queriers:
		var enemy: Dictionary = SoldierEngagedEnemyProximity.nearest_enemy(epos[k], eteam[k], eradius[k], ereach[k])
		if enemy.is_empty():
			continue
		var owner: Unit = eowners[k]
		owner._sim_steer[eslots[k]] += standoff_bias(epos[k], enemy["position"], ereach[k], enemy["reach"])


## True when at least one team's WEAKEST engaged reach falls short of some OTHER team's max
## engaged reach -- i.e. some team could plausibly have an outreached soldier this tick. MIN,
## not MAX: a team's own best-reach unit ties/exceeding the enemy's best doesn't mean every
## unit on that team does -- see accumulate()'s own call site for the concrete mixed-army
## failure this guards against. Pure helper for accumulate()'s pass-1 early-out.
static func _any_team_could_be_outreached(min_reach_by_team: Dictionary, max_reach_by_team: Dictionary) -> bool:
	for team in min_reach_by_team:
		if min_reach_by_team[team] < _max_opposing_reach(max_reach_by_team, team):
			return true
	return false


## The greatest max-reach recorded for any team OTHER than `team`, or -1.0 if none (no
## opposing team currently has an engaged unit at all). Pure helper shared by both passes.
static func _max_opposing_reach(max_reach_by_team: Dictionary, team: int) -> float:
	var best: float = -1.0
	for t in max_reach_by_team:
		if t != team:
			best = maxf(best, max_reach_by_team[t])
	return best
