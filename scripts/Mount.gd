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
# The animal's real mass in kilograms — the absolute figure the HUD reports,
# per the units convention, AND the single source of truth for the mount's
# contribution to a soldier's contact mass: SoldierCombat.relative_mass_from_kg
# (mass_kg) is the mount's share of the sim's relative mass units (a foot
# soldier's body is ~1.0). The horse is what makes a cavalryman hit like
# several foot soldiers, not a heavier rider. There is no separate tuned
# "mass_contribution" scalar anymore — the relative contact figure is always
# derived from this real kilogram value, never hand-maintained alongside it.
@export var mass_kg: float
# The mount's own top pace in metres/second. Provisional shape data, like
# Shield.arc_deg: nothing reads it for gameplay yet — the loadout table's
# hand-authored cavalry gait speeds remain the source of truth for movement
# (see Battle._default_loadout's own comment on the toned-down gallop).
@export var top_speed_mps: float


## Build one interned type instance. Registry construction only — everything
## else reads shared instances through LoadoutRegistry.mount(id).
static func make(p_id: int, p_name: String, p_mass_kg: float, p_top_speed_mps: float) -> Mount:
	var m := Mount.new()
	m.id = p_id
	m.display_name = p_name
	m.mass_kg = p_mass_kg
	m.top_speed_mps = p_top_speed_mps
	return m
