class_name Shield
extends Resource
## A concrete shield TYPE: the fixed stats every soldier carrying this shield
## shares. Shared and interned — LoadoutRegistry holds one instance per type,
## referenced by id from the per-soldier `_sim_soldier_shield_id` arrays — so a
## shield is never allocated per soldier and never mutated after the registry
## builds it. Per-soldier hold STATE (the current hold angle: resting, bracing,
## raised) is a later phase's per-soldier array, never a field here — two
## soldiers carrying the same scutum must not fight over one shared angle.
## See docs/soldier-loadout-design.md.

@export var id: int
@export var display_name: String
# How much active defence the shield ITSELF contributes. The land contest's
# shield weight composes at strike time as the defender type's stance residual
# (SoldierCombat.profile_for's "shield_residual") plus this block value, then
# multiplies by SHIELD_DEFENSE_WEIGHT (see SoldierCombat.land_chance).
@export var block_value: float
# Coverage arc in degrees, centred on the hold angle. Shape data for a
# discrete arc-coverage check; today's combat uses the continuous facing gate
# (SoldierCombat.facing_gate), which doesn't read it.
@export var arc_deg: float
# Rest pose: the angle (radians, relative to the soldier's facing) the shield
# is held at by default. Feeds the render once visuals read the type.
@export var default_hold_angle: float


## Build one interned type instance. Registry construction only — everything
## else reads shared instances through LoadoutRegistry.shield(id).
static func make(p_id: int, p_name: String, p_block_value: float, p_arc_deg: float,
		p_hold_angle: float = 0.0) -> Shield:
	var s := Shield.new()
	s.id = p_id
	s.display_name = p_name
	s.block_value = p_block_value
	s.arc_deg = p_arc_deg
	s.default_hold_angle = p_hold_angle
	return s


## Whether an attack coming in at `attack_angle` falls inside the shield's
## coverage arc held at `hold_angle` (both radians, same frame). The angle
## difference wraps, so an attack across the -PI/PI seam still compares
## correctly. A zero-arc shield (SHIELD_NONE) covers nothing, which keeps
## "no shield" a uniform case instead of a null check at every call site.
## Pure; nothing reads it for gameplay yet.
func covers(attack_angle: float, hold_angle: float) -> bool:
	if arc_deg <= 0.0:
		return false
	return absf(wrapf(attack_angle - hold_angle, -PI, PI)) <= deg_to_rad(arc_deg) * 0.5
