class_name SoldierEncirclement
## Per-soldier encirclement detection and break-to-individual-melee response. SHIELD_WALL and
## TESTUDO both depend on a soldier's shield staying locked with its neighbours to earn their
## stance bonus/penalty (Unit.breaks_under_encirclement): SHIELD_WALL's frontal melee/missile
## defense assumes the wall is intact and squarely facing the threat, TESTUDO's all-round
## missile cover and melee-output penalty assume the whole roof is still locked overhead. A
## soldier who is actually contacted by enemies spanning more than a single facing's hemisphere
## can't be defended by either assumption any more -- there is no direction that shield could
## face and cover every attacker at once -- so it individually breaks the stance: its own
## combat multipliers fall back to the unmodified baseline (SoldierMelee.resolve reads
## Unit._sim_soldier_broken per soldier to drop the stance's melee-output/defense multiplier
## for just that one body), and it is steered toward the widest open gap between its
## attackers instead of holding its formation slot. SQUARE/SCHILTRON are deliberately excluded
## (breaks_under_encirclement is false for them): their whole point is an all-around stance
## built to be attacked from every side, so being surrounded is the design, not a breakdown.
##
## "Surrounded" (is_surrounded): no single facing direction could keep every contacting enemy
## within this soldier's frontal hemisphere -- exactly the frontal arc Unit._is_frontal_attack
## already tests SHIELD_WALL's bonus against (dot(facing, dir) > 0). Equivalently: sort the
## contacts' bearings and find the largest angular gap between consecutive ones; if the
## contacts collectively span more than PI radians (2*PI minus that largest gap), no
## hemisphere can contain them all -- any two contacts genuinely on opposite sides of the
## soldier (bearings ~PI apart) already cross this threshold regardless of how many other
## contacts exist, which is exactly the textbook "attacked from front and rear at once" case
## this is meant to catch.
##
## The retreat direction isn't a separate synthetic escape heading bolted on afterward -- it's
## the midpoint of that same largest gap: literally the widest opening between attackers,
## read off the exact calculation that already decided the soldier is surrounded. Feeding it
## into _sim_steer (the same composable per-tick velocity bias SoldierMeleeStandoff/
## SoldierSteering already use) means the retreat is a real, bounded-accel velocity request
## that competes with genuine contact-collision resistance (SoldierEnemyContact runs after
## this pass in Battle._on_soldier_tick) -- if the gap is real, the body slips through it; if
## attackers close it again, the body makes little progress. That is the whole mechanism
## behind "fall back and rejoin as soon as an opening appears" -- there is no separate
## explicit "is there an opening" check anywhere; it falls out of the physics, matching this
## codebase's standing "no top-down gimmicks" design philosophy (see .claude/memories/
## sparta.md).
##
## Scoped to the ENGAGED tier only (Unit.engaged_soldier_indices), the same population
## SoldierMeleeStandoff/SoldierEnemyContact already gather each tick. For a SHIELD_WALL/
## TESTUDO formation this is a live-position forward-projection selection
## (UnitFormation.live_front_indices), so a soldier struck only from directly behind an
## otherwise-intact front rank (which the engaged tier never selects at all) isn't visible to
## this pass -- a known simplification shared with the rest of the per-soldier melee model
## (engaged_soldier_indices' own doc comment), not something this pass introduces on its own.
## A real flanking/envelopment attack (cavalry sweeping around one end of the line) IS caught:
## the flank files sit at the edges of the same forward-projection selection, so a soldier
## there touched from both ahead and to the side registers correctly.
##
## No latch/hysteresis: _sim_soldier_broken is recomputed fresh every tick from live contact
## geometry, so both "breaks" and "rejoins" track the current tick's contacts directly --
## matching the issue's own "as soon as" phrasing on both ends.
##
## Ranged (Unit.is_ranged) units never count as a CONTACT (see accumulate()'s gather loop):
## "surrounded" is a melee-structural concept, and an archer merely shooting from range isn't
## pressing against anyone physically -- only its actual reach differs from a melee unit's,
## not its threat model. A ranged unit's own eligibility to break is untouched; it's excluded
## only from being counted as a threat TO someone else.
##
## Determinism: gathered in unit-uid then ascending-soldier-index order (mirroring
## SoldierEnemyContact/SoldierMeleeStandoff), so SoldierEncirclementProximity's cell insertion
## order -- and this pass's own per-soldier contact list -- is reproducible; no RNG, no
## wall-clock.

# No single facing (a hemisphere, matching Unit._is_frontal_attack's own
# dot(facing, dir) > 0 test) can face every contact at once once they collectively span more
# than half the circle -- see the class doc for the derivation.
const ENCIRCLEMENT_ARC_MIN: float = PI

# Vector2's own components are single-precision (Godot's default, non-double-precision build),
# so two contacts that are geometrically EXACTLY opposite (e.g. Vector2.UP/Vector2.DOWN) can
# still compute a _covered_arc a hair under PI due to float32 rounding in .angle() -- a real
# tick's soldier positions are never pixel-perfect-exact-antipodal either, so a bare `>=` would
# be fragile right at the one geometry (dead-on front-and-rear) this whole mechanic exists to
# catch. This tolerance absorbs that rounding without weakening the threshold for anything
# else -- it is many orders of magnitude smaller than any angular gap that matters gameplay-wise.
const ENCIRCLEMENT_ARC_EPS: float = 1e-4

# Retreat bias magnitude (world units/sec) -- the same order of magnitude as
# SoldierMeleeStandoff.STANDOFF_STRENGTH, since both compose into the identical bounded-accel
# arrival physics that value was tuned against.
const RETREAT_STRENGTH: float = 40.0


## `contacts`' bearings (Vector2.angle(), in [-PI, PI)), sorted ascending. Degenerate
## (near-zero-length) entries are dropped -- a co-located pair has no defined bearing.
## Pure helper shared by _covered_arc and retreat_direction.
static func _sorted_angles(contacts: PackedVector2Array) -> PackedFloat32Array:
	var angles := PackedFloat32Array()
	for c in contacts:
		if c.length_squared() > 0.0001:
			angles.push_back(c.angle())
	angles.sort()
	return angles


## The total arc (radians, in [0, 2*PI]) `contacts`' bearings collectively span: 2*PI minus
## the single widest gap between consecutive (circularly sorted) bearings. Fewer than 2
## contacts span nothing (0.0) -- a single bearing (or none) can never define a gap. Pure;
## shared by is_surrounded and retreat_direction so both read off the same largest-gap
## calculation.
static func _covered_arc(contacts: PackedVector2Array) -> float:
	var angles: PackedFloat32Array = _sorted_angles(contacts)
	if angles.size() < 2:
		return 0.0
	var largest_gap: float = 0.0
	for i in range(angles.size()):
		var a: float = angles[i]
		var b: float = angles[(i + 1) % angles.size()]
		var gap: float = (b - a) if b > a else (b - a + TAU)
		largest_gap = maxf(largest_gap, gap)
	return TAU - largest_gap


## True when `contacts` (bearings TO each enemy, any length/order, relative to the soldier)
## collectively span at least ENCIRCLEMENT_ARC_MIN radians -- i.e. no single facing hemisphere
## could contain every one of them AND still satisfy Unit._is_frontal_attack's own STRICT
## dot(facing, dir) > 0.0 test for every contact (the exact textbook "attacked from front and
## rear at once" case sits right at this boundary: two contacts exactly PI apart leaves only
## a knife-edge facing with dot == 0.0 for both, which _is_frontal_attack's strict inequality
## already treats as not-frontal -- so the threshold here has to be inclusive to match it).
## Fewer than 2 contacts can never span more than a point, so this is always false for those.
## Pure.
static func is_surrounded(contacts: PackedVector2Array) -> bool:
	return _covered_arc(contacts) >= ENCIRCLEMENT_ARC_MIN - ENCIRCLEMENT_ARC_EPS


## The direction bisecting the WIDEST angular gap between `contacts`' bearings -- the most
## open escape heading away from every attacker at once. Returns Vector2.ZERO for fewer than 2
## contacts (no gap is defined). Pure.
static func retreat_direction(contacts: PackedVector2Array) -> Vector2:
	var angles: PackedFloat32Array = _sorted_angles(contacts)
	if angles.size() < 2:
		return Vector2.ZERO
	var best_gap: float = -1.0
	var best_mid: float = 0.0
	for i in range(angles.size()):
		var a: float = angles[i]
		var b: float = angles[(i + 1) % angles.size()]
		var gap: float = (b - a) if b > a else (b - a + TAU)
		if gap > best_gap:
			best_gap = gap
			best_mid = a + gap * 0.5
	return Vector2.from_angle(best_mid)


## Recompute encirclement for every engaged soldier of every SHIELD_WALL/TESTUDO unit this
## tick: refresh `_sim_soldier_broken` and, for any soldier still surrounded, add its retreat
## bias into `_sim_steer` (composes on top of SoldierMeleeStandoff's own bias the same way
## that pass composes on top of SoldierSteering's -- see Battle._on_soldier_tick's ordering
## comment). Must run after SoldierMeleeStandoff (so it can add on top of its bias) and before
## UnitRef.step_all_sim_soldiers reads `_sim_steer` as this tick's feed-forward.
static func accumulate(units: Array, frame: int) -> void:
	# Clear every breakable, living unit's broken flags FIRST, unconditionally -- before the
	# perf early-out below, which only guards the expensive gather+grid rebuild, not this. A
	# unit that just disengaged (ENGAGED_LINGER expired, or its opponents routed/died) must
	# not keep a stale broken flag forever: nothing else ever clears _sim_soldier_broken (see
	# that field's own doc comment), and the render tint (Unit._soldier_is_broken_for_render)
	# reads it every frame with no engagement gate of its own -- a soldier could otherwise
	# render the broken tint indefinitely after its unit stopped fighting entirely. This pass
	# is cheap (one array fill per breakable unit, not the per-soldier gather below).
	for o in units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD or not u.breaks_under_encirclement():
			continue
		var n: int = u._sim_soldier_pos.size()
		if n == u._sim_soldier_broken.size():
			u._sim_soldier_broken.fill(0)

	var any_eligible: bool = false
	for o in units:
		var u: Unit = o as Unit
		if u != null and u.state != Unit.State.DEAD and u.breaks_under_encirclement() and u.is_engaged():
			any_eligible = true
			break
	if not any_eligible:
		return   # nobody could possibly break this tick -- skip the expensive gather+rebuild

	var sorted_units: Array = units.duplicate()
	sorted_units.sort_custom(func(x: Variant, y: Variant) -> bool: return (x as Unit).uid < (y as Unit).uid)

	var epos := PackedVector2Array()
	var eteam := PackedInt32Array()
	var eradius := PackedFloat32Array()
	var ereach := PackedFloat32Array()
	for o in sorted_units:
		var u: Unit = o as Unit
		# A ranged unit's soldiers never count as an encirclement CONTACT: "surrounded" is a
		# melee-structural concept (no facing could keep the shield locked against every
		# attacker), and an archer merely standing at ranged distance isn't pressing against
		# anyone physically -- reusing soldier_reach() (== attack_range, whichever weapon
		# type) for the contact radius the way SoldierMeleeStandoff/SoldierEnemyContact
		# already do for their own melee-only passes would otherwise let a far-off archer's
		# large ranged reach register as "surrounding" a SHIELD_WALL/TESTUDO unit it's only
		# shooting at, not touching (confirmed empirically: testudo-under-fire.json, a
		# pure-archer scenario, marked soldiers broken with no melee anywhere in the clip).
		# A ranged unit's own eligibility to individually break is untouched by this -- it's
		# excluded only as a CANDIDATE, not from ever being the querying side (a ranged unit
		# CAN still be meleed and, if somehow also in a breakable stance, break the same way).
		if u == null or u.state == Unit.State.DEAD or u.is_ranged:
			continue
		var n: int = u._sim_soldier_pos.size()
		if n == 0:
			continue
		var idxs: PackedInt32Array = u.engaged_soldier_indices(n)
		if idxs.is_empty():
			continue
		var r: float = u.soldier_body_radius()
		var reach: float = u.soldier_reach()
		for i in idxs:
			epos.push_back(u._sim_soldier_pos[i])
			eteam.push_back(u.team)
			eradius.push_back(r)
			ereach.push_back(reach)
	SoldierEncirclementProximity.rebuild(epos, eteam, eradius, ereach, frame)

	for o in sorted_units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD or not u.breaks_under_encirclement():
			continue
		var n: int = u._sim_soldier_pos.size()
		if n == 0 or u._sim_soldier_broken.size() != n or u._sim_steer.size() != n:
			continue
		# Every soldier's flag was already cleared to 0 by the unconditional reset pass above
		# this tick -- only set it back for whichever engaged indices are genuinely surrounded
		# right now.
		var idxs: PackedInt32Array = u.engaged_soldier_indices(n)
		if idxs.is_empty():
			continue
		var r: float = u.soldier_body_radius()
		var reach: float = u.soldier_reach()
		for i in idxs:
			var contacts: PackedVector2Array = SoldierEncirclementProximity.enemies_within(
					u._sim_soldier_pos[i], u.team, r, reach)
			var rel := PackedVector2Array()
			for c in contacts:
				rel.push_back(c - u._sim_soldier_pos[i])
			if is_surrounded(rel):
				u._sim_soldier_broken[i] = 1
				u._sim_steer[i] += retreat_direction(rel) * RETREAT_STRENGTH
