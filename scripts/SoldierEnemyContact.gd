class_name SoldierEnemyContact
## Continuous enemy-vs-enemy soldier contact (the soldier-level counterpart to
## SoldierSteering's friendly-avoidance pass): applies SoldierCollision.enemy_contact_impulse
## to every overlapping pair of engaged soldiers from OPPOSING teams, writing the resulting
## velocity deltas straight into _sim_body_vel. Unlike combat knockback (a one-shot impulse
## on a landed/defended STRIKE, its own attack cadence), this runs every tick contact exists,
## so a charging body's momentum is resisted by physical contact the instant it touches a
## braced line -- not only on the next landed blow, and not via the regiment-circle's flat
## "hard block" rule (Unit._push_share == 0/1 for spear vs cavalry). Retiring that rule (and
## the regiment circle's enemy-collision branch generally) was meant to be a follow-up once
## this soldier-level physics was proven out -- but a live-battle test (issue #296) found it
## is NOT yet sufficient on its own: the regiment's kinematic advance still rides through a
## braced line, because SoldierBodies.couple() averages drift over every soldier body, not
## just the ones this pass actually resists. See issue #783 for the root cause and
## docs/individual-collision-design.md phase 5. Until #783 is fixed and re-verified, the
## regiment-circle enemy-collision branch stays in place alongside this pass.
##
## Determinism: regiments are processed in uid order and each regiment's engaged soldiers in
## ascending index, so the gathered arrays are already global-soldier-id sorted; the
## SoldierSpatialHash query then visits candidates in a reproducible order, and every pair is
## resolved once (canonical lower-id-first) against the frozen input (Jacobi: every impulse
## this tick is computed from last tick's velocities/positions, applied in one pass at the
## end). No RNG, no instance-id/wall-clock -- replay-safe like the rest of the soldier layer.


## Resolve every enemy-contact pair this tick, writing the resulting velocity deltas into
## each body's _sim_body_vel. `frame` keys the spatial hash; pass a value distinct from
## SoldierSteering.accumulate's own frame key (the two passes gather different position
## sets in the same tick, so they can't share one cached grid) -- Battle drives this via a
## fixed odd/even offset. Only the ORIGINAL engaged tier (Unit.engaged_soldier_indices, not
## SoldierSteering's friendly-contact-tier expansion) is gathered: enemy contact only ever
## matters at melee range, which the engaged tier already captures.
static func accumulate(units: Array, frame: int) -> void:
	var sorted_units: Array = units.duplicate()
	sorted_units.sort_custom(func(x: Variant, y: Variant) -> bool: return (x as Unit).uid < (y as Unit).uid)

	var spos := PackedVector2Array()
	var svel: Array = []             # parallel to spos; PackedVector2Array doesn't alias well as a shared ref
	var sgids := PackedInt32Array()
	var sowners: Array = []          # owning Unit per entry
	var sslots := PackedInt32Array() # local index into the owner's _sim_body_vel
	var sradii := PackedFloat32Array()
	var smass := PackedFloat32Array()
	var sbrace := PackedFloat32Array()
	var steams := PackedInt32Array()
	for o in sorted_units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD:
			continue
		var nb: int = u._sim_soldier_pos.size()
		if nb == 0 or u._sim_body_vel.size() != nb:
			continue
		var idxs: PackedInt32Array = u.engaged_soldier_indices(nb)
		if idxs.is_empty():
			continue
		var r: float = u.soldier_body_radius()
		var mass: float = u.combat_profile()["mass"]
		var brace: float = u.soldier_brace()
		for i in idxs:
			spos.push_back(u._sim_soldier_pos[i])
			svel.push_back(u._sim_body_vel[i])
			sgids.push_back(u.soldier_id(i))
			sowners.push_back(u)
			sslots.push_back(i)
			sradii.push_back(r)
			smass.push_back(mass)
			sbrace.push_back(brace)
			steams.push_back(u.team)
	var n: int = spos.size()
	if n < 2:
		return

	SoldierSpatialHash.rebuild(spos, frame)
	var delta_v := PackedVector2Array()
	delta_v.resize(n)
	for a in range(n):
		for b in SoldierSpatialHash.query(spos[a]):
			if sgids[b] <= sgids[a]:
				continue   # each pair once
			if steams[a] == steams[b]:
				continue   # friendlies don't contact-collide here -- SoldierSteering handles them
			var min_dist: float = sradii[a] + sradii[b]
			var offset: Vector2 = spos[a] - spos[b]
			var d: float = offset.length()
			if d >= min_dist:
				continue   # not touching -- nothing to resolve
			var normal: Vector2
			var overlap_frac: float
			if d > 0.01:
				normal = offset / d
				overlap_frac = (min_dist - d) / min_dist
			else:
				# Co-located pair: fan apart along a stable, id-keyed angle (mirrors
				# SoldierSteering._pair_push's own tie-break), full overlap.
				var lo: int = mini(sgids[a], sgids[b])
				var angle: float = float(posmod(lo, 100)) / 100.0 * TAU
				var sgn: float = 1.0 if sgids[a] > sgids[b] else -1.0
				normal = Vector2.RIGHT.rotated(angle) * sgn
				overlap_frac = 1.0
			var impulses: Array = SoldierCollision.enemy_contact_impulse(
				svel[a], svel[b], smass[a], sbrace[a], smass[b], sbrace[b], normal, overlap_frac)
			delta_v[a] += impulses[0]
			delta_v[b] += impulses[1]
	# Apply each body's SUMMED delta under a clamp, not a raw add: enemy_contact_impulse's own
	# KNOCKBACK_SPEED_MAX cap is scoped to one pair, but a soldier can be simultaneously touching
	# several enemy bodies (a Square-perimeter defender pressed by more than one attacker from
	# one side is exactly this) whose individual impulses each pass that per-pair cap yet sum to
	# more. capped_knockback_velocity clamps the RESULTING velocity, mirroring the pile-on clamp
	# SoldierMelee.resolve already applies to accumulated strike knockback on one body.
	for k in range(n):
		if delta_v[k] != Vector2.ZERO:
			var owner: Unit = sowners[k]
			var slot: int = sslots[k]
			owner._sim_body_vel[slot] = SoldierCombat.capped_knockback_velocity(
				owner._sim_body_vel[slot], delta_v[k])
