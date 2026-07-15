class_name SoldierBodies
## Persistent per-soldier body dynamics (phase 4), extracted from Unit.gd. Every body
## ARRIVES at its formation slot under real, bounded force — it accelerates toward the
## slot at the unit's own acceleration and decelerates to land there with ~zero velocity,
## no overshoot and no oscillation (classic "arrive" steering, not a spring). No body ever
## teleports: position only ever changes by velocity * delta. An engaged front-rank body
## knocked back by melee HOLDS the displacement, then decelerates and returns under bounded
## force — a real knockback-and-recover, not a spring rebound — and feeds its
## friendly-avoidance steering velocity forward so it drifts off a crowding friend; the
## unengaged bulk feeds the unit's march velocity forward so it tracks its moving slots
## with no lag, easing onto a reformed slot instead of snapping. Operates on a Unit's
## `_sim_soldier_pos` / `_sim_body_vel` / `_sim_steer` (the state stays on the unit, where
## the render, steering, and melee read it). Deterministic and order-free across soldiers,
## no RNG — replay-safe like the rest of the soldier layer.

# Floor on the arrival acceleration (world units/s^2). A body accelerates toward its slot
# at max(unit.accel, this) and decelerates to arrive at rest, so a body shoved off formation
# returns under a real force ramp rather than snapping. The floor keeps reform brisk even
# for a very-low-accel unit type: a ~15 u shove recovers over ~1-2 s at 30 u/s^2, not 5+.
const BODY_ACCEL_FLOOR: float = 30.0
# Below this distance (world units) a body counts as on its slot — the arrival target
# collapses to the feed-forward velocity so a settled body doesn't jitter around the slot.
# A twentieth of a pixel is far below anything the eye resolves, so a body inside this band
# is visually on its mark; it just stops steering so discrete-step rounding can't drive a
# sub-pixel oscillation around the exact point.
const ARRIVE_EPS: float = 0.05
# Guard for the `to_slot / dist` direction normalisation: below this distance the body is
# on the slot for all purposes and dividing would be numerically meaningless. Shared by the
# inside-band arrival aim and the post-step inbound clamp so they gate on the same threshold.
const MIN_DIST: float = 1e-6
# Below this body speed (px/s) the render treats a body as at rest and the unit's marks
# can skip their per-frame MultiMesh rewrite — far under what the eye resolves at 60 fps.
const REST_SPEED: float = 0.5
# How long an engaged body's assigned canonical target slot is held fixed before the
# engaged-body <-> slot PAIRING (not the underlying canonical-slot fix itself) is
# recomputed, in physics ticks (60/s). A real soldier in a formation doesn't instantly
# re-decide which gap to fill the moment a neighbor's live position jostles across the
# engaged-selection boundary; this bounds how often that re-decision happens so a body's
# steering target stays stable for a real reaction cadence instead of potentially
# relocating every tick. ~0.5s: long enough to damp per-tick jostle, short
# enough that a genuine casualty or reform still resolves within a fraction of a second
# (and a casualty forces an immediate recompute regardless -- see Unit._engaged_target_*).
const ENGAGED_TARGET_REASSIGN_TICKS: int = 30


## Seed a unit's bodies onto its current formation slots, at rest (zero velocity) and
## at full per-type health.
static func seed(unit: Unit) -> void:
	unit._sim_soldier_pos = unit.soldier_world_slots(unit.soldiers)
	unit._sim_body_vel = PackedVector2Array()
	unit._sim_body_vel.resize(unit._sim_soldier_pos.size())
	unit._sim_steer = PackedVector2Array()
	unit._sim_steer.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_hp = PackedFloat32Array()
	unit._sim_soldier_hp.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_hp.fill(unit.combat_profile()["max_health"])   # everyone starts at full health
	unit._sim_prone = PackedFloat32Array()
	unit._sim_prone.resize(unit._sim_soldier_pos.size())             # 0 = standing
	unit._sim_soldier_stamina = PackedFloat32Array()
	unit._sim_soldier_stamina.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_stamina.fill(unit.combat_profile()["max_stamina"])
	# Loadout type ids: every soldier carries its unit's interned weapon/shield
	# type (see LoadoutRegistry) — an id into the shared registry, not an object.
	unit._sim_soldier_weapon_id = PackedInt32Array()
	unit._sim_soldier_weapon_id.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_weapon_id.fill(unit.weapon_type_id)
	unit._sim_soldier_shield_id = PackedInt32Array()
	unit._sim_soldier_shield_id.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_shield_id.fill(unit.shield_type_id)
	# Hold-angle state (phase 2): every soldier starts at its shield type's rest
	# pose (unit.shield_rest_angle, the shared lookup with the tail resize below
	# and Unit's formation-change reset).
	unit._sim_soldier_shield_hold_angle = PackedFloat32Array()
	unit._sim_soldier_shield_hold_angle.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_shield_hold_angle.fill(unit.shield_rest_angle())
	# Per-soldier facing starts from the formation's own layout (SQUARE's perimeter
	# ring faces outward; every other formation is uniform at the unit heading, the prior
	# behaviour), with no maneuver active.
	unit._sim_soldier_facing = unit.soldier_world_facings(unit._sim_soldier_pos.size())
	unit._per_soldier_facing = false
	unit._render_dirty = true   # fresh bodies need an initial draw


## Advance a unit's persistent bodies one fixed step. Every body arrives at its slot under
## bounded force and integrates its velocity; the unengaged bulk additionally feeds the
## unit's march velocity forward, which cancels the lag a slot-only target would give a
## moving formation (engaged regiments are ~stationary in melee, so their feed-forward is
## zero). Resizes to the live soldier count first — a casualty trims the rear bodies; the first call
## (empty arrays) seeds every body on its slot at rest. Order-free across soldiers; driven
## by the fixed physics delta, so it reproduces on replay.
static func step(unit: Unit, delta: float) -> void:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var n: int = slots.size()
	var old_n: int = unit._sim_soldier_pos.size()
	if old_n != n:
		# resize trims/extends at the tail (rear bodies); seed any newly-added body on
		# its slot at rest, so it never accelerates in from the array default (0, 0).
		unit._sim_soldier_pos.resize(n)
		unit._sim_body_vel.resize(n)
		for j in range(old_n, n):
			unit._sim_soldier_pos[j] = slots[j]
			unit._sim_body_vel[j] = Vector2.ZERO
	if unit._sim_steer.size() != n:
		# Index-aligned with the bodies; a fresh tail entry carries no steering yet. The
		# steering pass overwrites the engaged entries each tick before this runs.
		unit._sim_steer.resize(n)
	if unit._sim_soldier_hp.size() != n:
		# Keep the health pool index-aligned; any newly-added body arrives at full health.
		var hp_old: int = unit._sim_soldier_hp.size()
		var maxhp: float = unit.combat_profile()["max_health"]
		unit._sim_soldier_hp.resize(n)
		for j in range(hp_old, n):
			unit._sim_soldier_hp[j] = maxhp
	if unit._sim_prone.size() != n:
		unit._sim_prone.resize(n)   # index-aligned; a fresh tail body stands (0)
	var maxs: float = unit.combat_profile()["max_stamina"]
	if unit._sim_soldier_stamina.size() != n:
		# Keep the stamina pool index-aligned; any newly-added body arrives at full stamina.
		var stam_old: int = unit._sim_soldier_stamina.size()
		unit._sim_soldier_stamina.resize(n)
		for j in range(stam_old, n):
			unit._sim_soldier_stamina[j] = maxs
	if unit._sim_soldier_weapon_id.size() != n:
		# Keep the loadout type ids index-aligned; a fresh tail body carries the
		# unit's own types (phase 1: the loadout is uniform per unit).
		var weapon_old: int = unit._sim_soldier_weapon_id.size()
		unit._sim_soldier_weapon_id.resize(n)
		for j in range(weapon_old, n):
			unit._sim_soldier_weapon_id[j] = unit.weapon_type_id
	if unit._sim_soldier_shield_id.size() != n:
		var shield_old: int = unit._sim_soldier_shield_id.size()
		unit._sim_soldier_shield_id.resize(n)
		for j in range(shield_old, n):
			unit._sim_soldier_shield_id[j] = unit.shield_type_id
	if unit._sim_soldier_shield_hold_angle.size() != n:
		# Keep the hold-angle array index-aligned; a fresh tail body starts at its
		# shield type's rest pose, the same lookup the initial seed uses.
		var hold_old: int = unit._sim_soldier_shield_hold_angle.size()
		var tail_rest: float = unit.shield_rest_angle()
		unit._sim_soldier_shield_hold_angle.resize(n)
		for j in range(hold_old, n):
			unit._sim_soldier_shield_hold_angle[j] = tail_rest
	if unit._sim_soldier_facing.size() != n:
		var face_old: int = unit._sim_soldier_facing.size()
		unit._sim_soldier_facing.resize(n)
		# During an owned maneuver, seed a fresh tail body at the unit heading (the
		# default sync below is skipped, so it wouldn't otherwise be set). When not
		# owned, the fill() below covers every body, so seeding here would be redundant.
		if unit._per_soldier_facing:
			for j in range(face_old, n):
				unit._sim_soldier_facing[j] = unit.facing
	# Default: bodies track the formation's own facing layout (SQUARE's perimeter
	# ring outward, everything else the uniform unit heading). A maneuver that owns the
	# facings (_per_soldier_facing) keeps its own values until it releases them.
	if not unit._per_soldier_facing:
		unit._sim_soldier_facing = unit.soldier_world_facings(n)
	# A felled body rises on its own: decay its prone timer toward 0 each tick. Stamina
	# regens during the same pass; rising from prone costs KAPPA_P on the tick it happens.
	# The body still arrives at its slot below (it's down, not removed).
	for p in range(n):
		var was_prone: bool = unit._sim_prone[p] > 0.0
		unit._sim_prone[p] = maxf(0.0, unit._sim_prone[p] - delta)
		var just_rose: bool = was_prone and unit._sim_prone[p] == 0.0
		unit._sim_soldier_stamina[p] = clampf(
			unit._sim_soldier_stamina[p] + SoldierCombat.RHO_STAMINA * delta
				- (SoldierCombat.KAPPA_P if just_rose else 0.0),
			0.0, maxs)
	var engaged_indices: PackedInt32Array = unit.engaged_soldier_indices(n)
	# Membership test for the per-soldier loop below, as a packed bool array instead of a
	# Dictionary -- every tick, every unit builds one of these (engaged or not), so a
	# Dictionary's per-entry hashing/boxing overhead here is pure per-tick waste versus a
	# flat byte lookup.
	var is_engaged := PackedByteArray()
	is_engaged.resize(n)
	for idx in engaged_indices:
		is_engaged[idx] = 1
	# Engaged bodies are chosen by CURRENT POSITION (engaged_soldier_indices' live_front /
	# live_perimeter selection), so after a casualty compacts the per-soldier arrays they can
	# land on any array index -- slots[i] for those same i's is then just whatever canonical
	# grid cell array position i happens to hold post-compaction, not "the front/perimeter of
	# the formation". Map each live-engaged body to a CANONICAL target slot instead, so an
	# engaged body's own arrival target agrees with what SoldierBodies.couple() measures it
	# against -- see Unit.canonical_target_slot_indices. The two arrays are paired by RANK, so
	# each rank has to mean the same thing on both sides: raw surviving array index tracks
	# casualty-reindexed spawn order, not current position, so pairing by it can hand a body
	# at one end of the live front rank a target slot at the opposite end. Sort both sides by
	# actual lateral position first (Unit.pairing_sort_indices) so the k-th live-selected body
	# arrives at the k-th canonical slot NEAREST ITS OWN POSITION, not just its k-th array rank.
	# Dictionary keyed by array index + a `.has()`/fallback branch per soldier.
	#
	# The PAIRING itself (which engaged body gets which canonical slot) is rate-limited
	# (ENGAGED_TARGET_REASSIGN_TICKS): recomputing it fresh every tick lets a body's target
	# relocate by tens of world units the instant engaged_soldier_indices()'s live-position
	# selection jostles by a soldier-width, which the body then chases smoothly but still
	# reads as a snap since the GOAL moved. Only the ASSIGNMENT (which body index maps to
	# which canonical slot INDEX) is cached and reused within the interval -- `target_slots`
	# itself is rebuilt fresh from `slots` every tick, so an unengaged body (and an engaged
	# body's actual target POSITION, via `slots[sorted_canonical[k]]`) always tracks this
	# tick's live formation slots. Caching resolved positions instead of indices would freeze
	# every unengaged body's target too, since `slots` shifts continuously as the unit
	# marches/turns/gets pushed by SoldierBodies.couple() -- the exact snap this is meant to
	# fix, just for the unengaged majority.
	var target_slots: PackedVector2Array = slots.duplicate()
	if not engaged_indices.is_empty():
		var frame: int = Engine.get_physics_frames()
		var due_for_reassign: bool = unit._engaged_target_soldier_count != n \
				or unit._engaged_target_pairing_engaged.is_empty() \
				or unit._engaged_target_reassign_frame < 0 \
				or frame - unit._engaged_target_reassign_frame >= ENGAGED_TARGET_REASSIGN_TICKS
		var sorted_engaged: PackedInt32Array
		var sorted_canonical: PackedInt32Array
		if due_for_reassign:
			var canonical: PackedInt32Array = unit.canonical_target_slot_indices(slots, engaged_indices.size())
			sorted_engaged = unit.pairing_sort_indices(engaged_indices, unit._sim_soldier_pos)
			sorted_canonical = unit.pairing_sort_indices(canonical, slots)
			unit._engaged_target_pairing_engaged = sorted_engaged
			unit._engaged_target_pairing_canonical = sorted_canonical
			unit._engaged_target_reassign_frame = frame
			unit._engaged_target_soldier_count = n
		else:
			sorted_engaged = unit._engaged_target_pairing_engaged
			sorted_canonical = unit._engaged_target_pairing_canonical
		for k in range(mini(sorted_engaged.size(), sorted_canonical.size())):
			var engaged_idx: int = sorted_engaged[k]
			var canonical_idx: int = sorted_canonical[k]
			if engaged_idx < target_slots.size() and canonical_idx < slots.size():
				target_slots[engaged_idx] = slots[canonical_idx]
	else:
		# A full disengage must invalidate the cached pairing, not just leave it stale --
		# otherwise a re-engagement within the reassignment interval (with no casualty to
		# change `n` in between) would reuse a pairing built for an entirely different set
		# of engaged bodies (e.g. left-flank soldiers from a prior clash), mismatching which
		# bodies get a canonical-slot target for up to ENGAGED_TARGET_REASSIGN_TICKS.
		unit._engaged_target_pairing_engaged = PackedInt32Array()
		unit._engaged_target_pairing_canonical = PackedInt32Array()
		unit._engaged_target_reassign_frame = -1
		unit._engaged_target_soldier_count = -1
	# No body ever teleports: every body steers toward a desired velocity under bounded
	# acceleration and integrates its own velocity (fixed delta), so position only ever
	# changes by velocity * delta.
	var body_accel: float = maxf(unit.accel, BODY_ACCEL_FLOOR)
	# Cap the arrival approach at the unit's jog pace (not walk, not the move_speed sprint):
	# reforming and recovering from a knockback is a brisk jog, never a flat-out run, and the
	# same ceiling applies to engaged and unengaged bodies alike. The idle/reform jog cap
	# below enforces the same ceiling on the integrated velocity for a stationary unit; using
	# jog here keeps the arrival target consistent with it. A body that needs to move faster
	# than jog does so only via the march feed-forward, which is added on top and uncapped.
	var max_arrive: float = unit.jog_speed
	# Hoisted out of the per-soldier loop below: mass is uniform across a unit's own
	# soldiers (SoldierCombat.profile_for keys it only on unit-level type/training), so
	# looking it up once per unit-step -- like body_accel and max_arrive above -- avoids
	# allocating a fresh combat_profile() Dictionary on every soldier, every tick.
	var mass: float = unit.combat_profile()["mass"]
	for i in range(n):
		# The desired velocity is a feed-forward plus an arrival term toward the slot. The
		# feed-forward is what the slot itself is doing: for the marching bulk that is the
		# unit's march velocity (the rate its formation slots translate), so a body keeps up
		# with zero lag and arrives on a reformed or rotated slot over a few frames instead of
		# snapping to it. For an engaged front-rank body it is the friendly-avoidance steering
		# velocity (zero when no friendly crowds it, leaving the pure hold-and-recover arrival
		# that lets a body keep a knockback push and return under bounded force).
		# (`_approach_velocity` is itself zero while a unit stands idle, so an idle bulk
		# arrives onto its slots, not drifts.)
		# The unengaged bulk feeds the unit's march velocity forward, PLUS any friendly-contact
		# steering (phase 5): a marching regiment overlapping a friendly steers its contact
		# bodies off formation while still keeping up with the march, so the body->regiment
		# coupling slides the two apart. _sim_steer is zero for any body not gathered by the
		# steering pass this tick (it clears all steer first), so this reduces to the plain
		# march for the uncrowded bulk.
		var feed_forward: Vector2 = unit._sim_steer[i] if is_engaged[i] == 1 \
				else unit._approach_velocity + unit._sim_steer[i]
		# During an in-place turn the slot targets rotate with unit.facing, which would drag
		# bodies to intermediate positions and back. Drop the arrival term so bodies aim only at
		# the feed-forward (~zero for a turn in place); they decelerate to rest where they stand
		# instead of chasing the swinging slots. This covers the order-driven maneuvers (the
		# drill turns and the wheel, read off current_order) AND the engage re-face (a fighting
		# unit turning its front onto a new enemy) -- see Unit.is_maneuver_turning.
		var turning: bool = unit.is_maneuver_turning()
		var own_slot: Vector2 = target_slots[i]
		var to_slot: Vector2 = Vector2.ZERO if turning \
				else own_slot - unit._sim_soldier_pos[i]
		# Arrival: approach the slot at a speed that decelerates to 0 by the time the body
		# reaches it (v = sqrt(2 a d)), capped at the unit's jog pace, then move the body's
		# velocity toward that desired velocity at the bounded acceleration. No spring, so no
		# overshoot and no oscillation -- a body only ever slows as it nears the slot.
		var desired_vel: Vector2 = feed_forward
		var dist: float = to_slot.length()
		if dist > ARRIVE_EPS:
			# v = sqrt(2 a d) decelerates to 0 exactly at the slot in continuous time. The extra
			# dist/delta cap keeps the DESIRED velocity from asking for more than the remaining
			# distance in one tick; at the fixed 1/60 delta and any body_accel <= 90 wu/s^2 the
			# sqrt term is already the tighter of the two, so this inner cap is a cheap safety net
			# that rarely binds -- the real overshoot guard is the post-step inbound clamp below,
			# which bounds the INTEGRATED velocity (the desired cap can't stop a body carrying
			# residual inbound speed from an earlier, faster tick).
			var arrive_speed: float = minf(max_arrive, sqrt(2.0 * body_accel * dist))
			if delta > 0.0:
				arrive_speed = minf(arrive_speed, dist / delta)
			desired_vel += (to_slot / dist) * arrive_speed
		elif dist > MIN_DIST and delta > 0.0:
			# Inside the on-slot band, aim to land exactly this tick (dist/delta is tiny here),
			# so a body coasting in with residual speed is brought to the slot instead of
			# drifting through it and having to turn around -- the last guard against a
			# sub-pixel oscillation around the exact point.
			desired_vel += (to_slot / dist) * (dist / delta)
		# Apply kinetic friction damping (Newton's laws collision phase 1) to the velocity
		# CARRIED OVER from last tick, before this tick's arrival/steering command: velocity
		# held from a knockback or collision decays over time on its own (stationary/slow bodies
		# experience higher friction -- "stickier" -- fast bodies coast longer), but the arrival
		# system's own commanded speed for THIS tick is not itself decaying momentum, so it must
		# not be damped after move_toward computes it -- that would permanently shave the
		# steady-state arrival speed below its jog/back-speed target every tick, since there is no
		# next tick for move_toward to correct a deficit move_toward itself just created.
		# See SoldierCollision.apply_kinetic_friction and SoldierCombat friction constants.
		var damped_vel: Vector2 = SoldierCollision.apply_kinetic_friction(
				unit._sim_body_vel[i], mass, 0.0, delta)
		var new_vel: Vector2 = damped_vel.move_toward(desired_vel, body_accel * delta)
		# The sqrt(2 a d) arrival profile decelerates to 0 at the slot in continuous time, but
		# its slope steepens near the slot faster than a bounded decel can follow, so a body
		# arriving with residual inbound speed (built up from the previous tick's move_toward)
		# would coast a hair past and start a tiny oscillation. Clamp the arrival component
		# (velocity relative to the feed-forward) so it advances at most the remaining distance
		# this tick, for any positive distance -- the body lands exactly on the slot instead of
		# coasting through it. No overshoot, no oscillation.
		if not turning and delta > 0.0:
			if dist > MIN_DIST:
				var dir: Vector2 = to_slot / dist
				var arrival_vel: Vector2 = new_vel - feed_forward
				var inbound: float = arrival_vel.dot(dir)
				var max_inbound: float = dist / delta
				if inbound > max_inbound:
					new_vel -= dir * (inbound - max_inbound)
			else:
				# dist has collapsed to (effectively) zero: the body already sits on the slot, so
				# there is no meaningful direction left to project an inbound component onto -- but
				# the branch above never runs once dist <= MIN_DIST, so any leftover arrival
				# velocity (beyond the feed-forward) would otherwise carry the body straight past
				# the slot this tick with nothing left to clamp it. Zero the arrival component
				# instead of leaving it unclamped, so a body that just landed doesn't fling itself
				# to the far side on the very next tick (a gap this friction damping's carried-over
				# velocity can now expose, since a well-timed arrival used to leave almost no
				# residual speed at this exact transition).
				new_vel = feed_forward
		unit._sim_body_vel[i] = new_vel
		# Cap individual soldier speed to this unit's own jog pace while the unit is
		# stationary: during the reform hold phase AND whenever a formation reshape
		# (frontage change, centre pivot) plays out on an idle unit. A marching unit is
		# exempt — its bodies need to keep up with moving slots — so the cap only
		# applies when state == IDLE.
		if unit._reform_holding() or unit.state == Unit.State.IDLE:
			unit._sim_body_vel[i] = _cap_body_speed(unit, i)
		unit._sim_soldier_pos[i] += unit._sim_body_vel[i] * delta
		# Tell the render a body actually moved this tick, so _process can skip the
		# MultiMesh rewrite while a block sits at rest (REST_SPEED is well below visible).
		if unit._sim_body_vel[i].length_squared() > REST_SPEED * REST_SPEED:
			unit._render_dirty = true


## Cap a stationary/reforming body's velocity to its unit's jog pace, but to the slower
## backward pace (jog_speed * back_speed_fraction) when the body is moving BACKWARD
## relative to its own facing. "Backward" is a negative velocity component along the
## soldier's facing; a body stepping forward or purely sideways keeps the full jog cap.
## The backward component along the facing axis is capped to the slower pace while the
## sideways component stays free, so a rear rank backing into a new slot is slower than a
## front rank stepping forward -- exactly the maneuver asymmetry the stat models. A final
## jog_speed limit on the recombined vector keeps total speed within the jog ceiling, so a
## body moving diagonally backward-and-sideways never exceeds jog overall (the backward
## axis just eats a bigger share of that budget). Pure function of the body's velocity and
## facing; no RNG, order-free -- replay-safe.
static func _cap_body_speed(unit: Unit, i: int) -> Vector2:
	var vel: Vector2 = unit._sim_body_vel[i]
	var facing: Vector2 = unit._sim_soldier_facing[i] if i < unit._sim_soldier_facing.size() \
			else unit.facing
	# facing is always a unit vector -- every assignment site in Unit.gd normalises it
	# (dir.normalized(), Vector2.from_angle, rotation ops, the axis constants) -- so the
	# facing * forward_component projection below is exact. Guard the degenerate zero case.
	if facing.length_squared() < 0.0001:
		return vel.limit_length(unit.jog_speed)
	# A body moving forward or sideways (non-negative facing component) uses the full jog
	# cap. Only a body whose motion leans backward -- against its facing -- is capped slower.
	var forward_component: float = vel.dot(facing)
	if forward_component >= 0.0:
		return vel.limit_length(unit.jog_speed)
	# Split the velocity into its along-facing (backward) part and its sideways part, cap the
	# backward part to the slower pace, then re-limit the sum to jog so total speed stays
	# within the jog ceiling even for a diagonal backward-and-sideways body.
	var back_cap: float = unit.jog_speed * unit.back_speed_fraction
	var along: Vector2 = facing * forward_component            # points backward (component < 0)
	var side: Vector2 = vel - along
	if along.length() > back_cap:
		along = along.normalized() * back_cap
	return (along + side).limit_length(unit.jog_speed)


## Slide the regiment center toward its soldiers' centroid, at a bounded velocity (phase 5).
## The formation slots are centred (mean(slots) ~ position), so the drift body_centroid -
## slot_centroid is how far the bodies have been pushed off formation as a whole; stepping
## the center a fraction of that each tick drives the slot centroid onto the body centroid
## (geometric decay, stable). When bodies are pushed off slot by friendly avoidance or
## knockback, the whole regiment follows -- so friendly regiments separate from the soldier
## level up. During a clean march the bodies sit on their moving slots (drift ~0) so this is
## silent and never double-counts the march. Capped at MAX_FOLLOW_SPEED*delta so the center
## can never teleport. Per-unit and RNG-free -- replay-safe.
##
## An anchored (asymmetric) explicatio/duplicatio breaks the "mean(slots) ~ position" premise
## ON PURPOSE: unit.frontage_anchor_offset shifts every slot by a fixed local-X amount so one
## flank's edge holds fixed as the block widens/narrows (UnitFormation.slots), which moves the
## slot centroid away from `position` by that same amount for as long as the offset is nonzero
## -- not a transient lag that resolves as bodies arrive, but a standing, intentional gap. Left
## alone, coupling reads that permanent gap as bodies pushed off formation and keeps dragging
## `position` to close it every tick right up until the moment the bodies (which are separately
## easing onto the anchored slots via SoldierBodies.step) finish arriving -- at which point
## `position` has been pulled to whatever it happened to be dragged to, not the anchor's own
## fixed flank (this is a marginal/neutral feedback loop between this step and the arrival step:
## any position at all is a fixed point once the bodies catch up to wherever the slots ended up,
## so the actual endpoint is a transient-dependent accident, not the intended fixed flank).
## Skip coupling entirely while an anchor offset is in effect -- mirroring the wheel skip right
## below -- so `position` holds still and the bodies alone (correctly) ease onto the anchored
## slots; coupling resumes the moment a fresh order clears the offset back to 0.0.
##
## While engaged in melee, the drift average is weighted toward the ENGAGED bodies only, not
## every soldier in the regiment. SoldierEnemyContact only resists the engaged front rank; the
## unengaged bulk cheaply snaps onto its own (still-advancing) formation slot every tick
## regardless of what's happening at the front. Averaging over all n bodies dilutes the
## resisted front rank's drift by that compliant majority, so the correction below could never
## grow large enough to counter a sustained kinematic advance (_press_into/_move_to) -- see
## docs/individual-collision-design.md for the empirical trace that found this. Falls back to
## the whole-regiment average when there's no engaged soldier (the pre-existing friendly-
## collision / non-combat path), which this change leaves unaffected.
##
## couple() is the LAST soldier-layer sub-step this tick -- every unit's step() has already
## integrated this tick's body positions by the time it runs, unlike engaged_soldier_indices()'s
## other callers (SoldierMelee.resolve, SoldierSteering.accumulate, SoldierEnemyContact.accumulate,
## step()'s own internal call), which all run against the frozen pre-step snapshot and share its
## per-tick cache. Passing use_cache=false keeps couple() reading whatever _sim_soldier_pos holds
## at ITS OWN call time -- on a no-casualty tick that cache would otherwise return a stale,
## pre-integration selection instead.
static func couple(unit: Unit, delta: float) -> void:
	var n: int = unit._sim_soldier_pos.size()
	if n == 0:
		return
	# During a wheel the maneuver authoritatively slides `position` along the hinge arc while the
	# bodies arrive onto the swinging slots a few frames behind. Their centroid therefore lags the
	# slot centroid, so coupling would read that lag as off-formation drift and drag the centre
	# BACKWARD against the arc — pulling the standing flank off its hinge. Skip it; the arrival
	# alone brings the bodies onto the arc, and coupling resumes once the wheel completes.
	if unit.is_wheeling() or unit.frontage_anchor_offset != 0.0:
		unit._body_follow_vel = Vector2.ZERO
		return
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	if slots.size() != n:
		return   # arrays mid-resize this tick; couple next tick when they realign
	# position_anchor_indices narrows the engaged-ranks selection down to the live
	# near-front ranks (Unit.ANCHOR_RANKS) once the unit has settled (see
	# Unit.position_anchor_indices / _position_anchor_unstable) -- Square/Schiltron and any
	# in-progress turn or reform keep the wider engaged_soldier_indices selection this
	# always used to be.
	var indices: PackedInt32Array = unit.position_anchor_indices(n, false)
	var body_centroid := Vector2.ZERO
	var slot_centroid := Vector2.ZERO
	var count: int = indices.size()
	if count > 0:
		for i in indices:
			body_centroid += unit._sim_soldier_pos[i]
		# canonical_target_slot_indices' non-Square branch is always the contiguous
		# 0..target_count-1 (see its own docstring: `slots` is a fresh rank-major grid, so
		# the front `count` slots are always exactly those indices) -- sum straight over that
		# range instead of materializing the index array just to walk it right back off
		# (every engaged unit pays this once per tick in couple(), on top of step()'s own call to
		# canonical_target_slot_indices()).
		if unit.in_square():
			var target_indices: PackedInt32Array = unit.canonical_target_slot_indices(slots, count)
			for j in target_indices:
				slot_centroid += slots[j]
			if target_indices.size() != count:
				count = maxi(1, target_indices.size())
		else:
			# `count` (engaged-soldier indices, a subset of this unit's own `n` bodies) can
			# never exceed `slots.size()` (== n, guaranteed by the early-return above), so
			# the sum always runs over exactly `count` slots -- no size-mismatch fallback
			# needed here, unlike the Square branch's live-perimeter selection above.
			for j in range(count):
				slot_centroid += slots[j]
	else:
		count = n
		for i in range(n):
			body_centroid += unit._sim_soldier_pos[i]
			slot_centroid += slots[i]
	var inv: float = 1.0 / float(count)
	var drift: Vector2 = (body_centroid - slot_centroid) * inv
	var follow_step: Vector2 = (drift * Unit.FOLLOW_RATE * delta).limit_length(Unit.MAX_FOLLOW_SPEED * delta)
	unit._body_follow_vel = follow_step / delta if delta > 0.0 else Vector2.ZERO
	unit.position += follow_step
