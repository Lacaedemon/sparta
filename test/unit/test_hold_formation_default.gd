extends GutTest
## Default-to-hold: a directly player-commanded unit (auto_advance_on_detect false), under
## the plain NORMAL stance with a detected enemy still outside weapon range and no order,
## holds formation instead of auto-advancing onto it. The AI-driven enemy (flag true) still
## closes, and an explicit move or attack order still advances a player unit regardless.
## Battle owns the flag: false for the units the player commands directly (team 0, or every
## team under all-teams control), true for the AI-driven enemy army.

const BattleScript = preload("res://scripts/Battle.gd")

## DETECTION_RANGE is 190 wu; melee contact is attack_range + RADIUS + enemy.RADIUS
## (~62 wu for the default loadout), so a foe 120 wu away is detected yet well outside
## weapon range -- exactly the reactive close-the-distance case this behaviour governs.
const DETECTED_OUT_OF_RANGE_GAP := 120.0


func _make_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 120
	# _ready() (runs on add_child) sets soldiers = max_soldiers and joins the "units" group,
	# so current_target()'s detection scan can see it.
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## A live enemy `DETECTED_OUT_OF_RANGE_GAP` wu below `from` -- detected, but out of weapon
## range, so the combat branches don't engage it and the reactive auto-advance path decides
## whether the unit closes.
func _detected_enemy_below(from: Unit) -> Unit:
	var e := _make_unit()
	e.team = 1 - from.team
	e.position = from.position + Vector2(0.0, DETECTED_OUT_OF_RANGE_GAP)
	return e


# --- The behaviour change -----------------------------------------------------

func test_player_unit_holds_formation_when_enemy_only_detected_not_in_range() -> void:
	var u := _make_unit()
	u.team = 0
	u.auto_advance_on_detect = false   # a directly player-commanded unit
	var enemy := _detected_enemy_below(u)
	var before: Vector2 = u.position
	u._think(0.1)
	assert_eq(u.position, before,
		"a held player unit does not advance onto a foe still outside weapon range")
	assert_eq(u.state, Unit.State.IDLE,
		"with nothing in range and no order, the held unit stays idle")
	# The enemy is real and reachable -- the unit simply chose not to chase it.
	assert_not_null(enemy)


func test_ai_unit_still_auto_advances_when_enemy_only_detected() -> void:
	var u := _make_unit()
	u.team = 1
	u.auto_advance_on_detect = true    # the AI-driven enemy army
	var enemy := _detected_enemy_below(u)
	assert_not_null(enemy)
	var gap_before: float = u.position.distance_to(enemy.position)
	u._think(0.1)
	assert_lt(u.position.distance_to(enemy.position), gap_before,
		"an AI unit closes the distance on a detected foe so the battle still starts")


# --- Explicit orders are unaffected -------------------------------------------

func test_held_player_unit_still_obeys_an_explicit_move_order() -> void:
	var u := _make_unit()
	u.team = 0
	u.auto_advance_on_detect = false
	# A plain move order straight ahead -- the unit already faces +y, so it marches at once
	# rather than about-facing in place first. The hold default must not suppress an
	# explicit move.
	u.has_move_target = true
	u.move_target = Vector2(0.0, 300.0)
	var before: Vector2 = u.position
	u._think(0.1)
	assert_ne(u.position, before,
		"a held unit still marches when the player gives it a move order")


func test_held_player_unit_still_chases_an_explicit_attack_target() -> void:
	var u := _make_unit()
	u.team = 0
	u.auto_advance_on_detect = false
	var enemy := _detected_enemy_below(u)
	u.target_enemy = enemy             # an explicit attack order on the detected foe
	var gap_before: float = u.position.distance_to(enemy.position)
	u._think(0.1)
	assert_lt(u.position.distance_to(enemy.position), gap_before,
		"an explicit attack order still closes on a foe outside weapon range")


# --- Battle wires the flag from control ---------------------------------------

func test_battle_marks_only_ai_units_as_auto_advancing() -> void:
	# Battle.gd carries no class_name (see its own file), so it is reached through the
	# preloaded script rather than a static type annotation.
	var b := BattleScript.new()
	autofree(b)
	assert_false(b._unit_auto_advances_on_detect(0),
		"team 0 (the player's own army) holds formation by default")
	assert_true(b._unit_auto_advances_on_detect(1),
		"team 1 (the AI enemy) keeps auto-advancing so battles start")


func test_all_teams_control_holds_every_team() -> void:
	var b := BattleScript.new()
	autofree(b)
	b.all_teams_control = true
	assert_false(b._unit_auto_advances_on_detect(0),
		"under all-teams control the player commands team 0 directly, so it holds")
	assert_false(b._unit_auto_advances_on_detect(1),
		"under all-teams control the player commands team 1 directly too, so it holds")
