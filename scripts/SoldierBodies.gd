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
## with no lag, easing onto a reformed slot instead of snapping. A body's fully-integrated
## speed is still hard-capped near its unit's own top pace (Unit.superphysical_speed_frac
## * move_speed, or * flee_speed() while routing) no matter how far its slot has receded --
## see the final clamp at the end of
## the per-soldier loop in step(). That clamp floors at whatever speed the body already
## carried in, so it never suppresses a deliberately faster external push (a knockback) --
## only the march/arrival stacking it exists to bound. Operates on a Unit's
## `_sim_soldier_pos` / `_sim_body_vel` / `_sim_steer` (the state stays on the unit, where
## the render, steering, and melee read it).
## Deterministic and order-free across soldiers, no RNG -- replay-safe like the rest of the
## soldier layer.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")

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

# Multiplier on file pitch defining proximity threshold for straight-line arrival: a body
# within this radius of its own slot skips corridor routing entirely and just walks direct.
const CORRIDOR_PROXIMITY_MULT: float = 1.5
# The same proximity multiplier, but for a body whose unit is actively marching (own_slot
# is a moving point, not a fixed reform target) -- wider than CORRIDOR_PROXIMITY_MULT so a
# body catching up to a translating formation, hovering right at the plain radius from
# ordinary march wobble, doesn't repeatedly cross it and get flung into the full
# flank-and-rear detour (a formation's-width away) each time, right as it was about to
# land. See _corridor_to_slot's own doc comment for the failure this was measured against.
# A stationary reform (drill/frontage-fold, _approach_velocity zero) keeps the plain,
# narrower radius, so a genuine casualty-thinned or frontage-fold reform still corridors
# around its own formation's interior exactly as before. A march that turns keeps this
# wider band too, whatever the block's depth -- see advance_march_target_frac's doc comment,
# which also covers how a block setting off blends the two (arrival_target) and why one that
# stops switches straight back to the narrow band.
const MARCHING_CORRIDOR_PROXIMITY_MULT: float = 4.5
# Default for Unit.march_target_stop_grace_ticks: how many counted body steps a march may
# stand still before the ramp of its bodies' arrival target (advance_march_target_frac)
# starts again from nothing. Unit._march_stopped_ticks does the counting: a marching step
# resets it to 0, a standing step out of enemy contact and unengaged adds 1, and a standing
# step in contact or engaged leaves it as it is, so it is not a count of steps in a row. The
# ramp drops to 0 once that count passes this. Counted in steps, not seconds, because what
# it forgives is a step artifact -- a march velocity that reads zero for one or two
# integration steps and goes on -- so it means the same thing at any physics rate.
const MARCH_TARGET_STOP_GRACE_TICKS: int = 2
# Default for Unit.march_share_max_accel_mult: the most extra acceleration
# march_accel_budget grants a body, as a multiple of the body's own body_accel.
const MARCH_SHARE_MAX_ACCEL_MULT: float = 1.0
# Default for Unit.march_target_walk_frac: the march speed, as a fraction of walk_speed,
# whose time to reach from rest at the unit's accel sets how long a body's arrival target
# takes to move from the standing one to the marching one (advance_march_target_frac).
const MARCH_TARGET_WALK_FRAC: float = 1.0
# Defaults for Unit.march_share_from_pitches and Unit.march_share_full_pitches: how far off
# his own slot, in file pitches, a body takes none of march_accel_budget and all of it
# (march_share_frac).
const MARCH_SHARE_FROM_PITCHES: float = 0.5
const MARCH_SHARE_FULL_PITCHES: float = 1.0
# Default for Unit.flight_share_max_accel_mult: the most extra acceleration
# flight_accel_share grants a routing body, as a multiple of the body's own body_accel. Two
# speeds in a slot's feed-forward each change no faster than body_accel: the flight pace,
# which builds at unit.accel (Unit._process_rout) and body_accel is never below, and the
# speed of the slot's turning velocity, which changes by at most body_accel at the block's
# corner because the turn rate builds and sheds at Unit.bounded_turn_accel. Two body_accels
# cover those two. Not counted: the turning velocity swinging round with the grid; the bend
# of the flight's own heading as it follows a detour, about the pace times the rate the
# heading turns, which nothing bounds; the man's friendly-contact steering (_sim_steer), part
# of his feed-forward, which can change by any amount from one tick to the next; and a
# one-tick swing of the flight's direction (the step leaving a detour leg, or a side-step
# along a face starting or ending, Unit._flight_front_veer). So the cap binds while a flight
# bends round terrain at pace: on deep-router-close-start-hill (seed 0, Windows) the uncapped
# rate exceeded it on 279 of the 1637 man-ticks in which a man took any share and the flight
# was not slowing, mostly between ticks 290 and 340 as the flight bent round the hill
# (measured on 4a1c49aa, 2026-11-06, by a temporary per-man log of the uncapped rate).
const FLIGHT_SHARE_MAX_ACCEL_MULT: float = 2.0
# Defaults for Unit.flight_share_from_wu and Unit.flight_share_full_wu: how far off his own
# slot a routing body takes none of flight_accel_share and all of it (march_share_frac), a
# fixed distance rather than a multiple of the block's pitch: half and a whole of a default
# Cavalry block's 120 wu (6 m) rank pitch. While a flight builds up its men trail their
# slots: on deep-router-rounds-hill (Cavalry, file pitch 2 m, no man held at the hill), with
# no share (main 806be006, seed 0, Windows, 2026-11-05), the farthest man stands 43.7 to
# 103.6 wu off his slot from tick 120 to tick 350. A man within 3 m of his slot takes none,
# so a block whose men all keep that close flees as it did before. A ramp set in the
# block's own file or rank pitches also took up that ordinary lag, and in Infantry, whose
# rank pitch is about its file pitch (18 wu), it reached men only 9 wu off their slots.
const FLIGHT_SHARE_FROM_WU: float = 3.0 * WorldScaleRef.WU_PER_M
const FLIGHT_SHARE_FULL_WU: float = 6.0 * WorldScaleRef.WU_PER_M
# Lateral clearance beyond outer formed file for perimeter corridor routing.
const CORRIDOR_CLEARANCE_MULT: float = 1.0
# Stagger fraction between alternate soldier lanes in perimeter corridor.
const CORRIDOR_LANE_STAGGER_FRAC: float = 0.25
# Distance and lateral clearances for intra-file lane follower speed damping:
const LANE_FOLLOWER_DIST_MULT: float = 0.9
const LANE_FOLLOWER_LATERAL_MULT: float = 1.5

# In-transit same-unit standoff ratio against tightest pitch or two-body diameter:
const STANDOFF_MIN_SEP_FRAC: float = 0.9
# In-transit same-unit standoff maximum separation velocity along pair axis:
const STANDOFF_MAX_SPEED: float = 2.0 * WorldScaleRef.WU_PER_M
# Fraction of the standoff distance inside which a same-unit pair in a REFORM hold also has
# its closing speed cancelled (_separate_same_unit): each man takes half of it on top of the
# overlap push, the sum held to the per-man push cap, so the pair closes no faster than that
# cap allows. Without it the push grows with the overlap but never with the speed at which
# the two still walk into each other, so a man the arrival or a crowd at his back drives on
# at more than that push could walk on through a neighbour (a crowded re-slot brought pairs
# within 1.7 wu, against 9 wu for two bodies, with the pass running). Only a hold takes it:
# there the block stands and every man is walking to his own slot, while a march or a fight
# carries other pushes (the march itself, knockback) it would also blunt.
const STANDOFF_CONTACT_SEP_FRAC: float = 0.5
# Floor below which same-unit standoff separation is disabled (tuned in wu):
const STANDOFF_MIN_SEP_FLOOR: float = 0.01
# Default for Unit.standoff_off_slot_pitches: how far off his own slot, in file pitches,
# one unengaged body of a block must stand for _separate_same_unit to police the block
# outside its usual windows (fighting, a re-slot's settle window, or a REFORM hold). While
# every man stands within this of his slot the block counts as in good order and the scan
# is skipped.
const STANDOFF_OFF_SLOT_PITCHES: float = 1.0
# How far inside a rect a line must pass to count as crossing it, not running along its edge
# (router_terrain_avoid's way round). A solver epsilon, tuned in wu:
const INTERIOR_EPS: float = 0.01
# Deterministic spread of directions for exactly coincident bodies:
const STANDOFF_TIE_BREAK_DIRS: int = 99


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
	unit._sim_soldier_broken = PackedByteArray()
	unit._sim_soldier_broken.resize(unit._sim_soldier_pos.size())   # 0 = holding formation
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
	# Bodies seeded at rest have taken no march yet: measure the next step's march change
	# from rest, as from any other standstill, and start their arrival target from the
	# standing one.
	unit._body_march_ff_prev = Vector2.ZERO
	# Nor a flight: the next routing step reads no feed-forward change, so grants no share.
	unit._body_flight_ff_prev = PackedVector2Array()
	unit._march_target_frac = 0.0
	unit._march_stopped_ticks = 0
	unit._render_dirty = true   # fresh bodies need an initial draw


## Advance a unit's persistent bodies one fixed step. Every body arrives at its slot under
## bounded force and integrates its velocity; the unengaged bulk additionally feeds the
## unit's march velocity forward, which cancels the lag a slot-only target would give a
## moving formation (engaged regiments are ~stationary in melee, so their feed-forward is
## zero). Resizes to the live soldier count first -- a regiment-path casualty trims the rear
## bodies (SoldierMelee.reap compacts at the dead man's own index instead); the first call
## (empty arrays) seeds every body on its slot at rest. Order-free across soldiers; driven
## by the fixed physics delta, so it reproduces on replay.
static func step(unit: Unit, delta: float) -> void:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	# Hand this tick's slots to couple() (see Unit._step_slots_for_couple's own doc) so it
	# doesn't redo the identical computation moments later in the same tick.
	unit._step_slots_for_couple = slots
	unit._step_slots_for_couple_valid = true
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
	if unit._sim_soldier_broken.size() != n:
		unit._sim_soldier_broken.resize(n)   # index-aligned; a fresh tail body starts holding formation (0)
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
	# follows the regiment's pace during the same pass (Unit.stamina_flow_per_s: regen at
	# rest, neutral at a walk, a drain at a jog or sprint -- one reading per regiment per
	# tick, since every body shares its unit's pace); rising from prone costs KAPPA_P on
	# the tick it happens. The body still arrives at its slot below (it's down, not removed).
	var stamina_flow: float = unit.stamina_flow_per_s() * delta
	for p in range(n):
		var was_prone: bool = unit._sim_prone[p] > 0.0
		unit._sim_prone[p] = maxf(0.0, unit._sim_prone[p] - delta)
		var just_rose: bool = was_prone and unit._sim_prone[p] == 0.0
		unit._sim_soldier_stamina[p] = clampf(
			unit._sim_soldier_stamina[p] + stamina_flow
				- (SoldierCombat.KAPPA_P if just_rose else 0.0),
			0.0, maxs)
	# The BODY-DYNAMICS tier, not the melee-resolution one: identical geometry and gate, but
	# capped so it never covers the whole block. Everything below this line -- the dropped
	# march feed-forward, the canonical-slot re-pairing -- is written relative to an unengaged
	# bulk that still tracks the formation's own slots (see this file's class doc), so a tier
	# that swallowed every rank would leave those behaviours with no reference to work
	# against. See Unit.body_tier_soldier_indices / body_tier_ranks.
	var engaged_indices: PackedInt32Array = unit.body_tier_soldier_indices(n)
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
	var brake_accel: float = body_brake_accel_for(unit)
	# Cap the arrival approach at the unit's jog pace (not walk, not the move_speed sprint):
	# reforming and recovering from a knockback is a brisk jog, never a flat-out run, and the
	# same ceiling applies to engaged and unengaged bodies alike. The idle/reform jog cap
	# below enforces the same ceiling on the integrated velocity for a stationary unit; using
	# jog here keeps the arrival target consistent with it. A body that needs to move faster
	# than jog does so only via the march feed-forward, which is added on top of this cap --
	# the two combined are still bounded, by the superphysical clamp applied to the fully
	# integrated velocity below, not by this jog-pace arrival cap.
	var max_arrive: float = unit.jog_speed
	# Hoisted out of the per-soldier loop below: mass is uniform across a unit's own
	# soldiers (SoldierCombat.profile_for keys it only on unit-level type/training), so
	# looking it up once per unit-step -- like body_accel and max_arrive above -- avoids
	# allocating a fresh combat_profile() Dictionary on every soldier, every tick.
	var mass: float = unit.combat_profile()["mass"]
	var files: int = unit.formation_files(n)
	var body_radius: float = unit.soldier_body_radius()
	var two_bodies: float = body_radius * 2.0
	var turning: bool = unit.is_maneuver_turning()
	# The blend advances every step, turning or not, so it stays a measure of how long the
	# block has been marching; the per-body loop below skips arrival_target entirely during a
	# maneuver turn.
	var march_frac: float = advance_march_target_frac(unit, delta)
	if turning:
		march_frac = 0.0
	var straight_march: bool = not turning and not unit.is_turning()
	# Precompute true file-column front and rear neighbors in O(n) for lane follower speed damping
	# (exempting maneuver turns, stationary/reform-holding units, and square/schiltron formations):
	var file_front_neighbor: PackedInt32Array = PackedInt32Array()
	var file_rear_neighbor: PackedInt32Array = PackedInt32Array()
	if not turning and unit.state == Unit.State.MOVING and not unit._reform_holding() and not unit.in_square() and files > 0:
		file_front_neighbor.resize(n)
		file_front_neighbor.fill(-1)
		file_rear_neighbor.resize(n)
		file_rear_neighbor.fill(-1)
		if unit._sim_soldier_file.size() == n:
			var max_r: int = ceili(float(n) / float(files)) + 2
			var grid: PackedInt32Array = PackedInt32Array()
			grid.resize(files * max_r)
			grid.fill(-1)
			var explicit: bool = unit._sim_soldier_rank.size() == n
			var rank_counts: PackedInt32Array = PackedInt32Array()
			if not explicit:
				rank_counts.resize(files)
			var soldier_ranks: PackedInt32Array = PackedInt32Array()
			soldier_ranks.resize(n)
			for j in range(n):
				var f: int = clampi(unit._sim_soldier_file[j], 0, files - 1)
				var r: int = maxi(0, unit._sim_soldier_rank[j]) if explicit else rank_counts[f]
				if not explicit:
					rank_counts[f] += 1
				soldier_ranks[j] = r
				if r >= 0 and r < max_r:
					grid[f * max_r + r] = j
			for j in range(n):
				var f: int = clampi(unit._sim_soldier_file[j], 0, files - 1)
				var r: int = soldier_ranks[j]
				if r > 0 and r - 1 < max_r:
					file_front_neighbor[j] = grid[f * max_r + r - 1]
				if r + 1 < max_r:
					file_rear_neighbor[j] = grid[f * max_r + r + 1]
		else:
			for j in range(n):
				if j - files >= 0:
					file_front_neighbor[j] = j - files
				if j + files < n:
					file_rear_neighbor[j] = j + files
	# A router's anchor is driven by _process_rout, not _move_to, so its _approach_velocity
	# (zeroed by Unit._rout()) carries nothing of the flight: its bulk takes the flight
	# velocity as feed-forward instead, the same way a marching bulk takes the march. And its flee pace is above its
	# own move_speed by design (Unit.FLEE_SPEED_MULTIPLIER), so the superphysical ceiling is
	# measured from the flee pace -- measured from move_speed it would hold every body below
	# the pace its anchor runs at, and the coupling would drag the anchor back to them.
	var routing: bool = unit.state == Unit.State.ROUTING
	var halting: bool = unit.is_rally_halting()
	var march_vel: Vector2 = unit._flee_velocity if routing else unit._approach_velocity
	# The velocity change the march itself took since the last step, which each unengaged body
	# may take on top of its own body_accel (see march_accel_budget). Only an orderly march
	# grants it (Unit._body_march_orderly). A router's flight takes its own per-man share
	# instead (flight_accel_share, below). A pursuit, a charge or a hasty move takes none:
	# their men close at the ordinary rate.
	var march_budget: float = march_accel_budget(unit, march_vel, body_accel, delta) \
			if unit._body_march_orderly and not routing else 0.0
	var share_pitch: float = unit.file_pitch_wu()
	unit._body_march_ff_prev = march_vel
	# A router's men each read their own feed-forward from the last step (the flight velocity,
	# their slot's turning velocity and any friendly-contact steering,
	# Unit._body_flight_ff_prev), so a man well off his
	# slot can take on top of body_accel what his slot's feed-forward changed by
	# (flight_accel_share). A last step with a different headcount, or none, grants nothing.
	var flight_prev: PackedVector2Array = unit._body_flight_ff_prev
	var flight_share: bool = routing and flight_prev.size() == n
	var flight_now := PackedVector2Array()
	if routing:
		flight_now.resize(n)
	var flight_cap: float = body_accel * maxf(unit.flight_share_max_accel_mult, 0.0)
	# A router turning its flight, or any other block whose slot grid is turning after a small
	# heading correction, turns its grid about the anchor at this rate (rad/s;
	# Unit._turn_flight_toward, Unit._advance_grid_lag): each unengaged slot also moves at
	# turn_rate x its offset from the anchor, and that is fed forward with the march.
	var turn_rate: float = unit._flight_turn_rate if routing else unit._grid_lag_rate
	var top_pace: float = unit.flee_speed() if routing else unit.move_speed
	# In-transit same-unit standoff velocities for crowding same-unit bodies:
	var sep_vels: PackedVector2Array = _separate_same_unit(unit, n, target_slots, is_engaged, delta)
	var terrain_guard: Dictionary = _terrain_entry_guard(unit, n)
	# A router's men veer off impassable terrain they are running at (router_terrain_avoid);
	# the flight's feed-forward otherwise carries a man still closing on his slot after a turn
	# of the flight straight onto the rock. Only on a map with block terrain, and only routers.
	var routing_near_terrain: bool = routing and not terrain_guard.is_empty()
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
				else march_vel + unit._sim_steer[i]
		# During an in-place turn the slot targets rotate with unit.facing, which would drag
		# bodies to intermediate positions and back. Drop the arrival term so bodies aim only at
		# the feed-forward (~zero for a turn in place); they decelerate to rest where they stand
		# instead of chasing the swinging slots. This covers the order-driven maneuvers (the
		# drill turns and the wheel, read off current_order) AND the engage re-face (a fighting
		# unit turning its front onto a new enemy) -- see Unit.is_maneuver_turning.
		var own_slot: Vector2 = target_slots[i]
		if turn_rate != 0.0 and is_engaged[i] == 0:
			var arm: Vector2 = own_slot - unit.position
			feed_forward += Vector2(-arm.y, arm.x) * turn_rate
		var to_slot: Vector2 = Vector2.ZERO if turning \
				else arrival_target(unit, i, own_slot, n, march_frac, straight_march)
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
		if routing_near_terrain and terrain_guard["inside"][i] == 0:
			desired_vel = router_terrain_avoid(unit._sim_soldier_pos[i], unit._sim_body_vel[i],
					own_slot, desired_vel, terrain_guard["grown"], body_accel, delta)
		# The speed this body carried INTO this tick, before anything below touches it --
		# the floor the superphysical clamp uses further down, so a body already coasting
		# faster than that clamp (a knockback -- see the clamp's own comment) never gets
		# slammed back down to it; only NEW speed this tick's own steering adds gets bounded.
		var pre_tick_speed: float = unit._sim_body_vel[i].length()
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
		# An unengaged body's slot moves with the march, so the march's own acceleration this
		# tick is velocity change the body needs just to keep pace with its slot. A man walking
		# back to a slot he stands well off gets that much on top of body_accel, which stays
		# free for closing on the slot (march_share_frac); an engaged body takes no march
		# feed-forward and so gets no share of it.
		var accel_i: float = body_accel
		if is_engaged[i] == 0 and march_budget > 0.0:
			accel_i += march_budget * march_share_frac(
					own_slot.distance_to(unit._sim_soldier_pos[i]), share_pitch,
					unit.march_share_from_pitches, unit.march_share_full_pitches)
		# A router's flight builds its pace at the unit's accel, and its grid turn speeds a
		# corner slot sideways at up to the bodies' own acceleration on top, so a man's slot can
		# change its velocity faster than his body_accel lets him follow, and a man who has
		# fallen behind it gains nothing on it while the flight keeps changing (once its pace
		# and heading settle, his arrival term closes the gap as usual). He takes the change in
		# his own feed-forward on top, ramped in by how far he stands off his slot
		# (Unit.flight_share_from_wu, Unit.flight_share_full_wu).
		if routing:
			# Recorded in the unengaged form for every man, so a man who leaves the engaged
			# tier compares like with like rather than steering alone against the whole flight.
			# An engaged man's own_slot is the canonical slot he was re-paired onto, so his arm
			# is read off his own grid slot (slots[i]), the one he returns to when he leaves.
			var flight_ff: Vector2 = feed_forward
			if is_engaged[i] == 1:
				var flight_arm: Vector2 = slots[i] - unit.position
				flight_ff = march_vel + unit._sim_steer[i] \
						+ Vector2(-flight_arm.y, flight_arm.x) * turn_rate
			flight_now[i] = flight_ff
			if flight_share and is_engaged[i] == 0:
				accel_i += flight_accel_share(feed_forward, flight_prev[i], flight_cap, delta) \
						* march_share_frac(own_slot.distance_to(unit._sim_soldier_pos[i]), 1.0,
						unit.flight_share_from_wu, unit.flight_share_full_wu)
		var new_vel: Vector2 = damped_vel.move_toward(desired_vel, accel_i * delta) \
				if brake_accel <= accel_i \
				else brake_biased_step(damped_vel, desired_vel, accel_i, brake_accel, delta)
		# The sqrt(2 a d) arrival profile decelerates to 0 at the slot in continuous time, but
		# its slope steepens near the slot faster than a bounded decel can follow, so a body
		# arriving with residual inbound speed (built up from the previous tick's move_toward)
		# would coast a hair past and start a tiny oscillation. Clamp the arrival component
		# (velocity relative to the feed-forward) so it advances at most the remaining distance
		# this tick, for any positive distance -- the body lands exactly on the slot instead of
		# coasting through it. No overshoot, no oscillation.
		var step_vel: Vector2 = new_vel
		if not turning and delta > 0.0 and dist > MIN_DIST:
			var dir: Vector2 = to_slot / dist
			var arrival_vel: Vector2 = new_vel - feed_forward
			var inbound: float = arrival_vel.dot(dir)
			var max_inbound: float = dist / delta
			if inbound >= max_inbound:
				step_vel -= dir * (inbound - max_inbound)
				# The body arrives on slot this tick: use step_vel (clamped to dist/delta) to advance
				# the body onto the slot this tick, and zero the arrival component along dir for the
				# post-step stored velocity so leftover arrival speed does not coast past the slot on
				# subsequent ticks.
				new_vel = step_vel - dir * max_inbound
		# Lane follower forward speed cap: prevent sprinting through a friendly body directly ahead in the file lane:
		if file_front_neighbor.size() == n:
			var speed_sq: float = step_vel.length_squared()
			if speed_sq > 0.01:
				var my_speed: float = sqrt(speed_sq)
				var v_dir: Vector2 = step_vel / my_speed
				var my_pos: Vector2 = unit._sim_soldier_pos[i]
				var min_follow_dist: float = two_bodies * LANE_FOLLOWER_DIST_MULT
				var max_lat_dist: float = body_radius * LANE_FOLLOWER_LATERAL_MULT
				# Bounded O(1) check against resolved file-column neighbors:
				var prev_file_idx: int = file_front_neighbor[i]
				var next_file_idx: int = file_rear_neighbor[i]
				if prev_file_idx >= 0 and prev_file_idx < n:
					var other_pos: Vector2 = unit._sim_soldier_pos[prev_file_idx]
					var d_fwd: float = (other_pos - my_pos).dot(v_dir)
					if d_fwd > 0.0 and d_fwd < min_follow_dist:
						var d_lat: float = absf((other_pos - my_pos).cross(v_dir))
						if d_lat < max_lat_dist:
							var other_fwd_speed: float = maxf(0.0, unit._sim_body_vel[prev_file_idx].dot(v_dir))
							if my_speed > other_fwd_speed:
								var excess: float = my_speed - other_fwd_speed
								step_vel -= v_dir * excess
								new_vel -= v_dir * excess
								my_speed = other_fwd_speed
				if next_file_idx >= 0 and next_file_idx < n:
					var other_pos: Vector2 = unit._sim_soldier_pos[next_file_idx]
					var d_fwd: float = (other_pos - my_pos).dot(v_dir)
					if d_fwd > 0.0 and d_fwd < min_follow_dist:
						var d_lat: float = absf((other_pos - my_pos).cross(v_dir))
						if d_lat < max_lat_dist:
							var other_fwd_speed: float = maxf(0.0, unit._sim_body_vel[next_file_idx].dot(v_dir))
							if my_speed > other_fwd_speed:
								var excess: float = my_speed - other_fwd_speed
								step_vel -= v_dir * excess
								new_vel -= v_dir * excess
								my_speed = other_fwd_speed
		# In-transit same-unit standoff velocity applied along pair axis: applied to step_vel
		# (this tick's actual displacement) only, deliberately NOT folded into new_vel (the
		# velocity persisted into next tick's friction/move_toward baseline). Sep_vels is
		# recomputed fresh every tick from current positions, so a pair that is still too
		# close keeps getting pushed apart every tick regardless; folding it into new_vel as
		# well would instead carry the push forward as stored momentum for move_toward to
		# decay back out of at body_accel's bounded rate even after the pair has separated,
		# which overshoots each body past its own slot and turns the settle into a multi-tick
		# oscillation -- measured: doing so breaks
		# test_infantry_respreads_after_melee_exit.gd's 90-tick settle-streak requirement
		# outright, even though it changes nothing test_soldier_bodies.gd's own standoff
		# tests check for.
		if not sep_vels.is_empty():
			var sep: Vector2 = sep_vels[i]
			if sep != Vector2.ZERO:
				step_vel += sep

		# Cap individual soldier speed to this unit's own jog pace while the unit is
		# stationary: during the reform hold phase AND whenever a formation reshape
		# (frontage change, centre pivot) plays out on an idle unit. A marching unit is
		# exempt — its bodies need to keep up with moving slots — so the cap only
		# applies when state == IDLE.
		# A rallied unit pulling up from its flight is still moving -- its slots coast with
		# the anchor (Unit.is_rally_halting) -- so it is exempt for the same reason.
		if unit._reform_holding() or (unit.state == Unit.State.IDLE and not halting):
			var facing: Vector2 = unit._sim_soldier_facing[i] if i < unit._sim_soldier_facing.size() \
					else unit.facing
			step_vel = _cap_body_speed_vec(step_vel, facing, unit.jog_speed, unit.back_speed_fraction)
			new_vel = _cap_body_speed_vec(new_vel, facing, unit.jog_speed, unit.back_speed_fraction)
		unit._sim_body_vel[i] = new_vel
		# Final physical ceiling, applied after every adjustment above and to every body
		# alike (marching, engaged, idle/reforming): a man cannot exceed his own top pace (his
		# sprint, or his flee pace while routing -- `top_pace` above) by more than a hard
		# margin no matter how fast his slot is receding out from under him.
		# The arrival term above is already capped at jog pace, but the march feed-forward
		# stacks on top of it with no cap of its own, so only this clamp on the FULLY
		# INTEGRATED velocity bounds their sum -- see Unit.superphysical_speed_frac. Floored at
		# pre_tick_speed (above) rather than a flat top_pace * frac, so this clamp only ever
		# bounds speed THIS tick's own steering adds -- it never re-clamps a body already
		# coasting faster than the floor from an external impulse. A knockback -- especially
		# ORDER_KNOCKBACK_FOCUS's knockback_push_indefinite variant, which deliberately drives a
		# body up to SoldierCombat.KNOCKBACK_FOCUS_INDEFINITE_SPEED_CAP (200 wu/s), well past any
		# unit's own move_speed * frac -- sets _sim_body_vel directly via
		# SoldierCombat.capped_knockback_velocity() outside this loop; without the floor, the very
		# next tick's superphysical clamp would slam that legitimate push straight back down,
		# defeating the whole "coast much further than a normal push" point of the stance.
		var superphysical_cap: float = maxf(
			top_pace * unit.superphysical_speed_frac, pre_tick_speed)
		unit._sim_body_vel[i] = unit._sim_body_vel[i].limit_length(superphysical_cap)
		unit._sim_soldier_pos[i] += step_vel.limit_length(superphysical_cap) * delta
		# Tell the render a body actually moved this tick, so _process can skip the
		# MultiMesh rewrite while a block sits at rest (REST_SPEED is well below visible).
		if unit._sim_body_vel[i].length_squared() > REST_SPEED * REST_SPEED:
			unit._render_dirty = true

	# Empty unless routing, so a later rout's first step grants no flight share.
	unit._body_flight_ff_prev = flight_now
	# One arrival integration per body, each with exactly one `to_slot.length()`.
	SimOps.add(SimOps.BODY_STEP, n)
	SimOps.add(SimOps.SQRT_EVAL, n)
	_keep_out_of_terrain(unit, n, terrain_guard, delta)


## The extra acceleration (world units/s^2) a routing body may take this tick on top of its
## own body_accel: the rate its feed-forward `ff` (the flight velocity, its slot's turning
## velocity and any friendly-contact steering) changed since its feed-forward `ff_prev` on the
## last step, capped at `cap`
## (Unit.flight_share_max_accel_mult times body_accel). Unlike march_accel_budget it is read
## per man, since a turning grid moves each slot at its own velocity. Like it, a feed-forward
## whose speed fell grants none (compared exactly, with no tolerance): pulling up is not what
## leaves a man behind, and extra braking for a man well off his slot is what ran file-mates
## into each other on a march (march_accel_budget's sprint_reshape case). A swing at an
## unchanged or higher speed still counts. step() scales it by march_share_frac over the man's
## distance from his slot (Unit.flight_share_from_wu, Unit.flight_share_full_wu), so a man
## within 3 m of his slot, by default, takes none of it. 0 when `delta` is not positive.
static func flight_accel_share(ff: Vector2, ff_prev: Vector2, cap: float, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	if ff.length_squared() < ff_prev.length_squared():
		return 0.0
	return minf((ff - ff_prev).length() / delta, cap)


## The extra acceleration (world units/s^2) each unengaged body may take this tick: the rate
## the march velocity it is fed forward changed since the last step (Unit._body_march_ff_prev),
## capped at Unit.march_share_max_accel_mult times `body_accel`. A body's own velocity
## changes at body_accel (unit.accel, raised to BODY_ACCEL_FLOOR), while the march ramps its
## slots at unit.accel, so without this share a man behind his slot spends all or most of
## body_accel keeping pace with the accelerating slot and gains on it little or not at all.
## With it he keeps pace on the share and closes on the slot at his full body_accel. The
## rate is of the whole velocity vector, so a heading swing counts toward it, but only on a
## step whose march speed has not dropped: the test compares the squared speeds of this step
## and the last exactly, with no tolerance, so a swing at what is meant to be an unchanged
## speed grants the share on a step where rounding leaves the speed equal or higher and none
## on one where it reads lower by any amount. While the march runs at a steady velocity the
## share is zero, and step() grants it only to a man well off his slot (march_share_frac), so a block marching
## in good order moves exactly as before. That gate matters: without it the share also took
## up the small lag kinetic friction leaves a body behind an accelerating march, so every
## charge and pursuit closed faster than before. step() grants the share only on an orderly
## march (Unit._body_march_orderly): never on a router's flight (its men take
## flight_accel_share instead), a pursuit, a charge, a
## combat approach or a hasty move. A march that slows grants none either: pulling up is not
## what leaves a man behind, and a man braking harder than the neighbour behind him in his
## file was run into (sprint_reshape's 180-degree reversal: two men of one file 0.14 wu
## apart as the block pulled up, 2.65 without the share). The cap keeps a march that turns
## sharply in one tick (the first step after a far-tier return) from granting more than a
## set multiple of a body's ordinary acceleration (at the default of 1, no more than double
## it in all).
static func march_accel_budget(unit: Unit, march_vel: Vector2, body_accel: float,
		delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	if march_vel.length_squared() < unit._body_march_ff_prev.length_squared():
		return 0.0
	return minf((march_vel - unit._body_march_ff_prev).length() / delta,
			body_accel * maxf(unit.march_share_max_accel_mult, 0.0))


## How much of march_accel_budget a body `dist` from its own slot takes, 0 to 1: none
## within `from_pitches` file pitches of the slot, all of it from `full_pitches` out, and a
## straight ramp between. A man on or near his slot already keeps pace with it, so he moves
## exactly as he did before the share existed and a block marching in good order is
## untouched; only a man well off his slot, walking back to it, gets the extra.
static func march_share_frac(dist: float, pitch: float, from_pitches: float,
		full_pitches: float) -> float:
	var lo: float = pitch * from_pitches
	var hi: float = pitch * full_pitches
	if dist <= lo:
		return 0.0
	if hi <= lo or dist >= hi:
		return 1.0
	return (dist - lo) / (hi - lo)


## The rate this unit's bodies may shed speed at: their ordinary max(unit.accel,
## BODY_ACCEL_FLOOR), raised to the anchor's own braking rate while it pulls up from a rally
## (Unit.is_rally_halting, Unit.rally_halt_brake_rate): bodies held to the gentler rate would
## run on past their halting slots and walk back. Only braking is raised; a body speeding up
## (a man re-paired onto a slot ahead of him) still does so at the ordinary rate.
static func body_brake_accel_for(unit: Unit) -> float:
	var base: float = maxf(unit.accel, BODY_ACCEL_FLOOR)
	return maxf(base, unit.rally_halt_brake_rate()) if unit.is_rally_halting() else base


## One tick of a body's velocity toward `desired`, with the part of the change that opposes
## the body's current motion (braking) bounded by `brake_accel` and the rest (speeding up,
## or turning) by the ordinary `accel`.
static func brake_biased_step(vel: Vector2, desired: Vector2, accel: float, brake_accel: float,
		delta: float) -> Vector2:
	var change: Vector2 = desired - vel
	if vel.length_squared() < 0.0001:
		return vel.move_toward(desired, accel * delta)
	var brake_dir: Vector2 = -vel.normalized()
	var along: float = change.dot(brake_dir)
	if along <= 0.0:
		return vel.move_toward(desired, accel * delta)
	var brake: Vector2 = brake_dir * along
	var rest: Vector2 = change - brake
	return vel + brake.limit_length(brake_accel * delta) + rest.limit_length(accel * delta)


## Which bodies already stand inside impassable terrain itself (the rects as drawn, not
## grown) before this tick's integration: {"grown": the rects grown by the body radius,
## "inside": one flag per body}. Empty on a map with no block terrain, which turns the
## backstop off.
static func _terrain_entry_guard(unit: Unit, n: int) -> Dictionary:
	var field: PathField = PathField.active
	if field == null or not field.has_block_terrain():
		return {}
	var drawn: Array[Rect2] = field.block_rects()
	var inside := PackedByteArray()
	inside.resize(n)
	for i in range(n):
		inside[i] = 1 if PathField.inside_any_rect(unit._sim_soldier_pos[i], drawn) else 0
	SimOps.add(SimOps.TERRAIN_PROJECT, n * drawn.size())
	return {"grown": field.grown_block_rects(unit.soldier_body_radius()), "inside": inside,
			"bounds": field.field_bounds()}


## Hard backstop against impassable terrain, applied after the integration above so it has
## the last word on every body this tick: a body that ends the tick within its own body
## radius of `block` terrain is placed back on the edge of that margin, and the part of its
## velocity still heading in is dropped so it does not press straight back. Order validation
## keeps a destination's footprint clear, but contact forces, casualty reflow and a wheel's
## sweep move bodies without an order, and this catches all of them. A body that began the
## tick inside the terrain itself (a block spawned overlapping a hill) is left alone: ejecting
## a whole overlapping block at once would stack every body that differs only along the
## ejection axis onto one point, and holding it in place would pin the block to the rock.
## Body positions are parent-local while the terrain rects are in the Battle's frame; the
## two coincide while the Battle sits at the origin, as every other terrain query assumes.
## A block held with slots inside the margin is pressed back onto the edge every tick by a
## small creep; only a push longer than one tick's travel at REST_SPEED (the speed below
## which the integration above treats a body as at rest) raises the render flag, so that
## held block lets the render idle.
## `guard` is _terrain_entry_guard's result; empty (no block terrain) makes this a no-op.
static func _keep_out_of_terrain(unit: Unit, n: int, guard: Dictionary, delta: float) -> void:
	if guard.is_empty():
		return
	var grown: Array[Rect2] = guard["grown"]
	var inside: PackedByteArray = guard["inside"]
	var bounds: Rect2 = guard["bounds"]
	var visible_push: float = REST_SPEED * delta
	var moved_visibly := false
	var pushed: int = 0
	var checked: int = 0
	for i in range(n):
		if inside[i] != 0:
			continue
		checked += 1
		var p: Vector2 = unit._sim_soldier_pos[i]
		var q: Vector2 = PathField.push_out_of_rects(p, grown, 4, bounds)
		if q == p:
			continue
		unit._sim_soldier_pos[i] = q
		var push: float = p.distance_to(q)
		var outward: Vector2 = (q - p) / push
		if push > visible_push:
			moved_visibly = true
		var v: Vector2 = unit._sim_body_vel[i]
		var into: float = v.dot(outward)
		if into < 0.0:
			unit._sim_body_vel[i] = v - outward * into
		pushed += 1
	if moved_visibly:
		unit._render_dirty = true
	# One rect test per checked body per rect (first sweep); one normalization per body moved.
	SimOps.add(SimOps.TERRAIN_PROJECT, checked * grown.size())
	SimOps.add(SimOps.SQRT_EVAL, pushed)


## A routing man's desired velocity near impassable terrain. He looks ahead two ways: along
## the run he is carrying (his velocity `vel`), as far as he covers while shedding that speed
## at `accel`, plus one tick; and along where he wants to go (`desired`), as far as one tick
## takes him. If either look meets one of `grown` (the rects grown by the body radius), the
## part of `desired` heading into the face it meets is turned along that face: toward the
## side `slot` lies on when the slot is on his own side of the face, and otherwise toward the
## end that makes the shorter way round to `slot` -- counting, for an end whose straight line
## on to `slot` would cross the rect, the way on round its far corner. He veers off the rock
## while he can still turn, instead of running onto it and standing there: the hard backstop
## (_keep_out_of_terrain) stops a body dead in the direction of the rock, and a man stopped
## dead takes as long to pick up the flight again as it took him to reach it. The second look
## keeps a man already standing at the face from pressing into it. `desired` unchanged when
## both looks clear every rect, or when he already wants to run away from the face met.
## Deterministic and replay-safe; counts its own rect clips and square roots in SimOps.
static func router_terrain_avoid(pos: Vector2, vel: Vector2, slot: Vector2, desired: Vector2,
		grown: Array[Rect2], accel: float, delta: float) -> Vector2:
	var speed: float = vel.length()
	var want: float = desired.length()
	var sqrts: int = 2
	var clips: int = 0
	var best: float = INF
	var hit := Rect2()
	var entry := Vector2.ZERO
	if speed > 0.0 and accel > 0.0:
		var reach: float = speed * speed / (2.0 * accel) + speed * delta
		var ahead: Vector2 = pos + vel * (reach / speed)
		for g in grown:
			clips += 1
			var t: float = PathField.segment_rect_entry(pos, ahead, g)
			if t * reach < best:
				best = t * reach
				hit = g
				entry = pos.lerp(ahead, t)
	if want > 0.0 and delta > 0.0:
		var step_end: Vector2 = pos + desired * delta
		for g in grown:
			clips += 1
			var t: float = PathField.segment_rect_entry(pos, step_end, g)
			if t * want * delta < best:
				best = t * want * delta
				hit = g
				entry = pos.lerp(step_end, t)
	SimOps.add(SimOps.TERRAIN_PROJECT, clips)
	if not is_finite(best):
		SimOps.add(SimOps.SQRT_EVAL, sqrts)
		return desired
	# The face met: the one the entry point lies on (the nearest, for a point on a corner),
	# its outward normal, and its two ends.
	var gap_left: float = absf(entry.x - hit.position.x)
	var gap_right: float = absf(hit.end.x - entry.x)
	var gap_up: float = absf(entry.y - hit.position.y)
	var gap_down: float = absf(hit.end.y - entry.y)
	var outward := Vector2.LEFT
	var end_a: Vector2 = hit.position
	var end_b := Vector2(hit.position.x, hit.end.y)
	var nearest: float = gap_left
	if gap_right < nearest:
		nearest = gap_right
		outward = Vector2.RIGHT
		end_a = Vector2(hit.end.x, hit.position.y)
		end_b = hit.end
	if gap_up < nearest:
		nearest = gap_up
		outward = Vector2.UP
		end_a = hit.position
		end_b = Vector2(hit.end.x, hit.position.y)
	if gap_down < nearest:
		outward = Vector2.DOWN
		end_a = Vector2(hit.position.x, hit.end.y)
		end_b = hit.end
	var inward_part: float = -desired.dot(outward)
	if inward_part <= 0.0:
		SimOps.add(SimOps.SQRT_EVAL, sqrts)
		return desired
	var toward_a: bool
	var side: float = (slot - pos).dot(end_a - end_b)
	if slot.dot(outward) >= end_a.dot(outward) and side != 0.0:
		# His slot is on his own side of the face: he only has to stop running into it, so
		# he turns toward the side his slot lies on.
		toward_a = side > 0.0
	else:
		# His slot lies beyond the face: the shorter way round, by either end. Each end's far
		# corner is the same corner of the rect on its opposite face.
		var depth: float = absf(hit.size.dot(outward))
		var via_a: float = pos.distance_to(end_a) \
				+ _way_round(end_a, end_a - outward * depth, slot, hit)
		var via_b: float = pos.distance_to(end_b) \
				+ _way_round(end_b, end_b - outward * depth, slot, hit)
		sqrts += 8
		SimOps.add(SimOps.TERRAIN_PROJECT, 2)
		toward_a = via_a <= via_b
	var along: Vector2 = (end_a - end_b) if toward_a else (end_b - end_a)
	var along_len: float = along.length()
	sqrts += 1
	SimOps.add(SimOps.SQRT_EVAL, sqrts)
	if along_len <= 0.0:
		return desired
	return desired + outward * inward_part + along * (inward_part / along_len)


## How far it is from `corner` (one end of a face of `rect`) on to `slot`: straight there,
## unless that line would cross the rect's interior, in which case on round `far` (the same
## end's corner on the rect's opposite face) first. Always three square roots and one rect
## clip, so the caller can count them.
static func _way_round(corner: Vector2, far: Vector2, slot: Vector2, rect: Rect2) -> float:
	var direct: float = corner.distance_to(slot)
	var round_far: float = corner.distance_to(far) + far.distance_to(slot)
	if PathField.segment_intersects_rect(corner, slot, rect.grow(-INTERIOR_EPS)):
		return round_far
	return direct


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
static func _cap_body_speed_vec(vel: Vector2, facing: Vector2, jog_speed: float, back_speed_fraction: float) -> Vector2:
	# facing is always a unit vector -- every assignment site in Unit.gd normalises it
	# (dir.normalized(), Vector2.from_angle, rotation ops, the axis constants) -- so the
	# facing * forward_component projection below is exact. Guard the degenerate zero case.
	if facing.length_squared() < 0.0001:
		return vel.limit_length(jog_speed)
	# A body moving forward or sideways (non-negative facing component) uses the full jog
	# cap. Only a body whose motion leans backward -- against its facing -- is capped slower.
	var forward_component: float = vel.dot(facing)
	if forward_component >= 0.0:
		return vel.limit_length(jog_speed)
	# Split the velocity into its along-facing (backward) part and its sideways part, cap the
	# backward part to the slower pace, then re-limit the sum to jog so total speed stays
	# within the jog ceiling even for a diagonal backward-and-sideways body.
	var back_cap: float = jog_speed * back_speed_fraction
	var along: Vector2 = facing * forward_component            # points backward (component < 0)
	var side: Vector2 = vel - along
	if along.length_squared() > back_cap * back_cap:
		along = along.normalized() * back_cap
	return (along + side).limit_length(jog_speed)


## Applies in-transit same-unit standoff separation for crowding bodies within a regiment.
## Repels living, non-broken, unengaged pairs closer than min_sep with symmetric velocity
## along the pair axis. A FIGHTING regiment always runs this pass: the per-body is_engaged
## skip below (scoped to the front body_tier_soldier_indices() ranks) already excludes the
## bodies actually in contact, so the unengaged rear bulk of a fighting regiment still gets
## policed for crowding -- e.g. post-impact stacking behind a routing enemy the front rank
## cannot reach. Every other state runs it through a REFORM hold, inside
## unit._standoff_settle_until_tick's window, armed by the re-slot events (set_formation,
## set_frontage, reform_ranks) whose file-crossing this pass exists to police, and while any
## unengaged man stands more than Unit.standoff_off_slot_pitches file pitches off his slot
## (_any_body_off_slot), when men walking back to their slots can walk through each other --
## see the gate right below the deliberate-pass-through check for why a march in good order
## never needs the full scan.
static func _separate_same_unit(unit: Unit, n: int, target_slots: PackedVector2Array, is_engaged: PackedByteArray, delta: float) -> PackedVector2Array:
	if unit.state == Unit.State.ROUTING or n < 2 or delta <= 0.0:
		return PackedVector2Array()

	# Same-unit standoff is gated off whenever soldiers deliberately pass through each other
	# along file lanes: an in-place maneuver turn/wheel (rigid rotation, no crossing to
	# resolve), or a still-in-flight mirror reform (an about-face fold whose bodies have not
	# yet reached their re-squared slots -- the reflection genuinely crosses files through the
	# block).
	#
	# A REFORM leaf hold is not a pass-through, in or out of good order, and the pass runs for
	# the whole of it. Its men walk each straight at his own slot, from wherever a fight, a
	# march or the re-slot left them, and nothing about the hold routes them along file lanes.
	# With the pass gated off they walked through each other: an archer block re-forming after
	# a fight that had scrambled it (the showcase clip's uid 7) brought two men within 0.87 wu,
	# against 9 wu for two bodies. Nor does a block whose men all stand within a file pitch of
	# their slots hold apart on its own: one man standing on his neighbour's slot, the
	# neighbour half a pitch beside him, is exactly a pitch off, and when the two trade places
	# they cross head on (a checkerboard reform hold brought such a pair within 0.51 wu). What
	# a hold does need, bodies that file past one another on purpose, is the mirror clause's
	# case, and a block still crossing in a mirror reform keeps its gate there.
	#
	# The bare _formation_mirror_x flag is NOT the right test: it stays armed until the next
	# fresh order, long after any traversal finished -- including a hold_ground reform, which
	# re-squares with every man already on his post-reflection slot. Qualifying it with
	# "bodies have not yet settled onto their slots" (_reform_bodies_settled()) scopes the
	# gate to the genuine in-flight crossing and drops out once arrival catches up.
	#
	# Deliberately does NOT gate a frontage reshape (DUPLICATIO/EXPLICATIO file-doubling):
	# a reshape's lateral file crossing is exactly the crowding this pass exists to police.
	# Gating it off let bodies pass fully through each other with zero clearance instead
	# (measured: worst-case nnd collapsed from ~2.2 wu to ~0.13 wu on demos/inputs/
	# file-doubling.json), worse than the near-miss standoff was meant to fix.
	if unit.is_maneuver_turning() \
			or (unit._formation_mirror_x and not unit._reform_bodies_settled()):
		return PackedVector2Array()

	# An ordinary march never brings the settled gate below into play: target_slots moves
	# with the unit every tick, so a marching body is never within ARRIVE_EPS of it and
	# any_unsettled stays true forever -- paying the spatial-hash bucketing and neighbor scan
	# below on every tick for every marching unit buys nothing, since bodies marching in
	# formation already sit at min_pitch spacing, safely outside min_sep. Confine the pass to
	# the windows that actually matter: while a re-slot could still be crossing files
	# (unit._standoff_settle_until_tick, armed by set_formation/set_frontage/reform_ranks the
	# moment they re-slot the block -- see that field's own doc comment), or while FIGHTING,
	# whose unengaged rear ranks can go on stacking behind a front rank pinned against a
	# routing enemy for as long as the fight lasts and so are never covered by a settle
	# window at all. A REFORM hold is a third window, for the reason given above.
	#
	# A block out of good order outside all three windows is the exception: one whose men a march
	# has left strung out (a heading turn on the march, a block marching off scrambled from a
	# fight) has them walking back, each straight at his own slot, and with nothing keeping two
	# men of the block apart, a man walking back from far off walks through one nearer his slot
	# who stands on that line (the support clip's cavalry squadron: two riders 17 and 57 wu off
	# their slots came within 0.56 wu of each other as the farther one passed). So the pass also
	# runs while any unengaged man stands more than unit.standoff_off_slot_pitches file pitches off
	# his slot.
	var holding: bool = unit._reform_holding()
	if not holding and unit.state != Unit.State.FIGHTING \
			and Engine.get_physics_frames() > unit._standoff_settle_until_tick \
			and not _any_body_off_slot(unit, n, target_slots, is_engaged,
					unit.standoff_off_slot_pitches * unit.file_pitch_wu()):
		return PackedVector2Array()

	var body_radius: float = unit.soldier_body_radius()
	var two_bodies: float = body_radius * 2.0
	var file_pitch: float = unit.file_pitch_wu()
	var rank_pitch: float = unit.rank_pitch_wu()
	var min_pitch: float = minf(file_pitch, rank_pitch) if rank_pitch > 0.0 else file_pitch
	var min_sep: float = STANDOFF_MIN_SEP_FRAC * minf(two_bodies, min_pitch)
	if min_sep <= STANDOFF_MIN_SEP_FLOOR:
		return PackedVector2Array()

	# Engaged bodies are skipped so in-transit standoff never fights SoldierEnemyContact knockback during a press.
	var is_settled: PackedByteArray = PackedByteArray()
	is_settled.resize(n)
	var arrive_eps_sq: float = ARRIVE_EPS * ARRIVE_EPS
	var any_unsettled: bool = false

	for i in range(n):
		if i < unit._sim_soldier_hp.size() and unit._sim_soldier_hp[i] <= 0.0:
			continue
		if unit._sim_soldier_broken.size() > i and unit._sim_soldier_broken[i] != 0:
			continue
		if not is_engaged.is_empty() and is_engaged[i] == 1:
			continue
		if i < target_slots.size() and (unit._sim_soldier_pos[i] - target_slots[i]).length_squared() <= arrive_eps_sq:
			is_settled[i] = 1
		else:
			any_unsettled = true

	# When all active bodies sit on their slots, no in-transit pairs exist to separate:
	if not any_unsettled:
		return PackedVector2Array()

	var cell_size: float = min_sep
	var inv_cell_size: float = 1.0 / cell_size
	var cells: Dictionary[Vector2i, PackedInt32Array] = {}

	for i in range(n):
		if i < unit._sim_soldier_hp.size() and unit._sim_soldier_hp[i] <= 0.0:
			continue
		if unit._sim_soldier_broken.size() > i and unit._sim_soldier_broken[i] != 0:
			continue
		if not is_engaged.is_empty() and is_engaged[i] == 1:
			continue

		var p: Vector2 = unit._sim_soldier_pos[i]
		var ck := Vector2i(int(floor(p.x * inv_cell_size)), int(floor(p.y * inv_cell_size)))
		if not cells.has(ck):
			cells[ck] = PackedInt32Array()
		cells[ck].append(i)

	# The push is capped by the block's state the same way inside a REFORM hold as outside one:
	# a jog while the block stands (IDLE), the superphysical march cap while it moves.
	# STANDOFF_MAX_SPEED is lower than either for most unit types, so it is usually the cap
	# that binds.
	var speed_cap: float = unit.jog_speed if unit.state == Unit.State.IDLE \
			else unit.move_speed * unit.superphysical_speed_frac
	var max_sep_speed: float = minf(STANDOFF_MAX_SPEED, speed_cap)

	var sep_vel := PackedVector2Array()
	sep_vel.resize(n)
	sep_vel.fill(Vector2.ZERO)
	var min_sep_sq: float = min_sep * min_sep
	var inv_min_sep: float = 1.0 / min_sep
	# The contact band applies in a REFORM hold only (see STANDOFF_CONTACT_SEP_FRAC).
	var contact_sep: float = min_sep * STANDOFF_CONTACT_SEP_FRAC if holding else 0.0
	var has_vel: bool = unit._sim_body_vel.size() == n

	for i in range(n):
		if i < unit._sim_soldier_hp.size() and unit._sim_soldier_hp[i] <= 0.0:
			continue
		if unit._sim_soldier_broken.size() > i and unit._sim_soldier_broken[i] != 0:
			continue
		if not is_engaged.is_empty() and is_engaged[i] == 1:
			continue

		var p_i: Vector2 = unit._sim_soldier_pos[i]
		var ck := Vector2i(int(floor(p_i.x * inv_cell_size)), int(floor(p_i.y * inv_cell_size)))
		var settled_i: bool = is_settled[i] == 1

		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var nkey := Vector2i(ck.x + dx, ck.y + dy)
				if not cells.has(nkey):
					continue
				var arr: PackedInt32Array = cells[nkey]
				for j: int in arr:
					if j <= i:
						continue
					if settled_i and is_settled[j] == 1:
						continue
					var offset: Vector2 = p_i - unit._sim_soldier_pos[j]
					var d_sq: float = offset.length_squared()
					if d_sq >= min_sep_sq:
						continue
					var d: float = sqrt(d_sq)
					var overlap: float = (min_sep - d) * inv_min_sep
					var axis: Vector2
					if d > MIN_DIST:
						axis = offset / d
					else:
						var lo: int = mini(i, j)
						var angle: float = float(posmod(lo, STANDOFF_TIE_BREAK_DIRS)) / float(STANDOFF_TIE_BREAK_DIRS) * TAU
						# j > i always here (the pair loop above skips j <= i), so the
						# direction is fixed; push/reaction below stays equal-and-opposite.
						axis = -Vector2.RIGHT.rotated(angle)
					var push: Vector2 = axis * (max_sep_speed * overlap)
					# Inside the contact band the pair's closing is cancelled too: each
					# takes half of the speed at which the two are still walking into each
					# other, up to the per-man cap below (see STANDOFF_CONTACT_SEP_FRAC). Motion
					# across the axis is left alone, so the two still slide round each other.
					if d < contact_sep and has_vel:
						var closing: float = (unit._sim_body_vel[j] - unit._sim_body_vel[i]).dot(axis)
						if closing > 0.0:
							push += axis * (closing * 0.5)
					sep_vel[i] += push
					sep_vel[j] -= push

	# Bound per-soldier accumulated standoff velocity to the speed cap:
	var max_sep_sq: float = max_sep_speed * max_sep_speed
	for i in range(n):
		if sep_vel[i].length_squared() > max_sep_sq:
			sep_vel[i] = sep_vel[i].limit_length(max_sep_speed)

	return sep_vel


## Whether any living, unbroken, unengaged body of `unit` stands more than `dist` from its
## own slot in `target_slots` (_separate_same_unit's gate for a block out of good order).
static func _any_body_off_slot(unit: Unit, n: int, target_slots: PackedVector2Array,
		is_engaged: PackedByteArray, dist: float) -> bool:
	var dist_sq: float = dist * dist
	for i in range(mini(n, target_slots.size())):
		if i < unit._sim_soldier_hp.size() and unit._sim_soldier_hp[i] <= 0.0:
			continue
		if unit._sim_soldier_broken.size() > i and unit._sim_soldier_broken[i] != 0:
			continue
		if not is_engaged.is_empty() and is_engaged[i] == 1:
			continue
		if (unit._sim_soldier_pos[i] - target_slots[i]).length_squared() > dist_sq:
			return true
	return false


## Slide the regiment center toward its soldiers' centroid, at a bounded velocity (phase 5).
## The drift body_centroid - slot_centroid is how far the bodies have been pushed off
## formation as a whole. It compares the bodies with their slots, not with `position`, which
## matters because the slots are not always centred on `position`: a block with a short rear
## rank has its slot centroid a fraction of a rank toward its front. That offset is harmless
## while the slots move rigidly with `position`, but not while they move and the men
## deliberately do not follow (an in-place turn swings them about `position` under men who
## stand fast) or the men deliberately walk onto new ones (a hold-ground re-square's short
## files); both cases are handled below. Stepping
## the center a fraction of that each tick drives the slot centroid onto the body centroid
## (geometric decay, stable). When bodies are pushed off slot by friendly avoidance or
## knockback, the whole regiment follows -- so friendly regiments separate from the soldier
## level up. During a clean march the bodies sit on their moving slots (drift ~0) so this is
## silent and never double-counts the march. Capped at MAX_FOLLOW_SPEED*delta so the center
## can never teleport. Per-unit and RNG-free -- replay-safe.
##
## An anchored (asymmetric) explicatio/duplicatio moves the slot centroid off `position`
## ON PURPOSE, and for good, not for one maneuver: unit.frontage_anchor_offset shifts every slot by a fixed local-X amount so one
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
	var turning: bool = unit.is_order_turning()
	if not turning:
		unit.clear_turn_start_slots()
	if unit.is_wheeling() or unit.frontage_anchor_offset != 0.0:
		unit._body_follow_vel = Vector2.ZERO
		unit._step_slots_for_couple_valid = false   # this tick's handoff goes unused
		return
	var slots: PackedVector2Array
	if unit._step_slots_for_couple_valid and unit._step_slots_for_couple.size() == n:
		# step() computed this exact tick's slots already -- reuse instead of recomputing.
		slots = unit._step_slots_for_couple
	else:
		slots = unit.soldier_world_slots(unit.soldiers)
	unit._step_slots_for_couple_valid = false
	if slots.size() != n:
		return   # arrays mid-resize this tick; couple next tick when they realign
	# An in-place turn (an about-face or quarter-turn, standalone or a rear move's TURN phase,
	# from the order's response delay on) holds the men where they stand while the slots swing
	# about `position`. A block with a short rear rank has its slot centroid off `position`,
	# so that swing moves the slot centroid away from bodies nobody pushed. Measure the drift
	# against the slots as they stood when the turn began, carried along with `position`, so
	# the swing reads as nothing while a real push (a friendly shove) still moves the block.
	if turning:
		slots = unit.turn_start_slots(slots)
	# position_anchor_indices narrows the contact-tier selection down to the live
	# near-front ranks (Unit.ANCHOR_RANKS) once the unit has settled (see
	# Unit.position_anchor_indices / _position_anchor_unstable) -- Square/Schiltron and any
	# in-progress turn or reform keep the wider contact_soldier_indices selection this
	# always used to be. Also anchors a merely-in-contact (not fighting) regiment on its real
	# front-rank bodies, not the whole-block centroid -- see Unit._in_enemy_contact.
	var indices: PackedInt32Array = unit.position_anchor_indices(n)
	# With no engaged front to anchor on, the drift is averaged over every body -- and while
	# a reinforcement's newcomers are still walking in from behind, that average reads their
	# approach as the whole regiment standing off its slots. Hold `position` for the arrival
	# window instead (Unit._anchor_hold_until_tick); an engaged host anchors on its front
	# ranks alone and never enters this branch.
	if indices.is_empty() and unit.position_anchor_held():
		unit._body_follow_vel = Vector2.ZERO
		return
	var drift: Vector2
	if not indices.is_empty():
		drift = anchor_drift(unit, indices, slots)
	else:
		var body_centroid := Vector2.ZERO
		var slot_centroid := Vector2.ZERO
		var count: int = 0
		# A hold-ground re-square walks the short files onto slots a rank pitch away while the
		# full files already stand on theirs (Unit.arm_couple_transit). Those walkers are in
		# deliberate transit, not pushed off formation, so they stay out of the average until
		# each one arrives; the men already on their slots still carry any real push (a
		# friendly shove) into `position` as usual.
		var transit: bool = unit.couple_transit_active(n)
		var eps_sq: float = Unit.REFORM_SETTLE_EPS * Unit.REFORM_SETTLE_EPS
		var walking: int = 0
		for i in range(n):
			if transit and unit._couple_transit[i] != 0:
				if unit._sim_soldier_pos[i].distance_squared_to(slots[i]) > eps_sq:
					walking += 1
					continue
				unit._couple_transit[i] = 0
			body_centroid += unit._sim_soldier_pos[i]
			slot_centroid += slots[i]
			count += 1
		if transit and walking == 0:
			unit.clear_couple_transit()
		if count == 0:
			unit._body_follow_vel = Vector2.ZERO
			return
		var inv: float = 1.0 / float(count)
		drift = (body_centroid - slot_centroid) * inv
	var follow_step: Vector2 = (drift * Unit.FOLLOW_RATE * delta).limit_length(Unit.MAX_FOLLOW_SPEED * delta)
	unit._body_follow_vel = follow_step / delta if delta > 0.0 else Vector2.ZERO
	unit.position += follow_step


## How far the bodies `indices` (a non-empty anchor selection, Unit.position_anchor_indices)
## stand off the slots of `slots` (the unit's slot grid at its `position`) that a selection that
## size belongs on: their centroid less those slots' centroid. couple() moves `position` along
## it, so `position` plus it is where anchoring on those bodies settles the block. Moving
## `position` moves the slots with it and leaves the bodies, so the sum does not depend on
## where `position` stands.
static func anchor_drift(unit: Unit, indices: PackedInt32Array, slots: PackedVector2Array) -> Vector2:
	var body_centroid := Vector2.ZERO
	var slot_centroid := Vector2.ZERO
	var count: int = indices.size()
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
		# `count` (an anchor selection, a subset of this unit's own bodies) can never exceed
		# `slots.size()` (one slot per body, which both callers check), so the sum always runs
		# over exactly `count` slots -- no size-mismatch fallback needed here, unlike the
		# Square branch's live-perimeter selection above.
		for j in range(count):
			slot_centroid += slots[j]
	var inv: float = 1.0 / float(count)
	return (body_centroid - slot_centroid) * inv


## Advances and returns how far a body's arrival target has gone from the standing one
## toward the marching one (see arrival_target), 0 to 1, kept on the unit
## (Unit._march_target_frac). While the block marches it moves toward 1 by at most `delta` /
## march_target_ramp_s(unit) a step, so it covers the whole way in the time the march takes
## to reach Unit.march_target_full_speed() from rest at the unit's own acceleration. The
## step the march stops it returns 0, so the target switches straight back to the standing
## one. Only a stop of more than Unit.march_target_stop_grace_ticks counted steps drops the
## stored ramp (Unit._march_target_frac) to 0 as well: a march that dips to a standstill for
## a tick or two and goes on picks its ramp up where it left it, instead of starting it
## again from nothing each time (Unit._march_stopped_ticks counts the stop). A step stood in
## enemy contact, or while the block is engaged, is not counted and does not reset the
## count either, so a block that
## halts to fight marches off afterwards with the ramp it came in with: a fight is not a
## new start from rest, and it leaves the men scrambled, which is when they most need the
## marching target's direct walk back. Restarting the ramp there sent a scrambled block's
## men round the perimeter corridor again each time it marched off between bouts: the
## shallow cavalry troop of rout_rally, marching on its ATTACK between bouts, read a worst
## fitted residual of 41.29 wu against a limit of 30 on every seed with the restart, and
## passes without it, as it did with the hard switch. Depends only
## on unit-level state, so step() advances it once per unit-step and hands it to every
## body's arrival_target call (the same hoisting mass, body_radius and turning get above
## the per-soldier loop).
##
## The ramp keeps the target moving smoothly as a march begins: a hard switch at the first
## tick of the march swung the target of every man between the two bands round by tens of
## degrees at once (on the seed-0 catalog, 543 of 895 such switches swung a man's target
## more than 30 degrees), and he spent his acceleration turning instead of closing on his
## slot. Ramping by time, not reading the blend off the march speed, keeps a block that
## marches steadily below its full speed from holding a target part way between the two
## for the whole march: a speed-read blend left a 30-man block marching at 26 wu/s
## (general_doctrine_reserves, after its first melee) with men half sent round the
## perimeter corridor, and the block stayed scrambled out of contact (fitted residual 23.5
## to 33.9 wu). A stop is not ramped: the target switches back to the standing one at once,
## as it always has. A march stops outright when it runs into contact, and easing the target
## back there kept an attacker's men walking direct onto slots in the press: in the rear
## attack of test_melee_side_contact_battle, 10 attackers stood more than a rank inside the
## defender against none with the switch.
##
## The marching target uses the wider MARCHING_CORRIDOR_PROXIMITY_MULT band (own_slot is
## a moving point, not a fixed reform target -- see that const's own doc comment), straight
## or turning, whatever the block's depth: a lagging body keeps walking direct instead of
## being diverted into a perimeter corridor detour it would never catch up from. A turning
## march once kept the narrow band unless the block was deep (its formed turn derated),
## on the premise that a shallow block never lags far behind its own slots' arc. A combat
## re-face breaks that premise: it turns a marching block's whole slot grid about the anchor
## in one tick, and the men at its ends then stand ranks across and files along from their
## slots. Each such man was sent round the perimeter corridor, laid out in the grid's frame,
## while the block kept marching and turning, so the block did not re-form: in the support
## clip a 13-file archer block shooting on the march turned its grid 18.6 degrees, its end
## men stood up to 146 wu off, and 100 ticks later 25 of its 90 men were still walking the
## corridor (worst shape residual 29.9 to 32.3 on seeds 0 to 4 against a limit of 27; 17.6
## to 17.7 with the wide band). On the seed-0 catalog the wide band also re-formed the
## shallow cavalry troop in rout_rally, one of the clips the depth gate was kept for (its
## residual of 41.8 passed with the wide band, and passes on seeds 0 to 4 with the ramp,
## since a stop to fight does not restart it).
static func advance_march_target_frac(unit: Unit, delta: float) -> float:
	if not is_marching(unit):
		if not unit._in_enemy_contact and not unit.is_engaged():
			unit._march_stopped_ticks += 1
		if unit._march_stopped_ticks > unit.march_target_stop_grace_ticks:
			unit._march_target_frac = 0.0
		return 0.0
	unit._march_stopped_ticks = 0
	var ramp_s: float = march_target_ramp_s(unit)
	if ramp_s <= 0.0:
		unit._march_target_frac = 1.0
	else:
		unit._march_target_frac = move_toward(unit._march_target_frac, 1.0, delta / ramp_s)
	return unit._march_target_frac


## Seconds advance_march_target_frac takes to go all the way: the time a march takes to reach
## Unit.march_target_full_speed() from rest at the unit's own acceleration. 0 (switch at
## once) for a unit with no acceleration or no full speed.
static func march_target_ramp_s(unit: Unit) -> float:
	var full: float = unit.march_target_full_speed()
	if full <= 0.0 or unit.accel <= 0.0:
		return 0.0
	return full / unit.accel


## Whether the unit is actively marching this tick (its approach velocity is non-zero), a
## unit-level reading step() takes once rather than per body.
static func is_marching(unit: Unit) -> bool:
	return unit._approach_velocity.length_squared() > 0.0001


## Soldier `i`'s arrival target vector, `march_frac` (advance_march_target_frac) of the way from the
## standing target to the marching one. The standing target routes round the perimeter
## corridors outside the narrow CORRIDOR_PROXIMITY_MULT band; the marching one walks direct
## inside the wide MARCHING_CORRIDOR_PROXIMITY_MULT band and, on a straight march
## (`straight_march`: the block is not turning), takes _corridor_to_slot's radial-scaling
## branch. At 0 and 1 the target is exactly the one end; only a block setting off, while its
## ramp is under way, pays for both (blend_targets). A block that slows keeps the marching
## target, and one that stops switches straight back to the standing one.
static func arrival_target(unit: Unit, i: int, own_slot: Vector2, n: int, march_frac: float,
		straight_march: bool) -> Vector2:
	if march_frac <= 0.0:
		return _corridor_to_slot(unit, i, own_slot, n, CORRIDOR_PROXIMITY_MULT, false)
	var marching: Vector2 = _corridor_to_slot(unit, i, own_slot, n,
			MARCHING_CORRIDOR_PROXIMITY_MULT, straight_march)
	if march_frac >= 1.0:
		return marching
	var standing: Vector2 = _corridor_to_slot(unit, i, own_slot, n, CORRIDOR_PROXIMITY_MULT, false)
	return blend_targets(standing, marching, march_frac)


## The target `frac` of the way from `a` to `b`: its direction turns from a's to b's at a
## constant rate, frac times the angle between them, and its length runs linearly from a's
## to b's (Vector2.slerp). step() reads the man's desired speed off the target's length, and
## a plain lerp of two targets that point apart is shorter than either (two at right angles,
## halfway, are 0.71 of their length), so he would ask for less speed just because the two
## targets disagree. Normalizing that lerp keeps the length but not the rate: its direction
## barely moves near either end and swings round in the middle, 14.3 degrees in one tick of
## a 90-tick ramp for two targets 170 degrees apart, against 1.9 at the constant rate. Two
## targets pointing exactly apart turn through the half-turn at the same constant rate, on
## the side Vector2.angle_to's sign picks: it reads +PI or -PI as the sign of the zero cross
## product falls. From (10, 0) to (-20, 0) it reads +PI, so the target turns from +x toward
## +y, which is clockwise on screen in Godot's y-down frame, and halfway is (0, 15). A
## zero-length end has no direction, so there the blend is the plain lerp.
static func blend_targets(a: Vector2, b: Vector2, frac: float) -> Vector2:
	return a.slerp(b, frac)


## Computes the immediate arrival target vector for soldier `i` towards `own_slot`, routing
## along the formation's perimeter corridors (flank corridor and rear corridor) when crossing
## between different files and ranks to avoid cutting directly through standing formation ranks.
static func _corridor_to_slot(unit: Unit, i: int, own_slot: Vector2, n: int, proximity_mult: float, straight_march: bool) -> Vector2:
	var pos: Vector2 = unit._sim_soldier_pos[i]
	var diff: Vector2 = own_slot - pos
	if unit.state == Unit.State.ROUTING or (unit._sim_soldier_broken.size() > i and unit._sim_soldier_broken[i] != 0):
		return diff
	var spacing: float = unit.file_pitch_wu()
	if diff.length_squared() <= (spacing * proximity_mult) * (spacing * proximity_mult):
		return diff
	var ang: float = unit.soldier_block_world_angle()
	var p_local: Vector2 = (pos - unit.position).rotated(-ang)
	var t_local: Vector2 = (own_slot - unit.position).rotated(-ang)
	if unit._formation_mirror_x:
		p_local.x = -p_local.x
		t_local.x = -t_local.x

	var rank_pitch: float = unit.rank_pitch_wu()
	var depth: float = rank_pitch if rank_pitch >= 0.0 else spacing
	# Radial grid scaling (uniform density contraction or expansion during straight march):
	if straight_march and unit.state == Unit.State.MOVING and not unit._reform_holding():
		var same_quadrant: bool = (p_local.x * t_local.x >= -0.01) and (p_local.y * t_local.y >= -0.01)
		if same_quadrant and absf(t_local.x) > spacing * 0.2 and absf(t_local.y) > depth * 0.2:
			var k_x: float = p_local.x / t_local.x
			var k_y: float = p_local.y / t_local.y
			var max_k: float = maxf(k_x, k_y)
			if max_k > 0.0 and k_x > 0.0 and k_y > 0.0 and absf(k_x - k_y) <= 0.35 * max_k:
				if unit._formation_mirror_x:
					t_local.x = -t_local.x
				var target_world_direct: Vector2 = unit.position + t_local.rotated(ang)
				return target_world_direct - pos


	# Only route through perimeter corridors when moving across both ranks and files:
	if absf(p_local.y - t_local.y) > depth * 0.5 and absf(p_local.x - t_local.x) > spacing * 0.5:
		var files: int = unit.formation_files(n)
		var ranks: int = UnitFormation.ranks_for(n, files)
		var rx_half: float = (files - 1) * 0.5 * spacing
		var y_rear: float = (ranks - 1) * 0.5 * depth
		var rear_corridor_y: float = y_rear + depth * (CORRIDOR_CLEARANCE_MULT + CORRIDOR_LANE_STAGGER_FRAC * float((i / 2) % 2))

		# Case 1: moving to a rearward slot (destination is deeper than origin)
		if t_local.y >= p_local.y + depth * 0.5:
			var start_flank_sign: float = 1.0 if p_local.x >= 0.0 else -1.0
			var flank_x: float = start_flank_sign * (rx_half + spacing * (CORRIDOR_CLEARANCE_MULT + CORRIDOR_LANE_STAGGER_FRAC * float(i % 2)))
			if p_local.y < rear_corridor_y - depth * 0.5:
				t_local = Vector2(flank_x, rear_corridor_y)
			elif absf(p_local.x - t_local.x) > spacing * 0.5:
				t_local = Vector2(t_local.x, rear_corridor_y)
		# Case 2: moving from a rearward position to a forward slot
		elif p_local.y > t_local.y + depth * 0.5:
			var target_flank_sign: float = 1.0 if t_local.x >= 0.0 else -1.0
			var target_flank_x: float = target_flank_sign * (rx_half + spacing * (CORRIDOR_CLEARANCE_MULT + CORRIDOR_LANE_STAGGER_FRAC * float(i % 2)))
			if absf(p_local.x - target_flank_x) > spacing * 0.5 and p_local.y >= rear_corridor_y - depth * 0.5:
				t_local = Vector2(target_flank_x, rear_corridor_y)
			elif p_local.y >= t_local.y + depth * 0.5:
				t_local = Vector2(target_flank_x, t_local.y)

	if unit._formation_mirror_x:
		t_local.x = -t_local.x
	var target_world: Vector2 = unit.position + t_local.rotated(ang)
	return target_world - pos
