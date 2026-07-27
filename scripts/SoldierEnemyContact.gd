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
## this soldier-level physics was proven out -- but a live-battle test found it is NOT yet
## sufficient on its own: the regiment's kinematic advance still rides through a braced line,
## because SoldierBodies.couple() averages drift over every soldier body, not just the ones
## this pass actually resists. See docs/individual-collision-design.md phase 5 for the root
## cause and status. The regiment-circle enemy-collision branch stays in place alongside this
## pass until that's fixed and re-verified.
##
## Determinism: regiments are processed in uid order and each regiment's engaged soldiers in
## ascending index, so the gathered arrays are already global-soldier-id sorted; the
## SoldierSpatialHash query then visits candidates in a reproducible order, and every pair is
## resolved once (canonical lower-id-first) against the frozen input (Jacobi: every impulse
## this tick is computed from last tick's velocities/positions, applied in one pass at the
## end). No RNG, no instance-id/wall-clock -- replay-safe like the rest of the soldier layer.


## The per-body scale factor a summed contact delta must be trimmed by to match what
## capped_knockback_velocity would allow this body in isolation -- reusing that existing clamp
## rather than solving the exact per-body quadratic, a deliberate simplification. Returns 1.0
## for a zero delta (nothing to trim). Pure and directly unit-testable; see accumulate()'s own
## comment for why this per-body ratio then has to be applied per-PAIR (the smaller of the two
## endpoints' ratios), not directly to each body's own summed delta.
static func body_trim_scale(orig_vel: Vector2, delta: Vector2) -> float:
	if delta == Vector2.ZERO:
		return 1.0
	var isolated: Vector2 = SoldierCombat.capped_knockback_velocity(orig_vel, delta)
	var effective: Vector2 = isolated - orig_vel
	return clampf(effective.length() / delta.length(), 0.0, 1.0)


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
	# Every resolved pair is also kept (not just folded into delta_v) so the trim pass below
	# can rescale each pair's OWN two impulses together -- see that pass for why.
	var pair_a: PackedInt32Array = PackedInt32Array()
	var pair_b: PackedInt32Array = PackedInt32Array()
	var pair_impulse_a: PackedVector2Array = PackedVector2Array()
	var pair_impulse_b: PackedVector2Array = PackedVector2Array()
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
			pair_a.push_back(a)
			pair_b.push_back(b)
			pair_impulse_a.push_back(impulses[0])
			pair_impulse_b.push_back(impulses[1])

	# Trim each body's SUMMED delta to what capped_knockback_velocity would allow it in
	# isolation, expressed as a per-body scale factor -- reusing the existing clamp rather than
	# solving the exact per-body quadratic, a deliberate simplification. A soldier can be
	# simultaneously touching several enemy bodies (a Square-perimeter defender pressed by more
	# than one attacker from one side is exactly this), whose individual impulses each pass
	# enemy_contact_impulse's own per-pair KNOCKBACK_SPEED_MAX cap yet sum to more.
	#
	# Trimming delta_v directly per body (the original approach) breaks Newton's third law: pair
	# (a, b)'s two impulses are equal and opposite by construction, but a's trim ratio and b's
	# trim ratio are independent numbers -- scaling each body's SUMMED delta by its own ratio
	# scales a's share of THIS pair by one factor and b's share by a different one, so the pair's
	# net contribution to total system momentum is no longer zero. Summed over an entire contact
	# line, that leftover per-pair residual is a real net force with no opposing reaction anywhere
	# in the system -- and a net force applied off-center is a net TORQUE. Applied every tick two
	# prolonged, roughly-matched regiments grind against each other, that undamped torque
	# accumulates into a slow, continuous rotation of both regiments around their clash point
	# (root-caused via the torque-proxy instrumentation documented in .claude/memories/sparta.md).
	#
	# Fix: apply the SAME scale to both of a pair's impulses -- the smaller of the two bodies'
	# own scale factors, so neither body ever ends up over-trimmed relative to what it alone
	# would allow. This keeps every pair's contribution exactly action/reaction (near-zero net
	# system momentum and torque from this pass -- see the final safety-net clamp below for the
	# one case that can still reintroduce a small asymmetry), at the cost of sometimes trimming
	# a body's total delta a bit more conservatively than its own isolated cap strictly requires
	# -- an acceptable trade since physical correctness (far less phantom torque) matters more
	# here than extracting the absolute maximum knockback per body.
	var body_scale := PackedFloat32Array()
	body_scale.resize(n)
	for k in range(n):
		body_scale[k] = body_trim_scale(svel[k], delta_v[k])

	var scaled_delta_v := PackedVector2Array()
	scaled_delta_v.resize(n)
	for p in range(pair_a.size()):
		var ia: int = pair_a[p]
		var ib: int = pair_b[p]
		var s: float = minf(body_scale[ia], body_scale[ib])
		scaled_delta_v[ia] += pair_impulse_a[p] * s
		scaled_delta_v[ib] += pair_impulse_b[p] * s

	# Final safety-net clamp: pair-level trimming with mismatched per-body scale factors can
	# still leave a body's summed, rescaled delta over its own isolated cap -- e.g. when a
	# body's raw delta benefited from partial cancellation between two roughly-opposing pairs,
	# and one of those pairs then gets trimmed hard by a heavily-loaded partner, destroying that
	# cancellation. This clamp is itself a per-body-independent operation (the same shape the
	# pair-level trim above exists to avoid), so on that specific geometry it can reintroduce a
	# bounded asymmetry -- consistent with this fix's own measured residual (-0.169 net torque
	# over a 700-tick clash, not exactly zero) rather than contradicting the claim above: a
	# large, genuine reduction (~100,000x), not an exact conservation guarantee.
	for k in range(n):
		if scaled_delta_v[k] != Vector2.ZERO:
			var owner: Unit = sowners[k]
			var slot: int = sslots[k]
			owner._sim_body_vel[slot] = SoldierCombat.capped_knockback_velocity(
				owner._sim_body_vel[slot], scaled_delta_v[k])
