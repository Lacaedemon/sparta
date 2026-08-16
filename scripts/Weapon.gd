class_name Weapon
extends Resource
## A concrete weapon TYPE: the fixed stats every soldier carrying this weapon
## shares. Shared and interned — LoadoutRegistry holds one instance per type,
## referenced by id from the per-soldier `_sim_soldier_weapon_id` arrays — so a
## weapon is never allocated per soldier and never mutated after the registry
## builds it. Anything that genuinely varies per soldier (which type is
## equipped, hold state) lives in per-soldier arrays on Unit, not here.
## See docs/soldier-loadout-design.md.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")

@export var id: int
@export var display_name: String
# Effective melee reach in metres — the authored value, kept as the metric one the
# stat tables and the HUD speak in. A longer-reach weapon strikes while a
# shorter-weapon enemy is still closing the gap.
@export var reach_m: float
# The same reach in WORLD UNITS, converted once when the registry builds this type.
# Unit.attack_range is set from this (at spawn, and again on a phase-4 weapon switch),
# so the metre->world conversion happens once per TYPE rather than once per equip:
# runtime state stays world units end to end, per docs/units-convention.md.
@export var reach_wu: float
# Wounding power: the per-type lethality factor SoldierCombat.wound() scales by.
@export var lethality: float
# Rest pose: the angle (radians, relative to the soldier's facing) the weapon
# is held at when not striking. Feeds the render once visuals read the type.
@export var default_hold_angle: float
# How often this weapon lands a melee damage tick, in seconds — the regiment's
# aggregate battle-pace cadence (see Unit.ATTACK_INTERVAL's own doc comment: not a
# literal per-soldier swing rate). Per-weapon-type since a telegraphed thrust and a
# quick slashing exchange land at genuinely different tempos.
@export var attack_interval_s: float


## Build one interned type instance. Registry construction only — everything
## else reads shared instances through LoadoutRegistry.weapon(id).
static func make(p_id: int, p_name: String, p_reach_m: float, p_lethality: float,
		p_attack_interval_s: float, p_hold_angle: float = 0.0) -> Weapon:
	var w := Weapon.new()
	w.id = p_id
	w.display_name = p_name
	w.reach_m = p_reach_m
	w.reach_wu = p_reach_m * WorldScaleRef.WU_PER_M
	w.lethality = p_lethality
	w.attack_interval_s = p_attack_interval_s
	w.default_hold_angle = p_hold_angle
	return w


## The weapon's reach in metres under a terrain speed multiplier — the same
## plain float the movement code reads from PathField.active.speed_at(), so
## cramped ground shortens an effective thrust the way it slows a march.
## Pure; nothing reads it for gameplay yet.
func effective_reach(terrain_speed_multiplier: float) -> float:
	return reach_m * terrain_speed_multiplier
