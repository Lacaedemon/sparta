extends GutTest
## Unit tests for per-unit local combat status derived from physics and combat state.

const UnitScript = preload("res://scripts/Unit.gd")
const UnitMoraleScript = preload("res://scripts/UnitMorale.gd")


func _unit(soldiers: int = 100, state: Unit.State = Unit.State.FIGHTING) -> Unit:
	var u: Unit = UnitScript.new()
	u.max_soldiers = soldiers
	u.soldiers = soldiers
	u.state = state
	u.morale = 100.0
	add_child_autofree(u)
	u.soldiers = soldiers
	return u


func _engage(u: Unit, enemy: Unit) -> void:
	u._adjacent_engaged_cache = [enemy]
	u._adjacent_engaged_cache_frame = Engine.get_physics_frames()


func test_combat_status_not_in_combat_when_idle_or_unengaged() -> void:
	var u := _unit(100, Unit.State.IDLE)
	assert_eq(u.combat_status_name(), "not_in_combat")
	assert_eq(UnitMoraleScript.classify_combat_status(u), UnitMoraleScript.CombatStatus.NOT_IN_COMBAT)

	var u_fight := _unit(100, Unit.State.FIGHTING)
	# Engaged units list empty
	assert_eq(u_fight.combat_status_name(), "not_in_combat")


func test_combat_status_winning_decisively_when_severely_outnumbering_enemy() -> void:
	var u := _unit(100, Unit.State.FIGHTING)
	var e := _unit(20, Unit.State.FIGHTING)
	e.team = 1
	_engage(u, e)

	assert_eq(u.combat_status_name(), "winning_decisively")
	assert_eq(UnitMoraleScript.classify_combat_status(u), UnitMoraleScript.CombatStatus.WINNING_DECISIVELY)


func test_combat_status_winning_when_outnumbering_enemy() -> void:
	var u := _unit(100, Unit.State.FIGHTING)
	var e := _unit(70, Unit.State.FIGHTING)
	e.team = 1
	_engage(u, e)

	assert_eq(u.combat_status_name(), "winning")
	assert_eq(UnitMoraleScript.classify_combat_status(u), UnitMoraleScript.CombatStatus.WINNING)


func test_combat_status_balanced_when_roughly_equal() -> void:
	var u := _unit(100, Unit.State.FIGHTING)
	var e := _unit(100, Unit.State.FIGHTING)
	e.team = 1
	_engage(u, e)

	assert_eq(u.combat_status_name(), "balanced")
	assert_eq(UnitMoraleScript.classify_combat_status(u), UnitMoraleScript.CombatStatus.BALANCED)


func test_combat_status_losing_when_outnumbered() -> void:
	var u := _unit(50, Unit.State.FIGHTING)
	var e := _unit(80, Unit.State.FIGHTING)
	e.team = 1
	_engage(u, e)

	assert_eq(u.combat_status_name(), "losing")
	assert_eq(UnitMoraleScript.classify_combat_status(u), UnitMoraleScript.CombatStatus.LOSING)


func test_combat_status_losing_decisively_when_severely_outnumbered() -> void:
	var u := _unit(30, Unit.State.FIGHTING)
	var e := _unit(100, Unit.State.FIGHTING)
	e.team = 1
	_engage(u, e)

	assert_eq(u.combat_status_name(), "losing_decisively")
	assert_eq(UnitMoraleScript.classify_combat_status(u), UnitMoraleScript.CombatStatus.LOSING_DECISIVELY)


func test_losing_combat_erodes_morale() -> void:
	var u := _unit(30, Unit.State.FIGHTING)
	var e := _unit(100, Unit.State.FIGHTING)
	e.team = 1
	_engage(u, e)
	u.morale = 80.0

	UnitMoraleScript.tick_morale(u, 1.0)
	assert_lt(u.morale, 80.0, "losing combat erodes morale during combat")

	var u2 := _unit(50, Unit.State.FIGHTING)
	var e2 := _unit(80, Unit.State.FIGHTING)
	e2.team = 1
	_engage(u2, e2)
	u2.morale = 80.0

	UnitMoraleScript.tick_morale(u2, 1.0)
	assert_lt(u2.morale, 80.0, "losing moderate combat erodes morale during combat")


func test_snapshot_dict_exports_combat_status() -> void:
	var u := _unit(100, Unit.State.IDLE)
	var dict: Dictionary = u.to_snapshot_dict()
	assert_true("combat_status" in dict, "snapshot dict contains combat_status field")
	assert_eq(dict["combat_status"], "not_in_combat")
