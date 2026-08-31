extends GutTest
## Phase 4a of individual-level collision (see docs/combat-model.md): the
## probabilistic per-soldier combat MATH, as pure deterministic functions, before
## it is wired into the live melee loop (phase 4b). These pin each equation in the
## design note against its implementation — the per-type profile, the charge term,
## the facing gate, the opposed land contest, and the wound — so the spec and the
## code can be checked against each other and the math stays reproducible.

const TOL: float = 1e-4

# --- relative_mass_from_kg (the derived contact-mass scalar) ------------------

func test_relative_mass_from_kg_baseline_is_one() -> void:
	# CONTACT_MASS_BASELINE_KG is exactly the heavy-foot body_mass_kg (80), so a
	# soldier weighing the baseline gets the sim's canonical relative mass of 1.0.
	assert_eq(SoldierCombat.relative_mass_from_kg(80.0), 1.0)


func test_relative_mass_from_kg_scales_linearly() -> void:
	assert_almost_eq(SoldierCombat.relative_mass_from_kg(70.0), 0.875, TOL,
		"a 70 kg archer is 7/8 of the baseline")
	assert_almost_eq(SoldierCombat.relative_mass_from_kg(450.0), 5.625, TOL,
		"the warhorse's own real mass, relative to the baseline")
	assert_eq(SoldierCombat.relative_mass_from_kg(0.0), 0.0, "no mass, no relative mass")


func test_relative_mass_from_kg_is_additive_across_components() -> void:
	# Linear in its input, so summing two components' relative masses equals the
	# relative mass of their combined real weight (rider + mount composition
	# relies on exactly this property).
	var rider: float = SoldierCombat.relative_mass_from_kg(75.0)
	var horse: float = SoldierCombat.relative_mass_from_kg(450.0)
	assert_almost_eq(rider + horse, SoldierCombat.relative_mass_from_kg(525.0), TOL)


# --- Per-type combat profile (docs/combat-model.md "Soldier attributes") ------

func test_profile_skill_is_training() -> void:
	# Skill s is the unit's training, clamped to [0, 1], for every type.
	assert_almost_eq(SoldierCombat.profile_for(false, true, false, 0.75)["skill"], 0.75, TOL)
	assert_almost_eq(SoldierCombat.profile_for(true, false, false, 0.6)["skill"], 0.6, TOL)
	assert_almost_eq(SoldierCombat.profile_for(false, false, false, 1.4)["skill"], 1.0, TOL,
		"training above 1 clamps to 1")
	assert_almost_eq(SoldierCombat.profile_for(false, false, false, -0.2)["skill"], 0.0, TOL,
		"training below 0 clamps to 0")


func test_profile_spearmen_values() -> void:
	# shield_residual 0.05 is the braced anti-cavalry footing the pre-split 0.65
	# shield weight carried beyond the scutum's own 0.60 block value.
	var p: Dictionary = SoldierCombat.profile_for(false, true, false, 0.75)
	assert_almost_eq(p["armour"], 0.35, TOL)
	assert_almost_eq(p["shield_residual"], 0.05, TOL)
	assert_almost_eq(p["max_health"], 100.0, TOL)
	assert_almost_eq(p["max_stamina"], 100.0, TOL)


func test_profile_cavalry_values() -> void:
	# Cavalry flag wins even if other flags are set (it is checked first).
	# No stance residual: their round shield's block value is the whole weight.
	var p: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6)
	assert_almost_eq(p["armour"], 0.40, TOL)
	assert_almost_eq(p["shield_residual"], 0.0, TOL)
	assert_almost_eq(p["max_health"], 140.0, TOL)
	assert_almost_eq(p["max_stamina"], 120.0, TOL)


func test_profile_archer_values() -> void:
	# shield_residual 0.05 is unshielded deflection — archers carry SHIELD_NONE
	# (block 0), so their whole pre-split 0.05 weight is stance, not shield.
	var p: Dictionary = SoldierCombat.profile_for(false, false, true, 0.3)
	assert_almost_eq(p["armour"], 0.10, TOL)
	assert_almost_eq(p["shield_residual"], 0.05, TOL)
	assert_almost_eq(p["max_health"], 80.0, TOL)
	assert_almost_eq(p["max_stamina"], 90.0, TOL)


func test_profile_infantry_is_the_default() -> void:
	# No stance residual: the scutum's block value is the whole 0.60 weight.
	var p: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5)
	assert_almost_eq(p["armour"], 0.45, TOL)
	assert_almost_eq(p["shield_residual"], 0.0, TOL)
	assert_almost_eq(p["max_health"], 110.0, TOL)
	assert_almost_eq(p["max_stamina"], 100.0, TOL)


func test_profile_typed_panoply_armour_matches_the_legacy_rows_bit_for_bit() -> void:
	# Every roster type's default armor id must reproduce the legacy row's armour
	# EXACTLY — the typed loadout renames the scalar's home, it must not move
	# combat outcomes by any amount. Mass is covered separately below: unlike
	# armour, it is now DERIVED from real body/mount kilograms rather than a
	# renamed literal, so most types are unchanged but cavalry and archers are not
	# (see test_profile_typed_panoply_mass_is_derived_from_real_kilograms).
	var inf: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5,
			LoadoutRegistry.ARMOR_HAMATA, LoadoutRegistry.MOUNT_NONE)
	assert_eq(inf["armour"], 0.45, "typed infantry armour == the legacy literal")
	var spear: Dictionary = SoldierCombat.profile_for(false, true, false, 0.75,
			LoadoutRegistry.ARMOR_LINOTHORAX, LoadoutRegistry.MOUNT_NONE)
	assert_eq(spear["armour"], 0.35, "typed spearman armour == the legacy literal")
	var arch: Dictionary = SoldierCombat.profile_for(false, false, true, 0.3,
			LoadoutRegistry.ARMOR_TUNIC, LoadoutRegistry.MOUNT_NONE)
	assert_eq(arch["armour"], 0.10, "typed archer armour == the legacy literal")
	var cav: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6,
			LoadoutRegistry.ARMOR_SQUAMATA, LoadoutRegistry.MOUNT_WARHORSE)
	assert_eq(cav["armour"], 0.40, "typed cavalry armour == the legacy literal")


func test_profile_typed_panoply_mass_is_derived_from_real_kilograms() -> void:
	# Mass is relative_mass_from_kg(body_mass_kg) [+ relative_mass_from_kg(mount.mass_kg)
	# when mounted] — no separately-tuned relative constant anywhere. Infantry and
	# spearmen both weigh the 80 kg baseline, so their mass is unchanged at 1.0.
	# Archers (70 kg) and cavalry (75 kg rider + 450 kg warhorse) genuinely change
	# from the old tuned literals (0.9 and 2.5) to the values real body/mount
	# kilograms actually derive.
	var inf: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5,
			LoadoutRegistry.ARMOR_HAMATA, LoadoutRegistry.MOUNT_NONE)
	assert_eq(inf["mass"], 1.0, "80 kg infantry over an 80 kg baseline is unchanged")
	var spear: Dictionary = SoldierCombat.profile_for(false, true, false, 0.75,
			LoadoutRegistry.ARMOR_LINOTHORAX, LoadoutRegistry.MOUNT_NONE)
	assert_eq(spear["mass"], 1.0, "80 kg spearmen over an 80 kg baseline is unchanged")
	var arch: Dictionary = SoldierCombat.profile_for(false, false, true, 0.3,
			LoadoutRegistry.ARMOR_TUNIC, LoadoutRegistry.MOUNT_NONE)
	assert_almost_eq(arch["mass"], 0.875, TOL, "70 kg archers, derived (was the tuned 0.9)")
	var cav: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6,
			LoadoutRegistry.ARMOR_SQUAMATA, LoadoutRegistry.MOUNT_WARHORSE)
	assert_almost_eq(cav["mass"], 6.5625, TOL,
		"75 kg rider + 450 kg warhorse, derived (was the tuned 2.5)")


func test_profile_zero_ids_keep_the_legacy_armour_fallback() -> void:
	# A bare profile_for(flags, training) call — and any unknown armor id — keeps
	# the hard-coded armour row value, so old call sites and stray ids can't shift
	# combat. Mass has no equivalent "legacy" fallback anymore (see the next test):
	# with no mount id, mass correctly falls back to just the soldier's own real
	# body mass, not an assumption that a mount is present.
	var bare: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6)
	assert_eq(bare["armour"], 0.40, "no armor id -> the legacy cavalry armour")
	var unknown: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6, 999, 999)
	assert_eq(unknown["armour"], 0.40, "an unknown armor id keeps the legacy armour")


func test_profile_zero_mount_id_falls_back_to_the_body_alone() -> void:
	# With no mount id resolving (a bare call, or an unknown id), mass derives from
	# body_mass_kg alone — "no mount" now genuinely means "just this soldier's own
	# body", not the old hard-coded literal that implicitly assumed a mount was
	# present. This is a deliberate, judged consequence of deriving mass from real
	# kilograms end to end rather than keeping a second, separately-tuned fallback.
	var bare: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6)
	assert_almost_eq(bare["mass"], 75.0 / 80.0, TOL,
		"no mount id -> just the rider's own 75 kg body, no horse")
	var unknown: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6, 999, 999)
	assert_almost_eq(unknown["mass"], 75.0 / 80.0, TOL,
		"an unknown mount id -> just the rider's own body, no horse")


func test_profile_typed_panoply_can_diverge_from_the_type_default() -> void:
	# The point of the typed loadout: a unit can wear a DIFFERENT panoply than its
	# type's default, and the profile follows the worn type, not the flags.
	var mailed_archer: Dictionary = SoldierCombat.profile_for(false, false, true, 0.3,
			LoadoutRegistry.ARMOR_HAMATA, LoadoutRegistry.MOUNT_NONE)
	assert_eq(mailed_archer["armour"], 0.45, "an archer in mail protects like mail")
	var mounted_infantry: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5,
			LoadoutRegistry.ARMOR_HAMATA, LoadoutRegistry.MOUNT_WARHORSE)
	assert_almost_eq(mounted_infantry["mass"], 6.625, TOL,
		"a mounted foot profile carries the horse's real mass: 80 kg body + 450 kg warhorse")


func test_profile_reports_real_body_mass_in_kilograms() -> void:
	# body_mass_kg is the ABSOLUTE real mass the HUD reports — a separate datum
	# from the tuned relative "mass" contact scalar, which stays sim-internal.
	assert_eq(SoldierCombat.profile_for(false, false, false, 0.5)["body_mass_kg"], 80.0,
		"heavy infantry: 80 kg of man")
	assert_eq(SoldierCombat.profile_for(false, true, false, 0.75)["body_mass_kg"], 80.0,
		"spearmen match the heavy-foot body mass")
	assert_eq(SoldierCombat.profile_for(false, false, true, 0.3)["body_mass_kg"], 70.0,
		"archers are lighter men, matching their lighter relative scalar")
	assert_eq(SoldierCombat.profile_for(true, false, false, 0.6)["body_mass_kg"], 75.0,
		"a cavalry rider's own body, without the horse")


func test_instance_profile_reads_own_flags() -> void:
	var u: Unit = Unit.new()
	add_child_autofree(u)            # _ready() sets soldiers + joins groups
	u.anti_cavalry = true
	u.training = 0.75
	var p: Dictionary = u.combat_profile()
	assert_almost_eq(p["skill"], 0.75, TOL)
	assert_almost_eq(p["shield_residual"], 0.05, TOL, "anti-cavalry reads the spearman profile")


# --- Charge factor c (docs/combat-model.md "Closing velocity") ----------------

func test_charge_factor_zero_when_not_closing() -> void:
	assert_almost_eq(SoldierCombat.charge_factor(0.0), 0.0, TOL)
	assert_almost_eq(SoldierCombat.charge_factor(-50.0), 0.0, TOL,
		"a receding soldier deals no charge")


func test_charge_factor_is_one_at_reference_speed() -> void:
	assert_almost_eq(SoldierCombat.charge_factor(SoldierCombat.CHARGE_REFERENCE_SPEED), 1.0, TOL)


func test_charge_factor_is_monotonic() -> void:
	assert_gt(SoldierCombat.charge_factor(120.0), SoldierCombat.charge_factor(60.0),
		"a faster close gives a bigger charge")


# --- Facing gate phi (docs/combat-model.md "The land contest") ----------------

func test_facing_gate_full_to_the_front() -> void:
	# Defender faces +Y; the blow comes from +Y (dead ahead): fully met.
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.DOWN, Vector2.DOWN), 1.0, TOL)


func test_facing_gate_zero_to_the_back() -> void:
	# Defender faces +Y; the blow comes from behind (-Y): no active defence.
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.DOWN, Vector2.UP), 0.0, TOL)


func test_facing_gate_zero_to_the_flank() -> void:
	# A perpendicular blow gives a dot of 0, clamped to 0 (no negative gate).
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.DOWN, Vector2.RIGHT), 0.0, TOL)


func test_facing_gate_partial_off_axis() -> void:
	var phi: float = SoldierCombat.facing_gate(Vector2.DOWN, (Vector2.DOWN + Vector2.RIGHT))
	assert_almost_eq(phi, sqrt(0.5), TOL, "a 45-degree blow is partly met")


func test_facing_gate_degenerate_is_fully_met() -> void:
	# An undefined facing is treated as fully met, never a free back-strike.
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.ZERO, Vector2.DOWN), 1.0, TOL)


# --- Land contest p_land (docs/combat-model.md "The land contest") ------------

func test_land_even_match_front_is_a_coin_flip() -> void:
	# Equal skill, facing the blow, no charge: A = D, so L(0) = 0.5.
	assert_almost_eq(SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0), 0.5, TOL)


func test_land_skill_gap_raises_the_chance() -> void:
	var even: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0)
	var veteran: float = SoldierCombat.land_chance(0.9, 0.3, 0.0, 1.0, 0.0)
	assert_gt(veteran, even, "a more skilled attacker lands more often")


func test_land_back_strike_ignores_skill_and_shield() -> void:
	# phi = 0 zeroes the defender's active defence, so a shielded, skilled
	# defender struck from behind is as exposed as a helpless one.
	var front: float = SoldierCombat.land_chance(0.5, 0.8, 0.65, 1.0, 0.0)
	var back: float = SoldierCombat.land_chance(0.5, 0.8, 0.65, 0.0, 0.0)
	assert_gt(back, front, "a blow to the back lands far more often")
	# With phi = 0 the defence term vanishes entirely: only the attacker's offence
	# remains, so the shield and the defender's skill make no difference.
	var back_no_shield: float = SoldierCombat.land_chance(0.5, 0.2, 0.0, 0.0, 0.0)
	assert_almost_eq(back, back_no_shield, TOL,
		"from behind, the defender's shield and skill do not matter")


func test_land_shield_lowers_the_chance() -> void:
	var no_shield: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0)
	var shielded: float = SoldierCombat.land_chance(0.5, 0.5, 0.8, 1.0, 0.0)
	assert_lt(shielded, no_shield, "a shield turns more blows")


func test_land_shield_effectiveness_scales_with_defender_skill() -> void:
	# A skilled defender gains a larger active defense boost from a shield than a less skilled one.
	var high_skill_no_shield: float = SoldierCombat.land_chance(0.5, 0.8, 0.0, 1.0, 0.0)
	var high_skill_shielded: float = SoldierCombat.land_chance(0.5, 0.8, 0.5, 1.0, 0.0)
	var high_skill_diff: float = high_skill_no_shield - high_skill_shielded

	var low_skill_no_shield: float = SoldierCombat.land_chance(0.5, 0.2, 0.0, 1.0, 0.0)
	var low_skill_shielded: float = SoldierCombat.land_chance(0.5, 0.2, 0.5, 1.0, 0.0)
	var low_skill_diff: float = low_skill_no_shield - low_skill_shielded

	assert_gt(high_skill_diff, low_skill_diff, "more skilled defender derives greater active defense benefit from a shield")
	# Zero-skill defender gets zero active shield block benefit.
	var zero_skill_no_shield: float = SoldierCombat.land_chance(0.5, 0.0, 0.0, 1.0, 0.0)
	var zero_skill_shielded: float = SoldierCombat.land_chance(0.5, 0.0, 0.5, 1.0, 0.0)
	assert_almost_eq(zero_skill_no_shield, zero_skill_shielded, 1e-5, "untrained defender gets zero active shield block")


func test_land_charge_raises_the_chance() -> void:
	var standing: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0)
	var charging: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 1.0)
	assert_gt(charging, standing, "closing fast makes the blow harder to evade")


func test_land_is_clipped_to_the_bounds() -> void:
	# A hopeless mismatch still never reaches 0 or 1.
	var floor_case: float = SoldierCombat.land_chance(0.0, 1.0, 1.0, 1.0, 0.0)
	var ceil_case: float = SoldierCombat.land_chance(1.0, 0.0, 0.0, 0.0, 1.0)
	assert_almost_eq(floor_case, SoldierCombat.LAND_MIN, TOL, "never impossible")
	assert_almost_eq(ceil_case, SoldierCombat.LAND_MAX, TOL, "never automatic")


func test_land_condition_factors_shift_the_odds() -> void:
	var fresh_vs_fresh: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0, 1.0, 1.0)
	var fresh_vs_spent: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0, 1.0, 0.4)
	assert_gt(fresh_vs_spent, fresh_vs_fresh,
		"a wounded or winded defender (low cond_d) is easier to land on")


# --- Wound delta_h (docs/combat-model.md "Wound") -----------------------------

func test_wound_baseline_is_the_damage_scale() -> void:
	# lethality 1, no charge, no armour, full condition: exactly D0.
	assert_almost_eq(SoldierCombat.wound(1.0, 0.0, 0.0), SoldierCombat.DAMAGE_SCALE, TOL)


func test_wound_armour_reduces_it() -> void:
	var bare: float = SoldierCombat.wound(1.0, 0.0, 0.0)
	var armoured: float = SoldierCombat.wound(1.0, 0.0, 0.45)
	assert_almost_eq(armoured, SoldierCombat.DAMAGE_SCALE * 0.55, TOL)
	assert_lt(armoured, bare, "armour blunts the wound")


func test_wound_full_armour_stops_it() -> void:
	assert_almost_eq(SoldierCombat.wound(1.0, 0.0, 1.0), 0.0, TOL)


func test_wound_charge_amplifies_it() -> void:
	var standing: float = SoldierCombat.wound(1.0, 0.0, 0.0)
	var charging: float = SoldierCombat.wound(1.0, 1.0, 0.0)
	assert_almost_eq(charging, standing * 2.0, TOL, "a charge at c=1 doubles the wound")


func test_wound_scales_with_lethality_and_condition() -> void:
	assert_almost_eq(SoldierCombat.wound(0.5, 0.0, 0.0), SoldierCombat.DAMAGE_SCALE * 0.5, TOL)
	assert_almost_eq(SoldierCombat.wound(1.0, 0.0, 0.0, 0.5), SoldierCombat.DAMAGE_SCALE * 0.5, TOL,
		"a wounded attacker (low cond_a) hits softer")


func test_wound_is_never_negative() -> void:
	# Out-of-range inputs are clamped, never producing a healing "wound".
	assert_almost_eq(SoldierCombat.wound(1.0, -5.0, 1.5), 0.0, TOL)


func test_wound_piercing_partially_bypasses_armour() -> void:
	# Against 40% armour:
	# Non-piercing: effective armour 0.40 -> wound = DAMAGE_SCALE * 0.60
	# Piercing: effective armour 0.40 * (1 - 0.25) = 0.30 -> wound = DAMAGE_SCALE * 0.70
	var non_piercing: float = SoldierCombat.wound(1.0, 0.0, 0.40, 1.0, false)
	var piercing: float = SoldierCombat.wound(1.0, 0.0, 0.40, 1.0, true)
	assert_almost_eq(non_piercing, SoldierCombat.DAMAGE_SCALE * 0.60, TOL)
	assert_almost_eq(piercing, SoldierCombat.DAMAGE_SCALE * 0.70, TOL)
	assert_gt(piercing, non_piercing, "piercing hits deal more damage against armoured targets")


func test_wound_piercing_unarmoured_matches_non_piercing() -> void:
	# Unarmoured target (armour 0.0): both deal full baseline wound
	var non_piercing: float = SoldierCombat.wound(1.0, 0.0, 0.0, 1.0, false)
	var piercing: float = SoldierCombat.wound(1.0, 0.0, 0.0, 1.0, true)
	assert_almost_eq(non_piercing, SoldierCombat.DAMAGE_SCALE, TOL)
	assert_almost_eq(piercing, SoldierCombat.DAMAGE_SCALE, TOL)


# --- Determinism: the math is a pure function of its inputs -------------------

func test_math_is_deterministic() -> void:
	# Same inputs, same outputs, every call — no RNG, no state.
	var a: float = SoldierCombat.land_chance(0.7, 0.4, 0.3, 0.8, 0.5)
	var b: float = SoldierCombat.land_chance(0.7, 0.4, 0.3, 0.8, 0.5)
	assert_eq(a, b, "land chance is a pure function")
	var w1: float = SoldierCombat.wound(0.85, 0.7, 0.35)
	var w2: float = SoldierCombat.wound(0.85, 0.7, 0.35)
	assert_eq(w1, w2, "wound is a pure function")


# --- mass + knockback impulse -----------------------------------

func test_profiles_carry_per_type_mass() -> void:
	# Bare calls (no mount id) resolve mass from body_mass_kg alone — a cavalry
	# RIDER's own body (75 kg) is actually lighter than the 80 kg baseline; the
	# unit only reads as "heavy" once its real mount is composed in (see
	# test_profile_typed_panoply_mass_is_derived_from_real_kilograms above).
	assert_almost_eq(SoldierCombat.profile_for(true, false, false, 0.5)["mass"], 75.0 / 80.0, 1e-6,
		"a bare cavalry profile is just the rider's own body, no mount")
	assert_almost_eq(SoldierCombat.profile_for(false, true, false, 0.5)["mass"], 1.0, 1e-6, "spearmen baseline mass")
	assert_almost_eq(SoldierCombat.profile_for(false, false, false, 0.5)["mass"], 1.0, 1e-6, "infantry baseline mass")
	assert_almost_eq(SoldierCombat.profile_for(false, false, true, 0.5)["mass"], 0.875, 1e-6, "archers are light")


# --- effective mass (bracing) --------------------------------------------------

func test_effective_mass_no_brace_is_bare_mass() -> void:
	assert_almost_eq(SoldierCombat.effective_mass(2.0, 0.0), 2.0, TOL)


func test_effective_mass_full_brace_raises_it_by_the_multiplier() -> void:
	var expected: float = 2.0 * (1.0 + SoldierCombat.FRICTION_BRACING_MULTIPLIER)
	assert_almost_eq(SoldierCombat.effective_mass(2.0, 1.0), expected, TOL,
		"full bracing raises effective mass by FRICTION_BRACING_MULTIPLIER")


func test_effective_mass_never_negative() -> void:
	assert_almost_eq(SoldierCombat.effective_mass(-5.0, -1.0), 0.0, TOL,
		"out-of-range inputs clamp, never a negative mass")


# --- is_hard_collision (real-closing-speed gate for collision damage) ---------

func test_is_hard_collision_false_below_the_default_threshold() -> void:
	assert_false(SoldierCombat.is_hard_collision(SoldierCombat.COLLISION_DAMAGE_MIN_SPEED * 0.5))


func test_is_hard_collision_true_at_and_above_the_default_threshold() -> void:
	assert_true(SoldierCombat.is_hard_collision(SoldierCombat.COLLISION_DAMAGE_MIN_SPEED))
	assert_true(SoldierCombat.is_hard_collision(SoldierCombat.COLLISION_DAMAGE_MIN_SPEED * 2.0))


func test_is_hard_collision_threads_a_caller_supplied_threshold() -> void:
	# A caller-overridden min_speed changes the verdict at a speed where the default wouldn't --
	# the CLAUDE.md caller-configurable-parameters shape, matching capped_knockback_velocity's
	# own speed_cap parameter.
	assert_false(SoldierCombat.is_hard_collision(40.0, 50.0))
	assert_true(SoldierCombat.is_hard_collision(40.0, 30.0))


# --- collision damage (a hard, fast contact converts a real velocity change into damage) -

func test_collision_damage_scales_with_the_square_of_the_velocity_change() -> void:
	var single: float = SoldierCombat.collision_damage(Vector2(10.0, 0.0))
	var doubled: float = SoldierCombat.collision_damage(Vector2(20.0, 0.0))
	assert_almost_eq(doubled, single * 4.0, TOL, "damage scales with the square of the velocity change")


func test_collision_damage_matches_the_scale_formula() -> void:
	var delta_v := Vector2(30.0, 40.0)   # length 50
	var expected: float = SoldierCombat.COLLISION_DAMAGE_SCALE * 50.0 * 50.0
	assert_almost_eq(SoldierCombat.collision_damage(delta_v), expected, TOL)


func test_collision_damage_is_direction_independent() -> void:
	# Only the MAGNITUDE of the velocity change matters, not which way it points.
	var a: float = SoldierCombat.collision_damage(Vector2(50.0, 0.0))
	var b: float = SoldierCombat.collision_damage(Vector2(0.0, -50.0))
	assert_almost_eq(a, b, TOL)


func test_collision_damage_zero_delta_is_zero() -> void:
	assert_almost_eq(SoldierCombat.collision_damage(Vector2.ZERO), 0.0, TOL)


func test_collision_damage_threads_a_caller_supplied_scale() -> void:
	var default_scale: float = SoldierCombat.collision_damage(Vector2(10.0, 0.0))
	var doubled_scale: float = SoldierCombat.collision_damage(Vector2(10.0, 0.0), SoldierCombat.COLLISION_DAMAGE_SCALE * 2.0)
	assert_almost_eq(doubled_scale, default_scale * 2.0, TOL,
		"a caller-overridden scale changes the result -- CLAUDE.md caller-configurable-parameters shape")


func test_collision_damage_never_negative() -> void:
	# A negative scale is the only way this could go negative; guarded at the source.
	assert_almost_eq(SoldierCombat.collision_damage(Vector2(10.0, 0.0), -1.0), 0.0, TOL)


func test_collision_damage_composed_with_enemy_contact_impulse_favors_the_heavier_side() -> void:
	# Regression: an earlier version of collision_damage split a shared total by
	# jn^2/mass_i_eff, which could make a BRACED/heavier defender take MORE absolute damage
	# than an unbraced one against a much heavier attacker -- inverting what bracing is supposed
	# to do. Deriving damage from each side's own ACTUAL velocity change (this function's
	# design) fixes that automatically: a heavier/braced body always receives a SMALLER
	# velocity change from the same contact (SoldierCollision.enemy_contact_impulse's own
	# effective-mass split), so it always takes less damage too -- composing the two functions
	# directly (mirroring how SoldierEnemyContact.accumulate actually uses them) proves this
	# holds for a realistic heavy-attacker-vs-light-defender pairing.
	var closing_speed: float = SoldierCombat.COLLISION_DAMAGE_MIN_SPEED * 2.0
	var vel_a := Vector2(closing_speed, 0.0)   # heavy attacker closing on b
	var vel_b := Vector2.ZERO                  # stationary defender
	var heavy_mass: float = 6.5                # a mounted cavalry-scale effective mass
	var light_mass: float = 1.0                # an unbraced infantry-scale effective mass
	var impulses: Array = SoldierCollision.enemy_contact_impulse(
		vel_a, vel_b, heavy_mass, 0.0, light_mass, 0.0, Vector2(-1.0, 0.0), 0.0)
	var damage_heavy: float = SoldierCombat.collision_damage(impulses[0])
	var damage_light: float = SoldierCombat.collision_damage(impulses[1])
	assert_lt(damage_heavy, damage_light,
		"the heavier side takes less damage than the lighter side it struck")

	# Now brace the light side (raise its effective mass via brace_b) and confirm its OWN
	# damage drops relative to unbraced -- the property the earlier formula got backwards.
	var braced_impulses: Array = SoldierCollision.enemy_contact_impulse(
		vel_a, vel_b, heavy_mass, 0.0, light_mass, 1.0, Vector2(-1.0, 0.0), 0.0)
	var damage_light_braced: float = SoldierCombat.collision_damage(braced_impulses[1])
	assert_lt(damage_light_braced, damage_light,
		"bracing reduces the defender's own absolute damage, not just its share of the total")


func test_knockback_impulse_baseline() -> void:
	# lethality 1, no charge, mass 1, landed -> the base scale.
	assert_almost_eq(SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0),
			SoldierCombat.KNOCKBACK_IMPULSE_SCALE, 1e-6, "baseline landed impulse is J0")


func test_knockback_impulse_is_inverse_in_mass() -> void:
	var light: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0)
	var heavy: float = SoldierCombat.knockback_impulse(1.0, 0.0, 2.0, 1.0)
	assert_almost_eq(heavy, light * 0.5, 1e-5, "doubling the defender's mass halves the knockback")


func test_knockback_impulse_scales_with_charge_and_lethality() -> void:
	var base: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0)
	assert_almost_eq(SoldierCombat.knockback_impulse(1.0, 1.0, 1.0, 1.0), base * 2.0, 1e-5,
			"a full charge (c=1) doubles the impulse via (1+c)")
	assert_almost_eq(SoldierCombat.knockback_impulse(2.0, 0.0, 1.0, 1.0), base * 2.0, 1e-5,
			"twice the lethality, twice the impulse")


func test_defended_impulse_is_a_fraction_of_a_landed_one() -> void:
	var landed: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0)
	var defended: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, SoldierCombat.ETA_DEFENDED)
	assert_almost_eq(defended, landed * SoldierCombat.ETA_DEFENDED, 1e-5, "a turned-aside blow still shoves, less")
	assert_lt(defended, landed, "but less than a clean landing")


func test_knockback_impulse_never_negative() -> void:
	assert_eq(SoldierCombat.knockback_impulse(-1.0, 0.0, 1.0, 1.0), 0.0, "negative lethality clamps to no impulse")
	assert_gt(SoldierCombat.knockback_impulse(1.0, 0.0, 0.0, 1.0), 0.0, "zero mass is floored, not a divide-by-zero")


func test_knockback_impulse_piercing_is_reduced() -> void:
	var standard: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0, 1.0, false)
	var piercing: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0, 1.0, true)
	assert_almost_eq(piercing, standard * SoldierCombat.PIERCING_IMPULSE_MULT, 1e-6,
			"piercing strikes impart reduced knockback impulse")
	assert_lt(piercing, standard, "piercing strikes shove less than non-piercing blows")


# --- capped knockback velocity (add-then-clamp per strike) --------------------------------

func test_capped_knockback_single_blow_below_ceiling_passes_through() -> void:
	# One baseline landed blow (J0 = 40) on a body at rest stays under the ceiling untouched.
	var v: Vector2 = SoldierCombat.capped_knockback_velocity(
			Vector2.ZERO, Vector2(SoldierCombat.KNOCKBACK_IMPULSE_SCALE, 0.0))
	assert_almost_eq(v.x, SoldierCombat.KNOCKBACK_IMPULSE_SCALE, 1e-5, "the full impulse is kept")
	assert_almost_eq(v.y, 0.0, 1e-5, "nothing bleeds into the other axis")


func test_capped_knockback_stacked_blows_clamp_to_the_ceiling() -> void:
	# Five landed baseline blows in one cadence sum to 200 -- the launch case. Applied
	# strike by strike (as the resolver does), the accumulated speed clamps at the ceiling.
	var v: Vector2 = Vector2.ZERO
	for _k in range(5):
		v = SoldierCombat.capped_knockback_velocity(
				v, Vector2(0.0, SoldierCombat.KNOCKBACK_IMPULSE_SCALE))
	assert_almost_eq(v.y, SoldierCombat.KNOCKBACK_SPEED_MAX, 1e-4,
			"the stack clamps to KNOCKBACK_SPEED_MAX, not 5x J0")
	assert_almost_eq(v.x, 0.0, 1e-5, "direction is preserved")


func test_capped_knockback_never_raises_a_faster_body_further() -> void:
	# A body already legitimately faster than the ceiling (a galloping horse) is not
	# accelerated past its own speed by a blow -- the cap is max(own speed, ceiling).
	var gallop := Vector2(170.0, 0.0)
	var v: Vector2 = SoldierCombat.capped_knockback_velocity(gallop, Vector2(40.0, 0.0))
	assert_almost_eq(v.x, 170.0, 1e-4, "the blow cannot ratchet the body past its own speed")
	assert_almost_eq(v.y, 0.0, 1e-5, "no cross-axis drift")


func test_capped_knockback_sideways_blow_on_a_fast_body_turns_it_without_speeding_it() -> void:
	# A blow across a fast body's path redirects it; the resulting SPEED still never
	# exceeds what it already carried.
	var gallop := Vector2(170.0, 0.0)
	var v: Vector2 = SoldierCombat.capped_knockback_velocity(gallop, Vector2(0.0, 60.0))
	assert_almost_eq(v.length(), 170.0, 1e-3, "speed is capped at the carried speed")
	assert_gt(v.y, 0.0, "but the shove still deflects the path")


func test_capped_knockback_zero_impulse_is_identity_below_ceiling() -> void:
	var before := Vector2(10.0, -5.0)
	var v: Vector2 = SoldierCombat.capped_knockback_velocity(before, Vector2.ZERO)
	assert_almost_eq(v.x, before.x, 1e-6, "no impulse, no x change")
	assert_almost_eq(v.y, before.y, 1e-6, "no impulse, no y change")


# --- prone / knockdown ------------------------------------------

func test_prone_chance_zero_below_threshold() -> void:
	assert_eq(SoldierCombat.prone_chance(10.0, 1.0), 0.0, "a small shove never fells a man")
	assert_eq(SoldierCombat.prone_chance(0.0, 1.0), 0.0, "no impulse, no fall")


func test_prone_chance_climbs_with_surplus_impulse() -> void:
	var small: float = SoldierCombat.prone_chance(70.0, 1.0)
	var big: float = SoldierCombat.prone_chance(110.0, 1.0)
	assert_gt(small, 0.0, "above the threshold the chance is positive")
	assert_gt(big, small, "a bigger impulse fells more often")


func test_prone_chance_is_capped() -> void:
	assert_almost_eq(SoldierCombat.prone_chance(99999.0, 1.0), SoldierCombat.PRONE_CHANCE_MAX, 1e-6,
			"no single blow is a certain knockdown")


func test_heavier_and_braced_defenders_resist_going_prone() -> void:
	var light: float = SoldierCombat.prone_chance(120.0, 1.0)
	var heavy: float = SoldierCombat.prone_chance(120.0, 2.5)
	assert_lt(heavy, light, "a heavy (cavalry) body is far harder to fell")
	var unbraced: float = SoldierCombat.prone_chance(120.0, 1.0, 0.0)
	var braced: float = SoldierCombat.prone_chance(120.0, 1.0, 1.0)
	assert_lt(braced, unbraced, "bracing raises the knockdown threshold")


func test_moving_defender_is_easier_to_fell() -> void:
	var stationary: float = SoldierCombat.prone_chance(50.0, 1.0, 0.0, false)
	var moving: float = SoldierCombat.prone_chance(50.0, 1.0, 0.0, true)
	assert_gt(moving, stationary, "a moving defender is easier to topple than a settled stance")


# --- torque vs translation impulse partition (docs/combat-model.md) ------------

func test_anchor_capacity_stationary_vs_moving() -> void:
	var base: float = SoldierCombat.anchor_capacity(1.0, 0.0, false)
	assert_almost_eq(base, SoldierCombat.STATIC_FRICTION_THRESHOLD, 1e-6, "stationary unbraced is baseline")
	var moving: float = SoldierCombat.anchor_capacity(1.0, 0.0, true)
	assert_almost_eq(moving, SoldierCombat.STATIC_FRICTION_THRESHOLD * SoldierCombat.KINETIC_ANCHOR_RATIO, 1e-6,
		"moving anchor capacity is attenuated by kappa")


func test_anchor_capacity_bracing_scales_effective_mass() -> void:
	var unbraced: float = SoldierCombat.anchor_capacity(1.0, 0.0, false)
	var braced: float = SoldierCombat.anchor_capacity(1.0, 1.0, false)
	var expected: float = SoldierCombat.STATIC_FRICTION_THRESHOLD * (1.0 + SoldierCombat.FRICTION_BRACING_MULTIPLIER * 1.0)
	assert_almost_eq(braced, expected, 1e-6, "bracing scales anchor capacity with effective mass")
	assert_gt(braced, unbraced, "braced footing holds more shear before slipping")


func test_partition_impulse_below_anchor_is_pure_torque() -> void:
	var parts: Array[float] = SoldierCombat.partition_impulse(15.0, 1.0, 0.0, false)
	assert_almost_eq(parts[0], 15.0, 1e-6, "rotational torque takes entire sub-anchor impulse")
	assert_almost_eq(parts[1], 0.0, 1e-6, "translational knockback is zero below anchor capacity")


func test_partition_impulse_above_anchor_splits_into_translation() -> void:
	var parts: Array[float] = SoldierCombat.partition_impulse(35.0, 1.0, 0.0, false)
	assert_almost_eq(parts[0], 20.0, 1e-6, "rotational share caps at anchor capacity")
	assert_almost_eq(parts[1], 15.0, 1e-6, "surplus impulse goes into translational slide")


func test_translational_impulse_matches_partition_surplus() -> void:
	var below: float = SoldierCombat.translational_impulse(15.0, 1.0, 0.0, false)
	assert_almost_eq(below, 0.0, 1e-6, "sub-anchor translational impulse is zero")
	var above: float = SoldierCombat.translational_impulse(35.0, 1.0, 0.0, false)
	assert_almost_eq(above, 15.0, 1e-6, "super-anchor translational impulse is surplus")
	var moving: float = SoldierCombat.translational_impulse(20.0, 1.0, 0.0, true)
	assert_almost_eq(moving, 4.0, 1e-6, "moving defender has lower anchor capacity so higher translational surplus")


# --- bracing depth and capacity (docs/combat-model.md "Bracing") ---------------

func test_brace_depth_lone_man_is_one() -> void:
	var lone: PackedFloat32Array = PackedFloat32Array([1.0])
	assert_almost_eq(SoldierCombat.brace_depth(lone), 1.0, TOL, "a lone fully-set man contributes depth 1")


func test_brace_depth_accumulates_with_zeta_attenuation() -> void:
	var two: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
	assert_almost_eq(SoldierCombat.brace_depth(two), 1.0 + SoldierCombat.ZETA, TOL, "2-deep: 1 + ζ")
	var three: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
	var expected: float = 1.0 + SoldierCombat.ZETA + SoldierCombat.ZETA * SoldierCombat.ZETA
	assert_almost_eq(SoldierCombat.brace_depth(three), expected, TOL, "3-deep: 1 + ζ + ζ²")


func test_brace_depth_empty_file_is_zero() -> void:
	assert_almost_eq(SoldierCombat.brace_depth(PackedFloat32Array()), 0.0, TOL, "no file, no depth")


func test_brace_capacity_lone_set_man_is_j_cap() -> void:
	var lone: PackedFloat32Array = PackedFloat32Array([1.0])
	assert_almost_eq(SoldierCombat.brace_capacity(lone), SoldierCombat.BRACE_CAPACITY, TOL,
		"a lone set man absorbs exactly J_cap")


func test_brace_capacity_deep_file_exceeds_lone() -> void:
	var lone: PackedFloat32Array = PackedFloat32Array([1.0])
	var three: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
	assert_gt(SoldierCombat.brace_capacity(three), SoldierCombat.brace_capacity(lone),
		"a 3-deep file absorbs more than a lone man")


# --- weapon-differentiated brace capacity (docs/combat-model.md "Bracing") -----------

func test_brace_capacity_for_type_anti_cav_exceeds_infantry_baseline() -> void:
	# A grounded, angled spear/pike shaft is an independent leveraged strut into the
	# earth, so it resists more than a shield-only soldier's friction/mass-stacking alone.
	var anti_cav: float = SoldierCombat.brace_capacity_for_type(false, true, false)
	var infantry: float = SoldierCombat.brace_capacity_for_type(false, false, false)
	assert_gt(anti_cav, infantry, "a grounded spear/pike braces harder than a shield-only soldier")
	assert_almost_eq(infantry, SoldierCombat.BRACE_CAPACITY, TOL,
		"the plain-infantry case matches the flat baseline every prior caller used")


func test_brace_capacity_for_type_matches_named_constants() -> void:
	assert_almost_eq(SoldierCombat.brace_capacity_for_type(false, true, false),
		SoldierCombat.BRACE_CAPACITY_ANTI_CAV, TOL)
	assert_almost_eq(SoldierCombat.brace_capacity_for_type(false, false, true),
		SoldierCombat.BRACE_CAPACITY_RANGED, TOL)
	assert_almost_eq(SoldierCombat.brace_capacity_for_type(true, false, false),
		SoldierCombat.BRACE_CAPACITY_CAVALRY, TOL)


func test_brace_capacity_for_type_cavalry_takes_priority_over_anti_cav() -> void:
	# A mounted anti-cavalry flag combination shouldn't occur in practice, but the
	# dispatch order should still be well-defined: cavalry is checked first, matching
	# profile_for's own branch order.
	assert_almost_eq(SoldierCombat.brace_capacity_for_type(true, true, false),
		SoldierCombat.BRACE_CAPACITY_CAVALRY, TOL)


func test_brace_capacity_threads_a_type_specific_j_cap() -> void:
	var lone: PackedFloat32Array = PackedFloat32Array([1.0])
	var anti_cav_cap: float = SoldierCombat.brace_capacity(lone, SoldierCombat.BRACE_CAPACITY_ANTI_CAV)
	assert_almost_eq(anti_cav_cap, SoldierCombat.BRACE_CAPACITY_ANTI_CAV, TOL,
		"a lone set man's capacity is exactly the passed-in j_cap")


# --- stamina factor g(sigma) (docs/combat-model.md "Stamina") ------------------

func test_stamina_factor_full_stamina_is_one() -> void:
	var max: float = 100.0
	assert_almost_eq(SoldierCombat.stamina_factor(max, max), 1.0, TOL)


func test_stamina_factor_zero_stamina_is_the_floor() -> void:
	assert_almost_eq(SoldierCombat.stamina_factor(0.0, 100.0),
		SoldierCombat.COND_STAMINA_FLOOR, TOL)


func test_stamina_factor_is_monotone() -> void:
	var max: float = 100.0
	var low: float = SoldierCombat.stamina_factor(20.0, max)
	var mid: float = SoldierCombat.stamina_factor(50.0, max)
	assert_gt(mid, low, "more stamina -> higher factor")
	assert_gt(mid, SoldierCombat.COND_STAMINA_FLOOR, "mid is above the floor")
	assert_lt(mid, 1.0, "mid is below full")


func test_stamina_factor_guard_zero_max() -> void:
	# A zero max_stamina would divide by zero; the guard returns 1.0 instead.
	assert_almost_eq(SoldierCombat.stamina_factor(50.0, 0.0), 1.0, TOL)


func test_stamina_factor_combined_with_condition() -> void:
	# A soldier at half health AND zero stamina has a lower combined factor than either alone.
	var max_hp: float = 100.0
	var max_stam: float = 100.0
	var q_half: float = SoldierCombat.condition(max_hp * 0.5, max_hp)
	var g_zero: float = SoldierCombat.stamina_factor(0.0, max_stam)
	var combined: float = q_half * g_zero
	assert_lt(combined, q_half, "combined is below health-only factor")
	assert_lt(combined, g_zero, "combined is below stamina-only factor")
