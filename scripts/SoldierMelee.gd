class_name SoldierMelee
## Per-soldier melee resolution (phase 4b), extracted from Unit.gd. Each engaged
## front-rank soldier of the attacker strikes the nearest enemy soldier within its
## weapon reach -- searching across EVERY adjacent enemy unit passed in, not
## just one, and not only that unit's facing-front engaged ranks, so a soldier fights
## whoever is actually next to it regardless of which regiment its own unit's
## `target_enemy` happens to point to -- rolling the model's
## opposed land contest (SoldierCombat); a hit wounds the enemy soldier's health pool,
## and a soldier whose health reaches 0 dies and is removed, re-packing the formation.
## Flanking (facing), the spear-vs-sword reach standoff, the charge, and compounding
## wounds all emerge here, not from modifiers.
## The strike's loadout stats resolve through the per-soldier id arrays: the attacker's
## weapon id sets the blow's lethality, and the struck soldier's shield id adds its
## block value to the type's stance residual (see LoadoutRegistry / soldier-loadout
## design doc), so a per-soldier loadout change alters combat immediately.
## Replay-deterministic: attackers in soldier-id order, defenders in uid order, a fixed
## TWO Replay.rng draws per in-reach strike (the land roll, then the fall roll), and no
## RNG in the death-reaping.

## Resolve one melee cadence of `attacker`'s engaged front rank striking whichever of
## `defenders` each attacking soldier finds nearest within reach. `defenders` is the
## strike target plus every other adjacent engaged enemy this tick (see
## Unit.resolve_soldier_melee) -- the primary target is included even if it has not
## latched engaged yet, so the opening blow of a fresh contact still searches its
## living soldiers. A size-1 array degenerates to exactly the old single-enemy
## resolution.
static func resolve(attacker: Unit, defenders: Array[Unit]) -> void:
	var attackers: PackedInt32Array = attacker.engaged_soldier_indices(attacker._sim_soldier_pos.size())
	if attackers.is_empty() or defenders.is_empty():
		return

	# Sorted by uid (not array/instance order, which the caller's contact-query iteration
	# doesn't guarantee stable) so an exact-distance tie in the nearest-target search below
	# resolves the same way every run -- the same determinism convention the retired
	# _next_multiple_engage_target round-robin used.
	var live_defenders: Array[Unit] = defenders.duplicate()
	live_defenders.sort_custom(func(x: Variant, y: Variant) -> bool: return (x as Unit).uid < (y as Unit).uid)

	# Per-defender-unit constants, computed once per DISTINCT defender (not once per call,
	# now that a strike can land on any of several simultaneous adjacent enemies) --
	# negligible extra work at the typical 1-3 adjacent enemies this ever sees.
	var def_indices: Array[PackedInt32Array] = []
	var def_prof: Array[Dictionary] = []
	var def_mods: Array[Vector2] = []
	var any_candidates := false
	for d in live_defenders:
		# Every living soldier is a valid HIT candidate, not only the defender's
		# facing-front engaged ranks. Attackers still strike from their own engaged
		# front (the selection above); targets are whoever those men can actually
		# reach. A facing-front-only candidate set misses the men under a rear or
		# flank blow -- a deep cavalry block's "front" sits a mounted rank-pitch
		# on the far side of the horse -- so the opening blow of a contact made
		# from behind found nobody in reach and dealt no wounds, while the
		# regiment formula (the path that used to take that blow) simply deleted
		# an absolute head-count. Reach is the real gate: rear ranks of a deep
		# block are out of a frontal sword's range, and in range of a rear attack.
		var di: PackedInt32Array = _living_soldier_indices(d)
		def_indices.append(di)
		def_prof.append(d.combat_profile())
		# Formation melee scaling, applied to the wound this cadence lands: a hunkered SQUARE
		# or a head-down TESTUDO attacker hits softer (their offence penalties), and a braced
		# SHIELD_WALL defender's locked shields blunt a frontal assault. order_mode_modifiers
		# folds in All-out attack the same way: mods.x boosts the wound when the ATTACKER is
		# fighting all-out, and dividing by mods.y (< 1.0 when the DEFENDER is) inflates the
		# wound the defender takes -- the same asymmetric attacker/defender lookup the
		# regiment-formula path (UnitCombat.strike/shoot) already applies, so the per-soldier
		# melee path (the dominant case whenever both sides are engaged) isn't left as a silent
		# no-op for this stance. Scales only the wound magnitude, never the seeded land/fall
		# rolls -- the RNG stream (draw count and order) is untouched, so replays stay
		# bit-identical.
		def_mods.append(UnitCombat.order_mode_modifiers(attacker, d))
		if not di.is_empty():
			any_candidates = true
	if not any_candidates:
		return

	var my_prof: Dictionary = attacker.combat_profile()
	var my_maxhp: float = my_prof["max_health"]
	var my_maxstam: float = my_prof["max_stamina"]
	var reach: float = attacker.soldier_reach()
	# formation_attack_factor has no per-soldier override (it's SQUARE/SCHILTRON's own
	# offence penalty, and neither formation ever marks a soldier broken -- see
	# breaks_under_encirclement), so it's hoisted out here, attacker-side only;
	# formation_melee_attack_factor and melee_defense_factor DO vary per soldier (an
	# individually broken soldier drops the multiplier back to 1.0 -- see below), so those
	# two are computed per strike instead.
	var atk_formation_scale: float = attacker.formation_attack_factor()

	# The nearest-target scan below is O(attackers x candidates) and dominates a melee tick, so
	# it is counted by ARITHMETIC rather than by tallying inside it: the candidate set is fixed
	# for the whole cadence (def_indices is built once, above) and each searching attacker walks
	# all of it -- the inner `continue` skips a dead body only after entering its iteration, and
	# nothing breaks out early. So the exact evaluation count is candidates x searchers, and the
	# only per-attacker cost is one integer increment.
	var candidates_per_attacker: int = 0
	for di_list in def_indices:
		candidates_per_attacker += di_list.size()
	var searchers: int = 0
	for ai in attackers:
		if ai < attacker._sim_prone.size() and attacker._sim_prone[ai] > 0.0:
			continue   # a felled attacker can't strike (no target search, no RNG — order stays stable)
		searchers += 1
		var apos: Vector2 = attacker._sim_soldier_pos[ai]
		# An individually broken attacker (Unit.is_soldier_broken, driven by SoldierEncirclement)
		# fights as an unmodified individual: it no longer earns (or suffers) its unit's own
		# stance melee-output modifier -- TESTUDO's "head-down, can barely swing" penalty is
		# exactly the assumption a surrounded soldier's broken formation can't back up any more.
		var attacker_broken: bool = attacker.is_soldier_broken(ai)
		var atk_melee_scale: float = 1.0 if attacker_broken else attacker.formation_melee_attack_factor()
		# Nearest LIVING enemy soldier within reach, across EVERY defender in this cadence --
		# a longer reach lets us hit foes who can't hit back (the spear screen), and a soldier
		# fights whoever's actually next to it, not only whichever regiment target_enemy points
		# to. Enumerated in the uid-sorted defenders order established above so an exact-
		# distance tie resolves the same way every run (the `<=` below keeps the pre-existing
		# last-checked-wins tie rule).
		var target: int = -1
		var target_def: int = -1
		var best_d_sq: float = reach * reach
		for dj in range(live_defenders.size()):
			var candidates: PackedInt32Array = def_indices[dj]
			if candidates.is_empty():
				continue
			var d: Unit = live_defenders[dj]
			for di in candidates:
				if d._sim_soldier_hp[di] <= 0.0:
					continue
				# OPTIMIZATION: Use distance_squared_to instead of distance_to to avoid expensive sqrt
				var d_sq: float = apos.distance_squared_to(d._sim_soldier_pos[di])
				if d_sq <= best_d_sq:
					best_d_sq = d_sq
					target = di
					target_def = dj
		if target < 0:
			continue   # nothing in reach this strike — no RNG drawn, so order stays stable

		var defender: Unit = live_defenders[target_def]
		var en_prof: Dictionary = def_prof[target_def]
		var en_maxhp: float = en_prof["max_health"]
		var en_maxstam: float = en_prof["max_stamina"]
		# The non-shield part of the defender's shield weight b: stance/training
		# deflection, per type, constant across the cadence. The shield's own block
		# value is read per strike through the struck soldier's shield id, so
		# b = residual + block_value — bit-for-bit the pre-split per-type weight.
		var en_shield_residual: float = en_prof["shield_residual"]
		var mods: Vector2 = def_mods[target_def]

		# Same per-soldier override on the defending side: a broken SHIELD_WALL soldier's
		# frontal melee bonus assumed its shield was still locked with its neighbours, which
		# is exactly what being surrounded breaks.
		var defender_broken: bool = defender.is_soldier_broken(target)
		var def_defense_scale: float = 1.0 if defender_broken else defender.melee_defense_factor(attacker)
		var wound_scale: float = atk_formation_scale * atk_melee_scale * def_defense_scale * mods.x / mods.y

		var dpos: Vector2 = defender._sim_soldier_pos[target]
		var axis: Vector2 = dpos - apos
		var push_dir: Vector2 = axis.normalized() if axis.length_squared() > 0.000001 else Vector2.ZERO
		# Closing speed along the strike axis -> the charge term c (bind on its own
		# line; an inline ternary as a call arg can mis-evaluate in GDScript).
		var closing: float = attacker._approach_velocity.dot(push_dir)
		var c: float = SoldierCombat.charge_factor(closing)
		# A prone defender has no active defence (phi -> 0): only its armour saves it.
		var prone_d: bool = target < defender._sim_prone.size() and defender._sim_prone[target] > 0.0
		var phi: float = 0.0 if prone_d else SoldierCombat.facing_gate(defender.facing, apos - dpos)
		var stam_a: float = attacker._sim_soldier_stamina[ai] \
				if ai < attacker._sim_soldier_stamina.size() else my_maxstam
		var stam_d: float = defender._sim_soldier_stamina[target] \
				if target < defender._sim_soldier_stamina.size() else en_maxstam
		var cond_a: float = SoldierCombat.condition(attacker._sim_soldier_hp[ai], my_maxhp) \
				* SoldierCombat.stamina_factor(stam_a, my_maxstam)
		var cond_d: float = SoldierCombat.condition(defender._sim_soldier_hp[target], en_maxhp) \
				* SoldierCombat.stamina_factor(stam_d, en_maxstam)
		# Strike-time loadout reads, through the per-soldier id arrays: the
		# attacker's weapon sets the blow's lethality and piercing nature, the struck
		# soldier's shield adds its block value to the defender's stance residual.
		var lethality_a: float = attacker.soldier_lethality(ai)
		var is_piercing: bool = attacker.soldier_is_piercing(ai)
		var shield_d: float = en_shield_residual + defender.soldier_shield_block(target)
		var p_land: float = SoldierCombat.land_chance(my_prof["skill"], en_prof["skill"], shield_d, phi, c, cond_a, cond_d)
		# One seeded draw per striking attacker, in id order, after the target is fixed.
		var landed: bool = Replay.rng.randf() < p_land
		# Knockback is the enemy collision response (no separation pass): every in-reach strike
		# imparts a momentum impulse away from the attacker -- a clean landing transmits full
		# momentum (eta 1), a turned-aside blow a fraction (ETA_DEFENDED), and a heavier body
		# (high mass) is shoved less. So a charging horse throws foot back hard while shrugging
		# off shoves, and a blocked spear wall still pushes a stalled enemy back. The body holds
		# the push, then decelerates and returns to its slot under bounded arrival force.
		# Velocity only -- never a position snap.
		var eta: float = 1.0 if landed else SoldierCombat.ETA_DEFENDED
		# Knockback focus (UnitCombat.KNOCKBACK_FOCUS_DAMAGE_MULT's counterpart): a much
		# bigger impulse in exchange for the attack_mult penalty already folded into
		# wound_scale above. Boosting the raw impulse (rather than only the capped speed
		# below) also raises the prone_chance draw further down, so "higher intensity" and
		# "higher probability" both fall out of this one multiplier.
		var kb_focus: bool = attacker.order_mode == Unit.ORDER_KNOCKBACK_FOCUS
		var impulse_mult: float = SoldierCombat.KNOCKBACK_FOCUS_IMPULSE_MULT if kb_focus else 1.0
		var impulse_mag: float = SoldierCombat.knockback_impulse(
				lethality_a, c, en_prof["mass"], eta, impulse_mult, is_piercing)
		# Bracing: a front-facing, set, deep file resists a shove with the whole column's
		# footing (docs/combat-model.md "Bracing"). Walk the target's file rearward (phi > 0 only:
		# a flank/rear blow gets no buttress), stopping at the first dead/missing rank. A
		# sub-capacity shove dies on the depth; only the surplus moves the front man. The depth
		# sum also raises the prone threshold so a set phalanx is harder to fell.
		var file_braces: PackedFloat32Array
		if phi > 0.0:
			# The defender's CURRENT grid file count (formation_files), not the wide-line
			# frontage() -- a SQUARE defender's file-stride must match the square grid its
			# soldiers are actually laid out on, or this walks the wrong rank_idx sequence.
			var frontage: int = defender.formation_files(defender._sim_soldier_pos.size())
			var n_def: int = defender._sim_soldier_pos.size()
			var br: float = defender.soldier_brace()
			var rank_idx: int = target
			while rank_idx < n_def:
				if defender._sim_soldier_hp[rank_idx] <= 0.0:
					break
				file_braces.append(br)
				rank_idx += frontage
		var brace_d: float = SoldierCombat.brace_depth(file_braces)
		# Weapon-differentiated ceiling (docs/combat-model.md "Bracing"): a grounded spear/pike
		# resists via an independent leveraged strut, so it absorbs more than a shield-only
		# soldier's friction/mass-stacking alone -- see SoldierCombat.brace_capacity_for_type.
		var j_cap: float = SoldierCombat.brace_capacity_for_type(
				defender.is_cavalry, defender.anti_cavalry, defender.is_ranged)
		var cap: float = j_cap * brace_d   # avoids a second walk of file_braces via brace_capacity()
		var received: float = maxf(0.0, impulse_mag - cap)
		# Knockback focus's own per-order push-distance parameter (Unit.
		# knockback_push_indefinite): "just clear the line" (the default) caps the shoved
		# body's speed so it coasts roughly past both blocks' combined front depth before
		# SoldierBodies.BODY_ACCEL_FLOOR's arrival recovery reins it back in -- floored at
		# KNOCKBACK_SPEED_MAX (SoldierCombat.knockback_focus_clear_line_cap) so a strong/
		# charging hit is never shoved LESS far by this default variant than a plain
		# attack already would be; "indefinite" uses a much higher fixed cap instead, so
		# the shove clearly outruns that. Only the struck DEFENDER's cap changes -- the
		# attacker's own recoil below keeps the ordinary KNOCKBACK_SPEED_MAX default,
		# since the push-distance parameter is about how far the struck body travels,
		# not the striker's own stagger.
		var defender_speed_cap: float = SoldierCombat.KNOCKBACK_SPEED_MAX
		if kb_focus:
			if attacker.knockback_push_indefinite:
				defender_speed_cap = SoldierCombat.KNOCKBACK_FOCUS_INDEFINITE_SPEED_CAP
			else:
				var clear_dist: float = attacker._front_depth() + defender._front_depth()
				defender_speed_cap = SoldierCombat.knockback_focus_clear_line_cap(
						clear_dist, SoldierBodies.BODY_ACCEL_FLOOR)
		# Newton's laws collision (bidirectional impulses): both attacker and defender
		# exchange momentum. The impulse is split inversely by effective mass (which
		# includes bracing). Bracing gates the DEFENDER's forward motion (via `cap`
		# above), but does NOT reduce the attacker's recoil — a braced defender still
		# pushes back with full force. Lighter units recoil harder; heavier units shrug
		# off shoves. See SoldierCollision.bidirectional_impulse.
		if impulse_mag > 0.0:
			var attacker_brace: float = attacker.soldier_brace()
			var impulses: Array = SoldierCollision.bidirectional_impulse(
				impulse_mag,
				push_dir,
				my_prof["mass"],
				attacker_brace,
				en_prof["mass"],
				brace_d
			)
			var impulse_attacker: Vector2 = impulses[0]
			var impulse_defender: Vector2 = impulses[1]
			# Apply recoil to attacker (always, even if bracing absorbs the defender's motion).
			if impulse_attacker.length_squared() > 0.0001:
				attacker._sim_body_vel[ai] = SoldierCombat.capped_knockback_velocity(
					attacker._sim_body_vel[ai], impulse_attacker)
			# Torque vs. translation partition (docs/combat-model.md "Coupling the slide and the fall:
			# a friction-anchored pivot"):
			# A defender's footing anchors the impulse up to J_anchor (mass & bracing scaled).
			# The anchored share J_rot turns into tipping torque; only the surplus J_trans breaks
			# the footing loose to translate/shove the body.
			var defender_speed_sq: float = defender._sim_body_vel[target].length_squared()
			var is_moving: bool = defender_speed_sq > SoldierCombat.STATIC_FRICTION_VELOCITY_GATE * SoldierCombat.STATIC_FRICTION_VELOCITY_GATE
			var parts: Array[float] = SoldierCombat.partition_impulse(received, en_prof["mass"], brace_d, is_moving)
			var j_trans: float = parts[1]
			if j_trans > 0.0:
				var braced_impulse_defender: Vector2 = SoldierCollision.braced_defender_impulse(
						impulse_defender, j_trans, impulse_mag)
				defender._sim_body_vel[target] = SoldierCombat.capped_knockback_velocity(
						defender._sim_body_vel[target], braced_impulse_defender, defender_speed_cap)
		# Accumulate under a clamp: impulses from every attacker shoving this body this
		# cadence accumulate in its velocity, and each application clamps the summed result
		# (SoldierCombat.capped_knockback_velocity) -- a pile-on in an intermixed press
		# knocks a man back body-lengths, never launches him across the field.
		if landed:
			defender._sim_soldier_hp[target] -= \
					SoldierCombat.wound(lethality_a, c, en_prof["armour"], cond_a, is_piercing) * wound_scale
		# Going prone: a big enough impulse delivers tipping torque that fells the defender
		# (docs/combat-model.md "Going prone and getting up" and "Coupling the slide and the fall").
		# The fall roll is a second seeded draw per striking attacker, ALWAYS drawn (after the
		# land roll, in id order) so the draw count per in-reach strike is fixed -- the size guard
		# gates only the assignment, never the draw, so an out-of-sync array can't silently shift
		# the RNG stream. A felled body loses active defence and can't strike until it rises; a
		# fresh blow on a downed man refreshes the timer, keeping him down under assault.
		var fall_roll: float = Replay.rng.randf()
		if target < defender._sim_prone.size() \
				and fall_roll < SoldierCombat.prone_chance(impulse_mag, en_prof["mass"], brace_d,
					defender._sim_body_vel[target].length_squared() > SoldierCombat.STATIC_FRICTION_VELOCITY_GATE * SoldierCombat.STATIC_FRICTION_VELOCITY_GATE):
			defender._sim_prone[target] = SoldierCombat.PRONE_RISE_TIME
		# Stamina drain: attacker pays KAPPA_A per strike thrown; defender pays KAPPA_D
		# scaled by how much of the blow it had to meet (phi*(1+c) — zero for prone/flanked).
		if ai < attacker._sim_soldier_stamina.size():
			attacker._sim_soldier_stamina[ai] = maxf(0.0,
				attacker._sim_soldier_stamina[ai] - SoldierCombat.KAPPA_A)
		if target < defender._sim_soldier_stamina.size():
			defender._sim_soldier_stamina[target] = maxf(0.0,
				defender._sim_soldier_stamina[target]
					- SoldierCombat.KAPPA_D * phi * (1.0 + maxf(0.0, c)))

	SimOps.add(SimOps.MELEE_CHECK, searchers * candidates_per_attacker)

	# reap() no-ops immediately when a given unit had zero deaths this cadence, so it's safe
	# (and simplest) to call it once per distinct defender in the candidate set, unconditionally
	# -- exactly generalizing the old single-defender "reap(defender, attacker)" call, which was
	# always made once regardless of whether that one defender actually lost anyone this tick.
	for d in live_defenders:
		reap(d, attacker)


## Remove `unit`'s soldiers whose health has reached 0: compact them out of the
## per-soldier arrays (so the formation re-packs around the survivors), drop the
## regiment count to match, and route the deaths through the unit's shared casualty
## handler for morale, rout/death, and the cosmetic fallen markers. `killer` is the
## attacking regiment (morale/fallen direction). `morale_flank` scales the morale hit:
## the melee path leaves it 1.0 (facing is already in the strike rolls), while a ranged
## volley passes its regiment-level flank so a shot into the rear routs harder — matching
## the regiment-formula path. Deterministic — no RNG; walks high-to-low so a removal
## never shifts an index still to be checked. Captures each dying soldier's own live
## `_sim_soldier_pos` before it's spliced out, so the cosmetic Fallen heap drops one mark
## at each man's REAL position — not an averaged point, and not the unit's idealized
## formation-slot geometry, which can have already scattered away from the live bodies
## mid-melee.
static func reap(unit: Unit, killer: Unit, morale_flank: float = 1.0) -> void:
	var dead: int = 0
	var dead_positions := PackedVector2Array()
	for i in range(unit._sim_soldier_hp.size() - 1, -1, -1):
		if unit._sim_soldier_hp[i] <= 0.0:
			dead_positions.push_back(unit._sim_soldier_pos[i])
			unit._sim_soldier_pos.remove_at(i)
			unit._sim_body_vel.remove_at(i)
			unit._sim_soldier_hp.remove_at(i)
			if i < unit._sim_steer.size():
				unit._sim_steer.remove_at(i)   # keep the steering array index-aligned
			if i < unit._sim_prone.size():
				unit._sim_prone.remove_at(i)   # and the prone timer
			if i < unit._sim_soldier_stamina.size():
				unit._sim_soldier_stamina.remove_at(i)   # and the stamina pool
			if i < unit._sim_soldier_weapon_id.size():
				unit._sim_soldier_weapon_id.remove_at(i)   # and the loadout type ids
			if i < unit._sim_soldier_shield_id.size():
				unit._sim_soldier_shield_id.remove_at(i)
			if i < unit._sim_soldier_shield_hold_angle.size():
				unit._sim_soldier_shield_hold_angle.remove_at(i)   # and the hold-angle state
			if i < unit._sim_soldier_file.size():
				# Keep file_major_reform's persistent file assignment index-aligned: trimming
				# at the dead soldier's own index (not recomputing) is what makes a casualty
				# preserve every OTHER survivor's file identity -- see Unit._ensure_file_assignment.
				# The rank half closes up over the gap the dead man leaves, so his own file's
				# survivors step forward and no other file moves -- and it goes FIRST, while
				# _sim_soldier_file still holds his entry to say which file that was.
				unit._sim_soldier_rank = UnitFormation.drop_rank_assignment(
						unit._sim_soldier_rank, unit._sim_soldier_file, i)
				unit._sim_soldier_file.remove_at(i)
			if i < unit._sim_soldier_square_slot.size():
				# Keep the square slot pairing index-aligned AND still a permutation:
				# dropping this man's entry and stepping every later cell id down is
				# what the grid itself does when it loses a soldier, so the survivors
				# hold the cells they already had instead of the whole block re-pairing
				# mid-fight -- see UnitFormation.drop_slot_assignment.
				unit._sim_soldier_square_slot = UnitFormation.drop_slot_assignment(
						unit._sim_soldier_square_slot, i)
			if i < unit._sim_soldier_row_slot.size():
				# Same trim for the row-major pairing a hold-ground reform leaves behind, and
				# for the same reason: a man who held his ground through the reflection keeps
				# holding it as the block takes losses, rather than the whole grid re-pairing
				# the moment someone dies. Normally empty, so this is usually a no-op.
				unit._sim_soldier_row_slot = UnitFormation.drop_slot_assignment(
						unit._sim_soldier_row_slot, i)
			if i < unit._sim_soldier_broken.size():
				unit._sim_soldier_broken.remove_at(i)   # and the encirclement-broken flag
			dead += 1
	if dead == 0:
		return
	unit.soldiers = maxi(0, unit.soldiers - dead)
	UnitCombat.register_casualties(unit, dead, killer, morale_flank, dead_positions)


## Living soldier indices of `unit`, in array order. Used as the melee HIT candidate
## set so a blow can land on whoever is actually in reach, not only the facing-front
## engaged selection (see resolve()'s defender loop). Deterministic -- walks the
## current `_sim_soldier_hp` snapshot, no RNG.
static func _living_soldier_indices(unit: Unit) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n: int = mini(unit._sim_soldier_pos.size(), unit._sim_soldier_hp.size())
	for i in range(n):
		if unit._sim_soldier_hp[i] > 0.0:
			out.append(i)
	return out


## Apply a ranged volley's `casualties` to `target` at the individual level: the men
## nearest `origin` (the launch point the arrows came from — the exposed rank they reach
## first) fall, tie-broken by soldier index for a stable order, then `reap` compacts them and
## drives morale/rout. `killer` is the shooting regiment (morale/fallen direction); it may be
## null if the shooter died while the volley was in flight. `origin` is parent-local — the
## same frame `_sim_soldier_pos` and `flank_multiplier` use, NOT global_position — so a caller
## passes the shooter's `.position` (or a projectile's launch position). `casualties` is the
## same count the regiment formula would remove (flank already folded in by the caller), so
## the volley's lethality and morale hit are unchanged — only *which* soldiers die (geometric,
## near-side) and the body compaction differ. Deterministic: reads positions + index, no RNG.
static func apply_ranged_casualties(target: Unit, origin: Vector2, killer: Unit, casualties: int, morale_flank: float) -> void:
	if casualties <= 0 or target._sim_soldier_hp.is_empty():
		return
	var living: Array[int] = []
	for i in range(target._sim_soldier_hp.size()):
		if target._sim_soldier_hp[i] > 0.0:
			living.append(i)
	living.sort_custom(SoldierMelee._nearest_to.bind(origin, target))
	var kills: int = mini(casualties, living.size())
	for k in range(kills):
		target._sim_soldier_hp[living[k]] = 0.0
	reap(target, killer, morale_flank)


## Strict-weak ordering for apply_ranged_casualties: nearer the origin first, ties broken
## by soldier index so the sort is total (Godot's sort_custom isn't stable) and deterministic.
static func _nearest_to(a: int, b: int, origin: Vector2, unit: Unit) -> bool:
	var da: float = origin.distance_squared_to(unit._sim_soldier_pos[a])
	var db: float = origin.distance_squared_to(unit._sim_soldier_pos[b])
	if da == db:
		return a < b
	return da < db
