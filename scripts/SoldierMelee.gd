class_name SoldierMelee
## Per-soldier melee resolution (phase 4b), extracted from Unit.gd. Each engaged
## front-rank soldier of the attacker strikes the nearest enemy soldier within its
## weapon reach, rolling the model's opposed land contest (SoldierCombat); a hit
## wounds the enemy soldier's health pool, and a soldier whose health reaches 0 dies
## and is removed, re-packing the formation. Flanking (facing), the spear-vs-sword reach
## standoff, the charge, and compounding wounds all emerge here, not from modifiers.
## The strike's loadout stats resolve through the per-soldier id arrays: the attacker's
## weapon id sets the blow's lethality, and the struck soldier's shield id adds its
## block value to the type's stance residual (see LoadoutRegistry / soldier-loadout
## design doc), so a per-soldier loadout change alters combat immediately.
## Replay-deterministic: attackers in soldier-id order, a fixed TWO Replay.rng draws per
## in-reach strike (the land roll, then the fall roll), and no RNG in the death-reaping.

## Resolve one melee cadence of `attacker`'s engaged front rank striking `defender`.
static func resolve(attacker: Unit, defender: Unit) -> void:
	var attackers: PackedInt32Array = attacker.engaged_soldier_indices(attacker._sim_soldier_pos.size())
	var defenders: PackedInt32Array = defender.engaged_soldier_indices(defender._sim_soldier_pos.size())
	if attackers.is_empty() or defenders.is_empty():
		return

	var my_prof: Dictionary = attacker.combat_profile()
	var en_prof: Dictionary = defender.combat_profile()
	var my_maxhp: float = my_prof["max_health"]
	var en_maxhp: float = en_prof["max_health"]
	var my_maxstam: float = my_prof["max_stamina"]
	var en_maxstam: float = en_prof["max_stamina"]
	# The non-shield part of the defender's shield weight b: stance/training
	# deflection, per type, constant across the cadence. The shield's own block
	# value is read per strike through the struck soldier's shield id, so
	# b = residual + block_value — bit-for-bit the pre-split per-type weight.
	var en_shield_residual: float = en_prof["shield_residual"]
	var reach: float = attacker.soldier_reach()
	# Formation melee scaling, applied to the wound this cadence lands: a hunkered SQUARE
	# or a head-down TESTUDO attacker hits softer (their offence penalties), and a braced
	# SHIELD_WALL defender's locked shields blunt a frontal assault. All are regiment-level
	# (constant across the cadence, from the units' formation and relative facing), so
	# compute once. Scales only the wound magnitude, never the seeded land/fall rolls --
	# the RNG stream (draw count and order) is untouched, so replays stay bit-identical.
	var wound_scale: float = attacker.formation_attack_factor() \
			* attacker.formation_melee_attack_factor() \
			* defender.melee_defense_factor(attacker)

	for ai in attackers:
		if ai < attacker._sim_prone.size() and attacker._sim_prone[ai] > 0.0:
			continue   # a felled attacker can't strike (no target search, no RNG — order stays stable)
		var apos: Vector2 = attacker._sim_soldier_pos[ai]
		# Nearest LIVING enemy soldier within reach — a longer reach lets us hit foes
		# who can't hit back (the spear screen).
		var target: int = -1
		var best_d: float = reach
		for di in defenders:
			if defender._sim_soldier_hp[di] <= 0.0:
				continue
			var d: float = apos.distance_to(defender._sim_soldier_pos[di])
			if d <= best_d:
				best_d = d
				target = di
		if target < 0:
			continue   # nothing in reach this strike — no RNG drawn, so order stays stable

		var dpos: Vector2 = defender._sim_soldier_pos[target]
		var axis: Vector2 = dpos - apos
		var push_dir: Vector2 = axis.normalized() if axis.length() > 0.001 else Vector2.ZERO
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
		# attacker's weapon sets the blow's lethality, the struck soldier's
		# shield adds its block value to the defender's stance residual.
		var lethality_a: float = attacker.soldier_lethality(ai)
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
		var impulse_mag: float = SoldierCombat.knockback_impulse(lethality_a, c, en_prof["mass"], eta)
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
		var cap: float = SoldierCombat.BRACE_CAPACITY * brace_d   # avoids a second walk of file_braces
		var received: float = maxf(0.0, impulse_mag - cap)
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
			if impulse_attacker.length() > 0.01:
				attacker._sim_body_vel[ai] = SoldierCombat.capped_knockback_velocity(
					attacker._sim_body_vel[ai], impulse_attacker)
			# Apply reduced impulse to defender, still gated by bracing capacity: scale the
			# momentum-split defender impulse by the surviving fraction of the strike above
			# the file's brace capacity (SoldierCollision.braced_defender_impulse), so the
			# shove grows smoothly from zero at `cap` instead of jumping straight to the full
			# mass-split impulse the instant impulse_mag crosses it. The attacker's own recoil
			# (above) is untouched by this scaling, matching the "bracing does NOT reduce the
			# attacker's recoil" rule stated above.
			# Static friction gates whether the surviving impulse moves the defender's body AT
			# ALL: a resting (or slow) body needs `received` to clear a mass/bracing-scaled
			# threshold before it budges, so a genuinely tiny shove leaves it standing still
			# instead of nudging it (SoldierCollision.overcomes_static_friction). A body already
			# in motion has no such gate (kinetic friction only) -- it's the CURRENT velocity,
			# read before this strike's own impulse is applied, that decides which regime applies.
			if received > 0.0 and SoldierCollision.overcomes_static_friction(
					received, defender._sim_body_vel[target].length(), en_prof["mass"], brace_d):
				var braced_impulse_defender: Vector2 = SoldierCollision.braced_defender_impulse(
						impulse_defender, received, impulse_mag)
				defender._sim_body_vel[target] = SoldierCombat.capped_knockback_velocity(
						defender._sim_body_vel[target], braced_impulse_defender)
		# Accumulate under a clamp: impulses from every attacker shoving this body this
		# cadence accumulate in its velocity, and each application clamps the summed result
		# (SoldierCombat.capped_knockback_velocity) -- a pile-on in an intermixed press
		# knocks a man back body-lengths, never launches him across the field.
		if landed:
			defender._sim_soldier_hp[target] -= \
					SoldierCombat.wound(lethality_a, c, en_prof["armour"], cond_a) * wound_scale
		# Going prone: a big enough impulse fells the defender. The fall roll is a second seeded
		# draw per striking attacker, ALWAYS drawn (after the land roll, in id order) so the draw
		# count per in-reach strike is fixed -- the size guard gates only the assignment, never
		# the draw, so an out-of-sync array can't silently shift the RNG stream. A felled body
		# loses active defence and can't strike until it rises; a fresh blow on a downed man
		# refreshes the timer, keeping him down under assault. Prone rolls on the full impulse;
		# the depth brace raises the threshold so a set phalanx resists going down.
		var fall_roll: float = Replay.rng.randf()
		if target < defender._sim_prone.size() \
				and fall_roll < SoldierCombat.prone_chance(impulse_mag, en_prof["mass"], brace_d):
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

	reap(defender, attacker)


## Remove `unit`'s soldiers whose health has reached 0: compact them out of the
## per-soldier arrays (so the formation re-packs around the survivors), drop the
## regiment count to match, and route the deaths through the unit's shared casualty
## handler for morale, rout/death, and the cosmetic fallen markers. `killer` is the
## attacking regiment (morale/fallen direction). `morale_flank` scales the morale hit:
## the melee path leaves it 1.0 (facing is already in the strike rolls), while a ranged
## volley passes its regiment-level flank so a shot into the rear routs harder — matching
## the regiment-formula path. Deterministic — no RNG; walks high-to-low so a removal
## never shifts an index still to be checked.
static func reap(unit: Unit, killer: Unit, morale_flank: float = 1.0) -> void:
	var dead: int = 0
	for i in range(unit._sim_soldier_hp.size() - 1, -1, -1):
		if unit._sim_soldier_hp[i] <= 0.0:
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
			dead += 1
	if dead == 0:
		return
	unit.soldiers = maxi(0, unit.soldiers - dead)
	UnitCombat.register_casualties(unit, dead, killer, morale_flank)


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
