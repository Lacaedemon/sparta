class_name SoldierSteering
## Friendly-avoidance steering for the engaged soldier subset (the no-teleport
## replacement for the retired global separation pass). Instead of position-correcting
## overlapping bodies, it writes a per-soldier velocity bias into each unit's `_sim_steer`,
## which SoldierBodies feeds forward — so a body damps AWAY from a crowding FRIENDLY and
## drifts off it over a few frames, never snapping. Enemy overlap is deliberately ignored
## here: the fighting resolves it through knockback (SoldierMelee), so the standoff emerges
## from press-in vs knockback rather than a separation rule.
##
## Determinism: regiments are processed in uid order and each regiment's engaged soldiers
## in ascending index, so the gathered arrays are already global-soldier-id sorted; the
## SoldierSpatialHash query then visits candidates in a reproducible order, and every pair
## is accumulated once (canonical lower-id-first) against the frozen input. No RNG, no
## instance-id / wall-clock — replay-safe like the rest of the soldier layer.

# Closing velocity a fully-overlapping friendly pair steers apart at (world units/sec),
# split evenly between the two. Tuned so crowded ranks slide back to body contact in a
# fraction of a second, without the jitter the old hard position-snap produced.
const STEER_STRENGTH: float = 60.0


## Recompute every steering body's friendly-avoidance bias into its unit's `_sim_steer`.
## `frame` keys the spatial hash (tests pass a distinct frame). A regiment contributes its
## engaged front ranks (the original tier) and -- when its block overlaps a FRIENDLY
## regiment's block -- ALL its bodies (the friendly-contact tier, phase 5), so two
## friendlies pressing together steer apart even when neither is fighting; the
## body->regiment coupling then slides the two regiments off each other.
static func accumulate(units: Array, frame: int) -> void:
	var sorted_units: Array = units.duplicate()
	sorted_units.sort_custom(func(x: Variant, y: Variant) -> bool: return (x as Unit).uid < (y as Unit).uid)

	# Clear EVERY body's steering for this tick (recomputed below). Clearing all bodies --
	# not just the gathered ones -- means a body that drops out of the gathered set this tick
	# (no longer engaged / no longer overlapping a friendly) carries no stale bias into
	# SoldierBodies' feed-forward.
	for o in sorted_units:
		var u0: Unit = o as Unit
		if u0 == null or u0.state == Unit.State.DEAD:
			continue
		if u0._sim_steer.size() != u0._sim_soldier_pos.size():
			u0._sim_steer.resize(u0._sim_soldier_pos.size())
		u0._sim_steer.fill(Vector2.ZERO)

	# Precompute each living regiment's block extent once per tick. soldier_block_extent()
	# allocates a fresh PackedVector2Array (via UnitFormation.slots) and runs
	# SoldierFlock.compute_extent, so computing it here -- rather than per pair inside the
	# O(regiments^2) friendly broadphase below -- keeps large stacks (past ~30 friendly
	# regiments/side) off a recompute-and-allocate-per-pair cliff. Keyed by Unit so the
	# broadphase looks both endpoints up in O(1). half_extents/angles are the per-axis
	# counterpart _overlaps_friendly uses to tighten the circumradius pre-filter below.
	var extents := {}
	var half_extents := {}
	var angles := {}
	for o in sorted_units:
		var ue: Unit = o as Unit
		if ue == null or ue.state == Unit.State.DEAD:
			continue
		extents[ue] = ue.soldier_block_extent()
		half_extents[ue] = ue.soldier_block_half_extents()
		angles[ue] = ue.soldier_block_world_angle()

	# Gather steering bodies into parallel arrays, already in global-id order.
	var spos := PackedVector2Array()
	var sgids := PackedInt32Array()
	var sowners: Array = []          # owning Unit per entry
	var sslots := PackedInt32Array() # local index into the owner's _sim_steer
	var sradii := PackedFloat32Array()
	var steams := PackedInt32Array()
	for o in sorted_units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD:
			continue
		var nb: int = u._sim_soldier_pos.size()
		if nb == 0 or u._sim_steer.size() != nb:
			continue
		var r: float = u.soldier_body_radius()
		var idxs: PackedInt32Array
		if _overlaps_friendly(u, sorted_units, extents, half_extents, angles):
			idxs = PackedInt32Array()
			idxs.resize(nb)
			for i in range(nb):
				idxs[i] = i   # friendly-contact tier: all bodies
		else:
			idxs = u.engaged_soldier_indices(nb)   # original engaged tier
		for i in idxs:
			spos.push_back(u._sim_soldier_pos[i])
			sgids.push_back(u.soldier_id(i))
			sowners.push_back(u)
			sslots.push_back(i)
			sradii.push_back(r)
			steams.push_back(u.team)
	var n: int = spos.size()
	if n < 2:
		return

	# Accumulate each body's steering against the frozen input (Jacobi), each unordered
	# FRIENDLY pair once, in canonical (lower-id-first) order.
	SoldierSpatialHash.rebuild(spos, frame)
	var steer := PackedVector2Array()
	steer.resize(n)
	for a in range(n):
		for b in SoldierSpatialHash.query(spos[a]):
			if sgids[b] <= sgids[a]:
				continue   # each pair once
			if steams[a] != steams[b]:
				continue   # enemies don't steer — knockback handles them
			var owner_a: Unit = sowners[a]
			var owner_b: Unit = sowners[b]
			if owner_a == owner_b:
				continue   # intra-regiment spacing is the formation arrival's job, not steering's
			# Friendlies that pass cleanly through each other (a mover and an idle, or a
			# relief pair) don't shove — the exemption that used to live in _separate().
			if owner_a._separation_exempt(owner_b):
				continue
			var push: Vector2 = _pair_push(spos[a], spos[b], sgids[a], sgids[b], sradii[a] + sradii[b])
			if push == Vector2.ZERO:
				continue
			# Engaged-anchor asymmetry: a fighting regiment holds and the friendly newcomer
			# flows around it (mirrors _push_share's friendly branch). A symmetric pair
			# splits 0.5/0.5, exactly the original behaviour.
			var shares: Vector2 = _friendly_shares(owner_a, owner_b)
			steer[a] += push * shares.x
			steer[b] -= push * shares.y
	for k in range(n):
		# Bounded acceleration (SoldierBodies.step's move_toward) already stops any SINGLE
		# tick's push from snapping a body's velocity, but the summed push itself has no
		# ceiling -- under sustained extreme crowding (many neighbors converging on one
		# soldier, tick after tick) the accumulated steer vector, and so the target
		# velocity it feeds forward, could climb toward an unrealistic asymptote. Cap the
		# FINAL accumulated magnitude at one pair's own full-overlap push -- a maximally
		# compressed body doesn't escape any faster just because more neighbors are
		# pressing on it; friction/rigidity bound its yield rate regardless of headcount.
		sowners[k]._sim_steer[sslots[k]] = steer[k].limit_length(STEER_STRENGTH)


## Whether `u`'s block overlaps any living FRIENDLY regiment's block (a cheap deterministic
## regiment broadphase over the unit list — there are only dozens of regiments). Gates the
## friendly-contact tier so an uncrowded line costs the same as before. `extents` holds each
## living regiment's `soldier_block_extent()` precomputed once for the tick, so the scan reads
## both endpoints' reach from the cache instead of recomputing (and reallocating) per pair.
##
## The circumradius sum (`extents[u] + extents[v]`) bounds each block's reach in EVERY
## direction at once, i.e. out to its farthest corner -- correct as a broadphase REJECT test
## (if even that overestimate doesn't reach, the blocks truly can't overlap), but a loose
## ACCEPT test for a wide-but-shallow block (LOOSE order): two same-width regiments standing
## shoulder to shoulder can have circumradii that sum past their true gap while their actual
## near edges -- what could really crowd a soldier -- are nowhere close, promoting every body
## in both regiments to the expensive friendly-contact tier for nothing. So an apparent
## circle overlap is only a CANDIDATE; `_oriented_overlap` confirms it by projecting each
## block's half-extents onto the direction connecting the two centers instead of using the
## same reach in every direction, and only THAT tighter check decides the promotion.
static func _overlaps_friendly(u: Unit, sorted_units: Array, extents: Dictionary,
		half_extents: Dictionary, angles: Dictionary) -> bool:
	# `extents` is populated for every living unit in the same pass that calls this, so the
	# lookups here and at extents[v] below always hit. Assert the invariant rather than let a
	# future partial-dict caller fall through to a cryptic null-as-float mismatch downstream.
	assert(extents.has(u), "extents must be populated for all living units before _overlaps_friendly")
	var reach_u: float = extents[u]
	for o in sorted_units:
		var v: Unit = o as Unit
		if v == null or v == u or v.state == Unit.State.DEAD or v.team != u.team:
			continue
		var delta: Vector2 = v.position - u.position
		var d: float = delta.length()
		if d >= reach_u + extents[v]:
			continue   # cheap circumradius reject -- the blocks can't possibly overlap
		if _oriented_overlap(delta, d, half_extents[u], angles[u], half_extents[v], angles[v]):
			return true
	return false


## Tighter confirm step for a circumradius candidate: whether `u`'s and `v`'s blocks overlap
## along the SPECIFIC direction connecting their centers (`delta`, `d = delta.length()`),
## via the standard axis-aligned-rectangle support formula (`_support` below) instead of the
## circumradius' same-reach-everywhere bound. `d < 0.001` (co-located regiments) has no
## defined direction to project onto and can't be clear along any of them, so it overlaps
## trivially -- matching what the circumradius pre-filter already concluded to reach here.
static func _oriented_overlap(delta: Vector2, d: float, he_u: Vector2, ang_u: float,
		he_v: Vector2, ang_v: float) -> bool:
	if d < 0.001:
		return true
	var dir: Vector2 = delta / d
	return d < _support(he_u, ang_u, dir) + _support(he_v, ang_v, -dir)


## A block's reach along world direction `dir`, given its local-frame half-extents `he`
## (soldier_block_half_extents() -- already padded by mark radius + margin) and its current
## world rotation `ang` (soldier_block_world_angle()). Rotates `dir` into the block's own
## local frame, then applies the support-function formula for an axis-aligned rectangle:
## `hw*|dx| + hd*|dy|` for local direction (dx,dy) -- exact for a rectangle's own local axes,
## and always <= the circumradius (equal only exactly along the diagonal).
static func _support(he: Vector2, ang: float, dir: Vector2) -> float:
	var local_dir: Vector2 = dir.rotated(-ang)
	return he.x * absf(local_dir.x) + he.y * absf(local_dir.y)


## Per-soldier shares of a friendly pair's separation push (sum to 1). Even (0.5/0.5)
## normally; when exactly one owner is engaged (fighting) it holds (share 0) and the other
## yields fully (share 1), so a newcomer flows around a fighting friendly. Mirrors
## `_push_share`'s friendly branch.
static func _friendly_shares(owner_a: Unit, owner_b: Unit) -> Vector2:
	# (The caller has already skipped same-regiment pairs, so owner_a != owner_b here.)
	if owner_a.is_engaged() == owner_b.is_engaged():
		return Vector2(0.5, 0.5)
	return Vector2(0.0, 1.0) if owner_a.is_engaged() else Vector2(1.0, 0.0)


## The full separation push on soldier `a` away from `b` (caller applies the per-soldier
## shares), scaled by how deeply the pair overlaps, zero when clear. A co-located pair
## (d ~ 0) fans apart along a stable angle keyed off the lower id with a sign from the id
## order, so the tie-break carries no RNG / instance-id ordering.
static func _pair_push(pos_a: Vector2, pos_b: Vector2, gid_a: int, gid_b: int, min_dist: float) -> Vector2:
	var offset: Vector2 = pos_a - pos_b
	var d: float = offset.length()
	if d >= min_dist:
		return Vector2.ZERO
	var overlap: float = (min_dist - d) / min_dist   # 0 (just touching) .. 1 (co-located)
	var dir: Vector2
	if d > 0.01:
		dir = offset / d
	else:
		var lo: int = mini(gid_a, gid_b)
		var angle: float = float(posmod(lo, 100)) / 100.0 * TAU
		var sgn: float = 1.0 if gid_a > gid_b else -1.0
		dir = Vector2.RIGHT.rotated(angle) * sgn
	return dir * (STEER_STRENGTH * overlap)
