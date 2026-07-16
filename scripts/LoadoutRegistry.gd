class_name LoadoutRegistry
## The interned loadout TYPE registry (docs/soldier-loadout-design.md,
## phase 1): one shared, immutable Weapon/Shield/Armor/Mount instance per type
## in today's roster, keyed by int ids — the per-soldier arrays on Unit
## (_sim_soldier_weapon_id / _sim_soldier_shield_id) for weapons and shields,
## the per-unit Unit.armor_type_id / Unit.mount_type_id for armor and mounts
## (nothing varies per soldier for those yet, so they stay unit-level until a
## per-soldier need appears). Lookup is a dictionary read against data built
## once at class load — O(1), no allocation, no RNG — so it is replay-safe.
## Type objects are never mutated after load; per-soldier state that varies
## (equipped type, hold angle) belongs in per-soldier arrays on Unit, never on
## these shared instances.
##
## Id ranges are disjoint on purpose — weapons 1-99, shields 101-199, armor
## 201-299, mounts 301-399, 0 reserved invalid — so an id read against the
## wrong namespace (or a missed array fill, which PackedInt32Array defaults
## to 0) resolves to null instead of silently aliasing another type.

const WEAPON_SPEAR: int = 1
const WEAPON_GLADIUS: int = 2
const WEAPON_SIDEARM: int = 3
const WEAPON_SPATHA: int = 4

const SHIELD_SCUTUM: int = 101
const SHIELD_ROUND: int = 102
const SHIELD_NONE: int = 103

const ARMOR_HAMATA: int = 201
const ARMOR_LINOTHORAX: int = 202
const ARMOR_TUNIC: int = 203
const ARMOR_SQUAMATA: int = 204

const MOUNT_NONE: int = 301
const MOUNT_WARHORSE: int = 302

# Stat sources — the registry names what already exists, it invents nothing:
# reach_m carries the exact per-type values Battle._default_loadout() held as
# "reach_m" dictionary literals before the registry existed (the spear
# out-reaches the sword; the archers' melee sidearm is short — their bow is
# ranged fire, not a melee reach). lethality carries the per-type wounding
# powers SoldierCombat.profile_for() held before the strike-time reads moved
# here, mapping one-to-one onto the weapon each type carries. Reach still
# feeds Unit.attack_range at spawn; lethality is read at strike time through
# the attacker's per-soldier weapon id (Unit.soldier_lethality). Same numbers
# as the pre-registry literals, so combat outcomes are unchanged.
static var _weapons: Dictionary = {
	WEAPON_SPEAR: Weapon.make(WEAPON_SPEAR, "Spear", 2.4, 0.85),
	WEAPON_GLADIUS: Weapon.make(WEAPON_GLADIUS, "Gladius", 1.3, 1.0),
	WEAPON_SIDEARM: Weapon.make(WEAPON_SIDEARM, "Sidearm", 0.6, 0.5),
	WEAPON_SPATHA: Weapon.make(WEAPON_SPATHA, "Spatha", 1.5, 1.1),
}

# block_value: the shield's OWN contribution to the defensive shield weight.
# The land contest composes the full weight at strike time as the defender
# type's stance residual (profile_for's "shield_residual") plus this block
# value, through the struck soldier's shield id — so the scutum carries the
# plain infantry weight (0.60; the spearmen's pre-split 0.65 was the same
# shield plus 0.05 braced anti-cavalry footing, which stays in profile_for),
# and the round cavalry shield carries the cavalry weight (0.25). SHIELD_NONE
# is a real interned type (block 0, arc 0), not a null: archers carry it, and
# a uniform object keeps call sites free of "no shield" special cases (their
# 0.05 stance residual is unshielded deflection, not a shield). arc_deg is
# provisional shape data (nothing reads it for gameplay yet): the big body
# scutum covers a wide front, the round shield less.
static var _shields: Dictionary = {
	SHIELD_SCUTUM: Shield.make(SHIELD_SCUTUM, "Scutum", 0.6, 120.0),
	SHIELD_ROUND: Shield.make(SHIELD_ROUND, "Round shield", 0.25, 90.0),
	SHIELD_NONE: Shield.make(SHIELD_NONE, "Unshielded", 0.0, 0.0),
}

# protection carries the exact per-type armour scalars SoldierCombat.profile_for()'s
# rows held as hard-coded literals before the registry existed, mapping one-to-one
# onto the panoply each roster type wears: infantry mail (0.45), the spearmen's
# linothorax (0.35), the archers' padded tunic (0.10), and the cavalry's scale shirt
# (0.40). profile_for reads protection through the unit's armor id, so combat
# outcomes are unchanged for the default roster. weight_kg is provisional shape
# data (nothing reads it for gameplay yet — the loadout table's gait speeds encode
# panoply weight by hand); the values are plausible historical panoply weights, not
# tuned gameplay numbers.
static var _armors: Dictionary = {
	ARMOR_HAMATA: Armor.make(ARMOR_HAMATA, "Lorica hamata", 0.45, 11.0),
	ARMOR_LINOTHORAX: Armor.make(ARMOR_LINOTHORAX, "Linothorax", 0.35, 5.0),
	ARMOR_TUNIC: Armor.make(ARMOR_TUNIC, "Padded tunic", 0.10, 2.0),
	ARMOR_SQUAMATA: Armor.make(ARMOR_SQUAMATA, "Lorica squamata", 0.40, 13.0),
}

# mass_contribution: the horse's own share of a cavalryman's effective contact
# mass — profile_for composes body (1.0) + warhorse (1.5) to the exact 2.5 the
# cavalry row carried as a hard-coded literal before the registry existed, so
# contact physics are unchanged. MOUNT_NONE is a real interned type (zero mass,
# zero pace), not a null, so call sites stay free of "no mount" special cases —
# the same choice SHIELD_NONE made. top_speed_mps records the toned-down 8.5 m/s
# fast-canter the cavalry loadout already uses as its sprint (provisional shape
# data; movement still reads the loadout table, not this).
static var _mounts: Dictionary = {
	MOUNT_NONE: Mount.make(MOUNT_NONE, "On foot", 0.0, 0.0),
	MOUNT_WARHORSE: Mount.make(MOUNT_WARHORSE, "Warhorse", 1.5, 8.5),
}


## The shared Weapon instance for `type_id`, or null for an unknown id.
static func weapon(type_id: int) -> Weapon:
	return _weapons.get(type_id) as Weapon


## The shared Shield instance for `type_id`, or null for an unknown id.
static func shield(type_id: int) -> Shield:
	return _shields.get(type_id) as Shield


## The shared Armor instance for `type_id`, or null for an unknown id.
static func armor(type_id: int) -> Armor:
	return _armors.get(type_id) as Armor


## The shared Mount instance for `type_id`, or null for an unknown id.
static func mount(type_id: int) -> Mount:
	return _mounts.get(type_id) as Mount


## Every registered weapon id, for roster-wide iteration (tests, tools).
static func weapon_ids() -> PackedInt32Array:
	return PackedInt32Array(_weapons.keys())


## Every registered shield id, for roster-wide iteration (tests, tools).
static func shield_ids() -> PackedInt32Array:
	return PackedInt32Array(_shields.keys())


## Every registered armor id, for roster-wide iteration (tests, tools).
static func armor_ids() -> PackedInt32Array:
	return PackedInt32Array(_armors.keys())


## Every registered mount id, for roster-wide iteration (tests, tools).
static func mount_ids() -> PackedInt32Array:
	return PackedInt32Array(_mounts.keys())
