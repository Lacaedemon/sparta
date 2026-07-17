class_name Mount
extends Resource
## A concrete mount TYPE: the fixed stats every mounted soldier of this kind
## shares. Shared and interned — LoadoutRegistry holds one instance per type,
## referenced by id from Unit.mount_type_id — so a mount is never allocated
## per soldier and never mutated after the registry builds it, the same
## contract Weapon and Shield already keep. "On foot" is a real interned type
## (MOUNT_NONE: zero mass, zero pace), not a null, so call sites stay free of
## "no mount" special cases — the same choice SHIELD_NONE made.
## See docs/soldier-loadout-design.md.

@export var id: int
@export var display_name: String
# The mount's own contribution to the soldier's effective contact mass, in the
# sim's relative mass units (a foot soldier's body is ~1.0). profile_for
# composes the combatant's mass as body mass + this contribution — the horse
# is what makes a cavalryman hit like 2.5 foot soldiers, not a heavier rider.
# SIM-INTERNAL, a tuned gameplay scalar: never shown to the player (the HUD
# reports mass_kg below), and not yet derived from the real mass — deriving
# the contact scalars from the kg data is tracked follow-up work.
@export var mass_contribution: float
# The animal's real mass in kilograms — the absolute figure the HUD reports,
# per the units convention (a raw sim scalar never reaches the player).
# Provisional shape data for gameplay, like Shield.arc_deg: contact physics
# still reads the tuned mass_contribution above, not this.
@export var mass_kg: float
# The mount's own top pace in metres/second. Provisional shape data, like
# Shield.arc_deg: nothing reads it for gameplay yet — the loadout table's
# hand-authored cavalry gait speeds remain the source of truth for movement
# (see Battle._default_loadout's own comment on the toned-down gallop).
@export var top_speed_mps: float


## Build one interned type instance. Registry construction only — everything
## else reads shared instances through LoadoutRegistry.mount(id).
static func make(p_id: int, p_name: String, p_mass_contribution: float,
		p_mass_kg: float, p_top_speed_mps: float) -> Mount:
	var m := Mount.new()
	m.id = p_id
	m.display_name = p_name
	m.mass_contribution = p_mass_contribution
	m.mass_kg = p_mass_kg
	m.top_speed_mps = p_top_speed_mps
	return m
