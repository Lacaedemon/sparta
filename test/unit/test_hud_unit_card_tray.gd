extends GutTest
## HUD's own wiring of the unit card tray: filtering to the player's own team, and refreshing
## it periodically during a live battle (not only when an unrelated Settings toggle fires).

const HUDScript = preload("res://scripts/HUD.gd")
const UnitScript = preload("res://scripts/Unit.gd")

var _orig_show_tray: bool


func before_each() -> void:
	_orig_show_tray = Settings.show_unit_card_tray
	# Force a known starting state (arrange-phase only -- guarded so it never touches disk):
	# several tests below assume the tray starts hidden, which doesn't hold if a prior run
	# (in this suite or a real play session) left show_unit_card_tray persisted as true.
	Settings._loading = true
	Settings.show_unit_card_tray = false
	Settings._loading = false


func after_each() -> void:
	# Deliberately UNGUARDED: several tests below drive the real setter (via the button's
	# own toggled handler or the menu dispatch) to verify the live Settings.changed sync
	# chain, which really does persist to user://settings.cfg mid-test. A guarded restore
	# here would only fix the in-memory value, leaving that mid-test write on disk -- this
	# real write is what actually undoes it, regardless of what happened during the test.
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
	assert_false(result.has(theirs), "an enemy unit is excluded -- the tray is the player's own battle lines")


func test_own_team_units_is_empty_with_no_selection_manager_sibling() -> void:
	var hud := HUDScript.new()
	add_child_autofree(hud)   # no "../SelectionManager" sibling, so _sel_mgr stays null
	assert_eq(hud._own_team_units(), [], "no SelectionManager to resolve own-team against")


func test_sync_unit_card_tray_visibility_only_shows_own_team_cards() -> void:
	Settings._loading = true
	Settings.show_unit_card_tray = true
	Settings._loading = false
	var hud := _hud_with_selection_manager()
	var mine := _unit(0)
	var theirs := _unit(1)

	hud._sync_unit_card_tray_visibility()

	var shown: Array = hud._unit_card_tray.get_units_in_tray_order()
	assert_true(shown.has(mine), "the tray shows the player's own unit")
	assert_false(shown.has(theirs), "the tray never shows an enemy unit's card")


func test_process_refreshes_the_tray_once_a_second_during_a_battle() -> void:
	Settings._loading = true
	Settings.show_unit_card_tray = true
	Settings._loading = false
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


# --- persistent tray-toggle button ---------------------------------------------------
# The tray was previously only reachable via the Menu popup's "Unit card tray"
# check item -- a persistent button beside Menu gives it an always-visible entry point.

func test_pressing_the_tray_toggle_button_shows_the_tray() -> void:
	var hud := _hud_with_selection_manager()
	assert_false(hud._unit_card_tray.visible, "starts hidden (show_unit_card_tray defaults false)")

	hud._tray_toggle_btn.set_pressed_no_signal(true)
	hud._tray_toggle_btn.toggled.emit(true)

	assert_true(Settings.show_unit_card_tray, "pressing the button turns the setting on")
	assert_true(hud._unit_card_tray.visible, "...and the tray becomes visible immediately")


func test_pressing_the_tray_toggle_button_again_hides_the_tray() -> void:
	var hud := _hud_with_selection_manager()
	hud._tray_toggle_btn.set_pressed_no_signal(true)
	hud._tray_toggle_btn.toggled.emit(true)

	hud._tray_toggle_btn.set_pressed_no_signal(false)
	hud._tray_toggle_btn.toggled.emit(false)

	assert_false(Settings.show_unit_card_tray, "pressing it again turns the setting back off")
	assert_false(hud._unit_card_tray.visible, "...and the tray hides immediately")


func test_tray_toggle_button_reflects_the_menu_checkbox_and_vice_versa() -> void:
	var hud := _hud_with_selection_manager()

	# Toggling via the menu's own dispatch path (not the new button) still updates the button.
	hud._on_menu_id(HUDScript.MENU_UNIT_CARD_TRAY)
	assert_true(hud._tray_toggle_btn.button_pressed,
			"the button re-syncs when the tray is toggled from the menu instead")

	var popup := hud._menu_button.get_popup()
	assert_true(popup.is_item_checked(popup.get_item_index(HUDScript.MENU_UNIT_CARD_TRAY)),
			"and the menu checkbox reflects the same setting")


# --- F1 hotkey --------------------------------------------------------------------------
# Not Tab: Tab is Godot's own built-in ui_focus_next action, hijacked by GUI focus
# navigation on whatever Control currently holds keyboard focus (see HUD.gd's own comment
# on _is_tray_toggle_keypress). F1 is free and immune to Godot's built-in UI bindings.

func _f1_keydown() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F1
	ev.pressed = true
	return ev


func test_is_tray_toggle_keypress_matches_only_a_fresh_f1_keydown() -> void:
	var hud := _hud_with_selection_manager()
	assert_true(hud._is_tray_toggle_keypress(_f1_keydown()), "a plain F1 keydown matches")

	var released := _f1_keydown()
	released.pressed = false
	assert_false(hud._is_tray_toggle_keypress(released), "a key-up doesn't toggle it")

	var echoed := _f1_keydown()
	echoed.echo = true
	assert_false(hud._is_tray_toggle_keypress(echoed), "an OS key-repeat echo doesn't re-toggle it")

	var other_key := InputEventKey.new()
	other_key.physical_keycode = KEY_SPACE
	other_key.pressed = true
	assert_false(hud._is_tray_toggle_keypress(other_key), "an unrelated key doesn't match")

	var tab_key := InputEventKey.new()
	tab_key.physical_keycode = KEY_TAB
	tab_key.pressed = true
	assert_false(hud._is_tray_toggle_keypress(tab_key),
			"Tab specifically doesn't match -- it's Godot's own ui_focus_next key")


func test_pressing_f1_toggles_the_tray() -> void:
	var hud := _hud_with_selection_manager()
	assert_false(hud._unit_card_tray.visible, "starts hidden")

	hud._unhandled_input(_f1_keydown())
	assert_true(Settings.show_unit_card_tray, "F1 turns the setting on")
	assert_true(hud._unit_card_tray.visible, "...and the tray becomes visible immediately")

	hud._unhandled_input(_f1_keydown())
	assert_false(Settings.show_unit_card_tray, "F1 again turns it back off")
	assert_false(hud._unit_card_tray.visible, "...and the tray hides immediately")
