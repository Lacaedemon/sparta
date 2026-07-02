class_name Weapon
extends Resource
## A concrete weapon TYPE: the fixed stats every soldier carrying this weapon
## shares. Shared and interned — LoadoutRegistry holds one instance per type,
## referenced by id from the per-soldier `_sim_soldier_weapon_id` arrays — so a
## weapon is never allocated per soldier and never mutated after the registry
## builds it. Anything that genuinely varies per soldier (which type is
## equipped, hold state) lives in per-soldier arrays on Unit, not here.
## See docs/soldier-loadout-design.md.

@export var id: int
@export var display_name: String
# Effective melee reach in metres. Battle converts it to world units at spawn
# (reach_m * WORLD_UNITS_PER_METER -> Unit.attack_range): a longer-reach weapon
# strikes while a shorter-weapon enemy is still closing the gap.
@export var reach_m: float
# Wounding power: the per-type lethality factor SoldierCombat.wound() scales by.
@export var lethality: float
# Rest pose: the angle (radians, relative to the soldier's facing) the weapon
# is held at when not striking. Feeds the render once visuals read the type.
@export var default_hold_angle: float


## Build one interned type instance. Registry construction only — everything
## else reads shared instances through LoadoutRegistry.weapon(id).
static func make(p_id: int, p_name: String, p_reach_m: float, p_lethality: float,
		p_hold_angle: float = 0.0) -> Weapon:
	var w := Weapon.new()
	w.id = p_id
	w.display_name = p_name
	w.reach_m = p_reach_m
	w.lethality = p_lethality
	w.default_hold_angle = p_hold_angle
	return w


## The weapon's reach in metres under a terrain speed multiplier — the same
## plain float the movement code reads from PathField.active.speed_at(), so
## cramped ground shortens an effective thrust the way it slows a march.
## Pure; nothing reads it for gameplay yet.
func effective_reach(terrain_speed_multiplier: float) -> float:
	return reach_m * terrain_speed_multiplier
