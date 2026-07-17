class_name TierTransition
extends RefCounted
## The tier transition itself (docs/large-scale-simulation-design.md, phase 3): demotion
## collapses a close-tier unit down to its aggregate fields, and promotion reconstructs
## per-soldier state from those aggregates. Both directions hold to the replay-determinism
## bar the rest of the sim step lives under:
##
## - **Demotion is lossy but deterministic.** It drops the per-soldier arrays outright; the
##   unit's own scalar fields (position, facing, morale, soldiers, and the durable
##   formation/order modes) already carry the whole far-tier aggregate record, so nothing
##   new is computed and no randomness is involved. FarTierFormation.from_unit builds the
##   standalone record the isolated far-tier rules consume; the Unit-integrated transition
##   here keeps the unit's own fields as the single source of truth instead of mirroring
##   them into a second record that would go stale as the unit marches.
## - **Promotion is a pure function of the aggregate state plus a deterministic seed** —
##   a hash of (unit uid, promotion tick, battle seed), all already-serialized data — so
##   the same replay always reconstructs the identical soldier layout, with no live or
##   wall-clock RNG and no draw from the shared Replay.rng stream (which would desync
##   every later combat roll). Bodies fill the formation grid front-to-back up to the
##   living count, so the casualties the far tier accumulated read as consumed from the
##   rear ranks first, matching how the close tier's own casualty compaction trims the
##   rear bodies.
##
## A round trip is deterministic but NOT lossless: a demote-then-promote reconstructs *a*
## plausible layout consistent with the aggregates, not the exact pre-demotion bodies —
## the same "recompute a plausible state from durable inputs" the close tier already
## performs when it re-derives formation slots from position + facing + formation_mode.

# Maximum seeded scatter radius around each formation slot, as a fraction of the unit's
# live soldier spacing. Promoted bodies reappear NEAR their slots, not stacked on one
# point and not parade-exact — a formation marching at a distance isn't pixel-perfect —
# and the arrival dynamics (SoldierBodies) then ease each body onto its slot under the
# same bounded force that governs every other reform. A quarter of the spacing keeps
# even two worst-case neighbouring scatters from overlapping bodies at normal density.
const SCATTER_FRACTION: float = 0.25

# How much of a survivor's health pool the promotion wound distribution can take, at the
# extreme of a fully-mauled formation (casualty fraction 1.0). Scaled by the actual
# casualty fraction: an untouched formation reconstructs at exactly full health, while a
# mauled one carries plausible wounds spread across its survivors — losses the aggregate
# tier recorded but could not attribute to individual bodies. Capped at half the pool so
# no reconstructed soldier spawns near death.
const WOUND_SPREAD: float = 0.5


## Whether `u` is in a state the lossy demotion reduction can collapse safely: close-tier,
## idle or marching, and with no per-soldier state currently owned by a drill, maneuver,
## reform hold, or relief swap (those hold in-flight per-soldier context — facings mid-turn,
## a parked march leg, an interleaving partner — that the aggregate record cannot carry).
## The maneuver and relief context lives on the current Order (turn_target / active leaf /
## friendly_target), so those checks read the queue; a relieved unit holds no swap state of
## its own, but it just left melee, so the engaged linger keeps it close-tier through the
## pass-through window. A fighting or engaged unit never qualifies; the demote trigger
## distance already sits far beyond every combat range, so this mostly guards the linger
## window and mid-maneuver edge cases. Pure read of deterministic sim fields — replay-safe.
static func can_demote(u: Unit) -> bool:
	if u.tier != FormationTier.CLOSE:
		return false
	if u.state != Unit.State.IDLE and u.state != Unit.State.MOVING:
		return false
	if u.is_engaged():
		return false
	# An order-driven in-place turn or wheel, or the reactive engage re-face: the bodies
	# are mid-arc, holding facings the aggregate record cannot carry.
	if u.is_maneuver_turning():
		return false
	# _reform_holding() covers both a plain reform-before-move pause AND a phased rear move
	# parked between its about-face and its march (the REFORM leaf still owns the ranks, with
	# the march leg parked behind it) -- one check, since Slice 1 ported both onto the same
	# REFORM leaf order mechanism. Plain MARCH is aggregate-safe.
	if u._per_soldier_facing or u._reform_holding():
		return false
	var o: Order = u.current_order
	# A live relief keeps the reliever close-tier: the swap runs on per-soldier
	# pass-through geometry from approach to resolution.
	if o != null and o.type == Order.Type.RELIEF:
		return false
	return true


## Demote `u` to the far tier: drop every per-soldier array. The unit's own scalar fields
## keep carrying the aggregate state (position, facing, morale, soldiers, formation_mode,
## spacing_scale, order_mode), so nothing else changes — regiment-level movement, morale,
## and orders continue exactly as before; only the per-soldier layer (arrival dynamics,
## steering, per-soldier melee, and the O(soldiers) memory) goes away. A pure, RNG-free
## reduction. Callers gate on can_demote(); demote itself just performs the drop.
static func demote(u: Unit) -> void:
	u.tier = FormationTier.FAR
	u._sim_soldier_pos = PackedVector2Array()
	u._sim_body_vel = PackedVector2Array()
	u._sim_steer = PackedVector2Array()
	u._sim_soldier_hp = PackedFloat32Array()
	u._sim_prone = PackedFloat32Array()
	u._sim_soldier_stamina = PackedFloat32Array()
	u._sim_soldier_weapon_id = PackedInt32Array()
	u._sim_soldier_shield_id = PackedInt32Array()
	u._sim_soldier_shield_hold_angle = PackedFloat32Array()
	u._sim_soldier_facing = PackedVector2Array()
	u._per_soldier_facing = false
	u._render_dirty = true   # the render swaps to the aggregate (formation-grid) marks


## The deterministic promotion seed: a hash of already-serialized data only — the unit's
## replay-stable uid, the tick the promotion fires on, and the battle seed the replay
## file carries. Two runs of the same replay promote the same unit at the same tick with
## the same battle seed, so they derive the same value; a different unit, tick, or battle
## gets an unrelated stream.
static func promotion_seed(uid: int, tick: int, battle_seed: int) -> int:
	return hash([uid, tick, battle_seed])


## Promote `u` back to the close tier: reconstruct the full per-soldier state from the
## unit's aggregate fields, seeded by promotion_seed — a locally-seeded RNG, never the
## shared Replay.rng stream, so promotion neither draws live randomness nor perturbs any
## later combat roll. The layout fills the formation grid front-to-back up to the living
## count (rear ranks absorb the recorded casualties), each body landing within
## SCATTER_FRACTION of its slot at rest; survivors of a formation that took losses carry
## a seeded wound distribution (see WOUND_SPREAD), everyone stands (no prone carry-over),
## and stamina reads fully rested — bursts of fatigue are below the far tier's resolution.
static func promote(u: Unit, tick: int, battle_seed: int) -> void:
	u.tier = FormationTier.CLOSE
	var n: int = u.soldiers
	var slots: PackedVector2Array = u.soldier_world_slots(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = promotion_seed(u.uid, tick, battle_seed)
	var scatter_r: float = minf(u.file_pitch_wu(), u.rank_pitch_wu()) * SCATTER_FRACTION
	var profile: Dictionary = u.combat_profile()
	var max_health: float = profile["max_health"]
	var wound_cap: float = 0.0
	if u.max_soldiers > 0:
		wound_cap = WOUND_SPREAD * float(u.max_soldiers - n) / float(u.max_soldiers)
	var pos := PackedVector2Array()
	pos.resize(n)
	var hp := PackedFloat32Array()
	hp.resize(n)
	for i in range(n):
		# Fixed three-draw sequence per body (angle, radius, wound), so the stream stays
		# aligned regardless of the aggregate values. sqrt on the radius roll makes the
		# scatter uniform over the disc rather than bunched at the centre.
		var scatter_angle: float = rng.randf_range(0.0, TAU)
		var scatter_dist: float = scatter_r * sqrt(rng.randf())
		pos[i] = slots[i] + Vector2.from_angle(scatter_angle) * scatter_dist
		hp[i] = max_health * (1.0 - wound_cap * rng.randf())
	u._sim_soldier_pos = pos
	u._sim_soldier_hp = hp
	u._sim_body_vel = PackedVector2Array()
	u._sim_body_vel.resize(n)   # at rest; the arrival dynamics ease each body onto its slot
	u._sim_steer = PackedVector2Array()
	u._sim_steer.resize(n)
	u._sim_prone = PackedFloat32Array()
	u._sim_prone.resize(n)   # 0 = standing
	u._sim_soldier_stamina = PackedFloat32Array()
	u._sim_soldier_stamina.resize(n)
	u._sim_soldier_stamina.fill(profile["max_stamina"])
	u._sim_soldier_weapon_id = PackedInt32Array()
	u._sim_soldier_weapon_id.resize(n)
	u._sim_soldier_weapon_id.fill(u.weapon_type_id)
	u._sim_soldier_shield_id = PackedInt32Array()
	u._sim_soldier_shield_id.resize(n)
	u._sim_soldier_shield_id.fill(u.shield_type_id)
	# Shield hold angles reconstruct at the type's rest pose — the same value the
	# initial seed uses; any braced/locked posture is below the far tier's resolution.
	u._sim_soldier_shield_hold_angle = PackedFloat32Array()
	u._sim_soldier_shield_hold_angle.resize(n)
	u._sim_soldier_shield_hold_angle.fill(u.shield_rest_angle())
	u._sim_soldier_facing = u.soldier_world_facings(n)
	u._per_soldier_facing = false
	u._render_dirty = true   # fresh bodies need an initial draw
