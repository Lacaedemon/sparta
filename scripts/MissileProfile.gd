class_name MissileProfile
extends Resource
## A concrete missile-weapon TYPE (docs/longer-range-missile-design.md): the fixed ranged
## stats every soldier loosing this weapon shares. Shared and interned -- LoadoutRegistry
## holds one instance per type and Unit copies the fields out on equip_missile -- so a
## profile is never allocated per unit and never mutated after the registry builds it.
## Same shape as Weapon: metric lengths are authored in metres and converted ONCE here,
## at construction, so runtime state stays world units end to end (docs/units-convention.md).

const WorldScaleRef = preload("res://scripts/WorldScale.gd")

const AMMO_UNLIMITED: int = -1

@export var id: int
@export var display_name: String
# Maximum reach in metres -- the authored value, the one the stat tables speak in.
@export var range_m: float
# The same reach in WORLD UNITS, converted once when the registry builds this type.
# Unit.missile_range is set from this on equip, so the metre->wu conversion happens once
# per TYPE rather than once per volley.
@export var range_wu: float
# Seconds between volleys -- the regiment's aggregate cadence, not one man's draw.
@export var interval_s: float
# Scales the regiment volley damage against a melee strike of the same stats.
@export var damage_factor: float
# Fraction of nominal damage a volley delivers at range_wu. 1.0 means no falloff at all,
# which is what an unprofiled unit gets; the falloff is linear from 1.0 at point blank
# (see accuracy_at).
@export var accuracy_at_max: float
# Launch angle in radians above horizontal. With ProjectileField's gravity it decides the
# flight time to a given distance (ProjectilePhysics.solve_launch): a lob hangs in the
# air, a flat throw arrives sooner.
@export var launch_angle: float
# Ammunition count for this weapon type (docs/longer-range-missile-design.md, phase 3):
# AMMO_UNLIMITED (-1) means infinite supply (bows/slings); positive integers enforce a
# finite quiver or shaft bundle (e.g. 2 pila).
@export var ammo: int = AMMO_UNLIMITED


## Build one interned type instance. Registry construction only -- everything else reads
## shared instances through LoadoutRegistry.missile(id).
static func make(p_id: int, p_name: String, p_range_m: float, p_interval_s: float,
		p_damage_factor: float, p_accuracy_at_max: float, p_launch_angle: float,
		p_ammo: int = AMMO_UNLIMITED) -> MissileProfile:
	var m := MissileProfile.new()
	m.id = p_id
	m.display_name = p_name
	m.range_m = p_range_m
	m.range_wu = WorldScaleRef.m_to_wu(p_range_m)
	m.interval_s = p_interval_s
	m.damage_factor = p_damage_factor
	m.accuracy_at_max = p_accuracy_at_max
	m.launch_angle = p_launch_angle
	m.ammo = p_ammo
	return m


## Range-accuracy falloff: the fraction of nominal damage a volley delivers at `dist_wu`,
## falling linearly from 1.0 at point blank to `accuracy_at_max` at `range_wu` and holding
## there past it (a shot past maximum range is the caller's problem, not a negative factor).
## Pure and RNG-free, so a replay recomputes the same value. A non-positive range has no
## curve to walk and reads as point blank, and an `accuracy_at_max` of 1.0 returns exactly
## 1.0 at every distance -- `1.0 - 0.0 * f` -- which is what keeps an unprofiled unit's
## damage bit-identical to the pre-profile formula.
static func accuracy_at(dist_wu: float, range_wu: float, accuracy_at_max: float) -> float:
	if range_wu <= 0.0:
		return 1.0
	var f: float = clampf(dist_wu / range_wu, 0.0, 1.0)
	return 1.0 - (1.0 - accuracy_at_max) * f


## This profile's own falloff at `dist_wu` (the static curve at this type's range).
func accuracy(dist_wu: float) -> float:
	return accuracy_at(dist_wu, range_wu, accuracy_at_max)


## Seconds a volley from this profile spends in the air to a target `dist_wu` away under
## `gravity` (wu/s^2) -- ProjectilePhysics.solve_launch at this type's launch angle. 0 for
## a degenerate distance, same as the solver.
func flight_time(dist_wu: float, gravity: float) -> float:
	return ProjectilePhysics.solve_launch(dist_wu, gravity, launch_angle)["flight_time"]
