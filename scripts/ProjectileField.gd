class_name ProjectileField
## In-flight projectiles (#435), held as plain-data parallel arrays — no nodes — and ticked
## once per physics frame by Battle after the soldier passes settle. A ranged volley enqueues
## a projectile carrying its already-rolled arrow count (UnitCombat.shoot); the projectile
## flies a real ProjectilePhysics height arc, and when it lands (elapsed >= flight_time) those
## arrows fall on individual men, chosen from the launch point outward (the men the arrows
## reach first) and each resolved against the shield he is holding.
##
## Determinism (replays depend on it): projectiles are appended in launch order and resolved
## in that order, on the fixed physics delta, and the shield roll below draws from the one
## seeded stream once per arrow that finds a man -- a volley carrying more arrows than the
## target has living men draws one roll per man reached, not one per arrow. Within that loop
## the draw is unconditional, so the stream advances by the same count whichever way the
## geometry falls. Same seed + orders reproduce the same battle.
##
## Landing is now per arrow, not per volley: each of the near-side men the volley reaches
## takes one arrow against the shield he is actually holding, so a shield wall facing the
## archers loses far fewer men than an exposed flank does to the identical volley, and arrows
## that lodge stay to weigh the wall down. Cover / line-of-sight in the flat-vs-arced choice,
## friendly fire along the flight path, and non-soldier targets are later slices.

const UnitRef = preload("res://scripts/Unit.gd")

static var active: ProjectileField = null

# Gravity (wu/s^2): deliberately low vs. real 9.8*20 = 196, so volleys arc slowly and high
# enough to read at battlefield ranges. A balance knob.
const GRAVITY: float = 90.0

# Shield-block defaults. Each is mirrored by an instance field below, so a scenario, a
# balance pass, or a test varies it through the object rather than by editing the class --
# these consts are only today's value.
#
# SHIELD_BLOCK_SCALE turns a shield type's registry block value into the chance it stops an
# arrow that its arc actually covers: a scutum (0.60) stops ~72% of the arrows it faces, a
# cavalry round shield (0.25) ~30%, and an unshielded man (0.00) none. SHIELD_LODGE_SHARE
# splits those stops between arrows that glance off and arrows that stick fast.
const SHIELD_BLOCK_SCALE: float = 1.2
const SHIELD_LODGE_SHARE: float = 0.35

# An arrow that lodges hangs on the shield until the fight ends. ARROW_MASS_KG is one war
# arrow with its head; SHIELD_SAG_PER_KG is how much block chance a kilogram of them costs
# the man carrying it; SHIELD_MAX_SAG caps how far a shield can be dragged off the line, so
# a long bombardment degrades cover without ever erasing it.
const ARROW_MASS_KG: float = 0.075
const SHIELD_SAG_PER_KG: float = 1.5
const SHIELD_MAX_SAG: float = 0.3

var shield_block_scale: float = SHIELD_BLOCK_SCALE
var shield_lodge_share: float = SHIELD_LODGE_SHARE
var arrow_mass_kg: float = ARROW_MASS_KG
var shield_sag_per_kg: float = SHIELD_SAG_PER_KG
var shield_max_sag: float = SHIELD_MAX_SAG

# Arrows currently lodged in each regiment's shields, keyed by unit uid. Plain data like the
# flight arrays, and reset with the field when a battle starts.
var _lodged: Dictionary = {}

# Parallel arrays, one entry per in-flight projectile (all appended together, compacted together).
var _from: Array[Vector2] = []       # launch ground position (near-side selection origin)
var _to: Array[Vector2] = []         # aim / landing ground position
var _elapsed: Array[float] = []      # seconds since launch
var _flight: Array[float] = []       # total flight time to landing
var _speed: Array[float] = []        # launch speed (for the height arc)
var _angle: Array[float] = []        # launch angle
var _shooter_uid: Array[int] = []
var _target_uid: Array[int] = []
var _arrows: Array[int] = []         # arrows in the volley (potential hits, not guaranteed kills)
var _flank: Array[float] = []


## Number of projectiles in flight (for tests / diagnostics).
func count() -> int:
	return _elapsed.size()


## Enqueue a volley projectile flying from `from` to `to`, carrying `arrows` (flank already
## folded in) against `target_uid`, keyed to `shooter_uid` for the morale/fallen direction.
## `arrows` is how many arrows the volley delivers, NOT how many men it kills: against a
## target with a soldier layer each arrow is tested against the shield the man it reaches is
## holding, so only some of them pierce. It collapses to a casualty count only on the
## fieldless fallback path, which has no shields to test.
## `arced` picks the lob vs the flat trajectory. A degenerate (zero-distance) solve lands on
## the next tick so the volley still resolves.
func launch(from: Vector2, to: Vector2, shooter_uid: int, target_uid: int,
		arrows: int, flank: float, arced: bool) -> void:
	var dist: float = from.distance_to(to)
	var angle: float = ProjectilePhysics.ANGLE_ARCED if arced else ProjectilePhysics.ANGLE_FLAT
	var sol: Dictionary = ProjectilePhysics.solve_launch(dist, GRAVITY, angle)
	var flight: float = sol["flight_time"]
	if flight <= 0.0:
		flight = get_physics_delta()   # degenerate: resolve next tick rather than never
	_from.append(from)
	_to.append(to)
	_elapsed.append(0.0)
	_flight.append(flight)
	_speed.append(sol["speed"])
	_angle.append(angle)
	_shooter_uid.append(shooter_uid)
	_target_uid.append(target_uid)
	_arrows.append(arrows)
	_flank.append(flank)


## Advance every projectile by `delta`; resolve and remove any that have landed. Landed
## projectiles resolve in launch (array) order, on the fixed physics delta -- so the order in
## which their per-arrow shield rolls draw from the seeded stream is fixed too. `battle`
## supplies the uid->unit lookup.
func step(delta: float, battle: Node) -> void:
	var i: int = 0
	while i < _elapsed.size():
		_elapsed[i] += delta
		if _elapsed[i] >= _flight[i]:
			_resolve(i, battle)
			_remove_at(i)          # compact in place; don't advance i (the next entry shifts in)
		else:
			i += 1


## Height of projectile `i` above the ground right now (for a renderer; 0 once landed).
func height_of(i: int) -> float:
	return ProjectilePhysics.height_at(_speed[i], _angle[i], GRAVITY, _elapsed[i])


## Ground position of projectile `i` right now.
func ground_of(i: int) -> Vector2:
	var f: float = _elapsed[i] / _flight[i] if _flight[i] > 0.0 else 1.0
	return ProjectilePhysics.ground_at(_from[i], _to[i], f)


## Deliver projectile `i`'s arrows to its target. Skips a dead/freed target --- a
## routing one (broken or shattered) is still fair game; fleeing doesn't dodge an arrow
## already in flight. Uses the launch point as the near-side selection origin; the shooter
## (if still alive) is the killer for morale/fallen direction. Falls back to the regiment
## formula if the target has no soldier layer, and only on THAT path is the payload a
## casualty count -- with a soldier layer each arrow still has to beat a shield.
func _resolve(i: int, battle: Node) -> void:
	var target = battle.unit_by_uid(_target_uid[i])
	if target == null or not is_instance_valid(target):
		return
	if target.state == UnitRef.State.DEAD:
		return
	var killer = battle.unit_by_uid(_shooter_uid[i])   # may be null if the shooter has died
	if not target._sim_soldier_hp.is_empty():
		_land_on_soldiers(target, killer, _from[i], _arrows[i], _flank[i])
	elif killer != null:
		# Fallback for a target with no soldier layer: no shields to test, so every arrow
		# lands as a kill. `_arrows[i]` ALREADY has the flank folded in (in shoot), so apply
		# it directly -- routing it through take_casualties would re-apply flank_multiplier
		# and double it. register_casualties handles morale/rout.
		var kills: int = _arrows[i]
		target.soldiers = maxi(0, target.soldiers - kills)
		UnitCombat.register_casualties(target, kills, killer, _flank[i])


## Land a volley's arrows on individual men. The near-side soldiers the arrows reach first
## take one arrow each (the same selection the whole-volley path uses), and every arrow is
## tested against the shield THAT man is holding: one outside his shield's arc pierces and
## kills, one inside it is deflected or lodges and he lives. So a wall that faces the archers
## loses far fewer men to an identical volley than an exposed flank does, and arrows that
## lodge stay to weigh the wall down.
##
## One roll is drawn per arrow that finds a man -- `ranged_victims` returns min(arrows,
## living) indices and every one of them draws, before the arc is even consulted. So the draw
## count is fixed by the volley size and the survivor count, never by which way the men are
## turned, and a replay stays in step with the run it recorded. `reap` runs once, after the
## whole volley, so the morale hit still arrives as one blow rather than as one per man.
func _land_on_soldiers(target, killer, origin: Vector2, arrows: int, morale_flank: float) -> void:
	var sag: float = shield_sag(target)
	var pierced: int = 0
	for idx in SoldierMelee.ranged_victims(target, origin, arrows):
		var shield: Shield = _shield_of(target, idx)
		var block_value: float = shield.block_value if shield != null else 0.0
		var block: float = ProjectilePhysics.shield_block_chance(block_value, shield_block_scale, sag)
		var roll: float = Replay.rng.randf()
		var covered: bool = _shield_covers(target, idx, origin, shield)
		var outcome: int = ProjectilePhysics.resolve_impact(covered, block, shield_lodge_share, roll)
		if outcome == ProjectilePhysics.Impact.LODGE:
			_lodged[target.uid] = lodged_arrows(target.uid) + 1
		elif outcome == ProjectilePhysics.Impact.PIERCE:
			target._sim_soldier_hp[idx] = 0.0
			pierced += 1
	if pierced > 0:
		SoldierMelee.reap(target, killer, morale_flank)


## The shield soldier `idx` of `unit` is carrying, resolved through the per-soldier shield id
## with the unit's own type as the fallback (the same chain Unit.soldier_shield_block uses).
## Null only when neither id resolves, which the registry never produces for a spawned unit.
func _shield_of(unit, idx: int) -> Shield:
	var type_id: int = unit.shield_type_id
	if idx < unit._sim_soldier_shield_id.size():
		type_id = unit._sim_soldier_shield_id[idx]
	var s: Shield = LoadoutRegistry.shield(type_id)
	if s == null:
		s = LoadoutRegistry.shield(unit.shield_type_id)
	return s


## Whether soldier `idx` has his shield between himself and an arrow arriving from `origin`.
## Parent-local throughout -- `origin` and `_sim_soldier_pos` share the frame `position` is
## in, never global_position -- and it reads the man's OWN facing and hold angle when the
## bodies carry them, falling back to the regiment's heading and the shield's rest pose.
func _shield_covers(unit, idx: int, origin: Vector2, shield: Shield) -> bool:
	if shield == null:
		return false
	var facing: Vector2 = unit.facing
	if idx < unit._sim_soldier_facing.size():
		facing = unit._sim_soldier_facing[idx]
	var hold: float = unit.shield_rest_angle()
	if idx < unit._sim_soldier_shield_hold_angle.size():
		hold = unit._sim_soldier_shield_hold_angle[idx]
	var incoming: Vector2 = origin - unit._sim_soldier_pos[idx]
	return shield.covers(ProjectilePhysics.incoming_angle(facing, incoming), hold)


## Arrows currently lodged in `uid`'s shields; 0 for a regiment that has caught none.
func lodged_arrows(uid: int) -> int:
	return int(_lodged.get(uid, 0))


## The weight those lodged arrows hang on the regiment's shields, in kilograms.
func lodged_weight_kg(uid: int) -> float:
	return float(lodged_arrows(uid)) * arrow_mass_kg


## How much block chance `unit` has lost to the arrows stuck in its shields: the lodged
## weight PER SHIELD (spread over the living men, so a big regiment isn't punished for its
## size) converted to lost cover and capped. A shield hung with arrows drags off the line of
## the next volley, which is what makes a lodged arrow worth more than a deflected one.
##
## The pool is regiment-wide rather than per man, so a casualty does not carry his own
## shield's arrows out of it -- a shrinking regiment's remaining shields inherit the whole
## load. That is the crude half of the model, and it errs toward punishing a battered unit,
## which is the direction a bombardment should push anyway. Per-soldier lodging wants a
## per-soldier array that survives the casualty compaction, and is not this slice's work.
func shield_sag(unit) -> float:
	var per_shield: float = lodged_weight_kg(unit.uid) / float(maxi(1, unit.soldiers))
	return clampf(per_shield * shield_sag_per_kg, 0.0, shield_max_sag)


## Remove projectile `index` from every parallel array (swap-free, order-preserving).
func _remove_at(index: int) -> void:
	_from.remove_at(index)
	_to.remove_at(index)
	_elapsed.remove_at(index)
	_flight.remove_at(index)
	_speed.remove_at(index)
	_angle.remove_at(index)
	_shooter_uid.remove_at(index)
	_target_uid.remove_at(index)
	_arrows.remove_at(index)
	_flank.remove_at(index)


## The fixed physics step (deterministic); 1/60 fallback when no SceneTree is available.
func get_physics_delta() -> float:
	return 1.0 / float(maxi(1, Engine.physics_ticks_per_second))
