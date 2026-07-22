extends GutTest
## HUD's own wiring of the unit card tray: filtering to the player's own team, and refreshing
## it periodically during a live battle (not only when an unrelated Settings toggle fires).

const HUDScript = preload("res://scripts/HUD.gd")
const UnitScript = preload("res://scripts/Unit.gd")

var _orig_show_tray: bool


func before_each() -> void:
	_orig_show_tray = Settings.show_unit_card_tray


func after_each() -> void:
	Settings.show_unit_card_tray = _orig_show_tray


## Builds a HUD alongside a real SelectionManager sibling named "SelectionManager", matching
## the relative lookup HUD._ready() uses (get_node_or_null("../SelectionManager")).
func _hud_with_selection_manager() -> HUDScript:
	var parent := Node.new()
	add_child_autofree(parent)
	var sm := SelectionManager.new()
	sm.name = "SelectionManager"
	parent.add_child(sm)
	var hud := HUDScript.new()
	parent.add_child(hud)
	return hud


func _unit(team: int) -> UnitScript:
	var u := UnitScript.new()
	u.team = team
	add_child_autofree(u)   # joins the "units" group in _ready()
	return u


func test_own_team_units_excludes_the_enemy() -> void:
	var hud := _hud_with_selection_manager()
	var mine := _unit(0)
	var theirs := _unit(1)

	var result: Array = hud._own_team_units()

	assert_true(result.has(mine), "the player's own unit is included")
	assert_false(result.has(theirs), "an enemy unit is excluded (issue #869: the player's own battle lines)")


func test_sync_unit_card_tray_visibility_only_shows_own_team_cards() -> void:
	Settings.show_unit_card_tray = true
	var hud := _hud_with_selection_manager()
	var mine := _unit(0)
	var theirs := _unit(1)

	hud._sync_unit_card_tray_visibility()

	var shown: Array = hud._unit_card_tray.get_units_in_tray_order()
	assert_true(shown.has(mine), "the tray shows the player's own unit")
	assert_false(shown.has(theirs), "the tray never shows an enemy unit's card")


func test_process_refreshes_the_tray_once_a_second_during_a_battle() -> void:
	Settings.show_unit_card_tray = true
	var hud := _hud_with_selection_manager()
	var mine := _unit(0)
	hud._process(1.0)   # closes the tick-rate window; should also resync the tray
	assert_eq(hud._unit_card_tray.get_units_in_tray_order().size(), 1,
			"the tray already reflects the unit present at HUD startup")

	var reinforcement := _unit(0)
	hud._process(1.0)   # a second window closing should pick up the new arrival

	var shown: Array = hud._unit_card_tray.get_units_in_tray_order()
	assert_true(shown.has(reinforcement),
			"a unit that joins mid-battle appears without any Settings toggle firing")
	assert_eq(shown.size(), 2, "both the original unit and the reinforcement are shown")
