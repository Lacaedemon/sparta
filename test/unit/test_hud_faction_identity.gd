extends GutTest
## Faction identity reaching the HUD: once a battle tells the HUD which Faction.Type each side
## fights under (Battle.team_factions -> HUD.set_team_factions), the formation button, the
## formation drop-up menu, the Menu's form-up items, and the info panel's own Formation /
## Faction / Doctrine lines all carry that side's historical names. A side with no faction
## keeps every plain name it had before.

const HUDScript = preload("res://scripts/HUD.gd")
const UnitScript = preload("res://scripts/Unit.gd")
const FactionScript = preload("res://scripts/Faction.gd")
const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")


func _hud() -> CanvasLayer:
	var h = HUDScript.new()
	add_child_autofree(h)
	return h


func _unit(team: int = 0) -> Unit:
	var u: Unit = UnitScript.new()
	u.uid = 1
	u.team = team
	u.max_soldiers = 10
	add_child_autofree(u)
	return u


func _formation_button_text(hud) -> String:
	return str(hud._ctrl_formation_btn.text).replace(" ▾", "")


# --- the formation button and the info panel's Formation line --------------------------

func test_every_faction_reaches_the_formation_button_and_info_line() -> void:
	# One assertion per Faction.Type, so a table that gains a faction but misses the wiring
	# (or vice versa) fails here rather than only in whichever faction a demo happens to use.
	for f_id in FactionScript.ALL_TYPES:
		var hud := _hud()
		var u := _unit()
		hud.set_team_factions([f_id, FactionScript.NONE])
		hud.show_unit(u, 1)
		var historical: String = FactionScript.HISTORICAL_FORMATIONS[f_id][UnitScript.FORMATION_NORMAL]
		assert_string_contains(_formation_button_text(hud), "(%s)" % historical,
				"the control-bar formation button names %s's own normal-order formation"
				% FactionScript.get_faction_name(f_id))
		assert_string_contains(hud._info.text, "Formation: %s" % _formation_button_text(hud),
				"the info panel's Formation line matches the button, historical name included")


func test_the_formation_button_keeps_its_plain_interval_caption() -> void:
	# The historical name is appended to, never a replacement for, the live interval/stance
	# caption -- that caption is what the distance legend and the demo transcript check.
	var hud := _hud()
	var u := _unit()
	hud.set_team_factions([FactionScript.Type.SPARTA])
	u.formation_mode = UnitScript.FORMATION_TIGHT
	hud.show_unit(u, 1)
	var plain: String = u.formation_label_for_mode(UnitScript.FORMATION_TIGHT)
	assert_eq(_formation_button_text(hud), "%s (synaspismos)" % plain)


func test_a_side_with_no_faction_keeps_the_plain_names() -> void:
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)   # never told any faction: the standalone/replay/campaign case
	assert_eq(_formation_button_text(hud), u.formation_summary(),
			"the button is the bare interval caption with no historical name appended")
	assert_false(hud._info.text.contains("Faction:"),
			"no Faction line for a side that has none")
	assert_false(hud._info.text.contains("Doctrine:"),
			"no Doctrine line for a side that has none")


func test_an_explicit_none_entry_is_the_same_as_no_faction() -> void:
	var hud := _hud()
	var u := _unit(1)
	hud.set_team_factions([FactionScript.Type.SPARTA, FactionScript.NONE])
	hud.show_unit(u, 1)
	assert_eq(_formation_button_text(hud), u.formation_summary(),
			"team 1 has no faction, so its unit reads plain even while team 0 has one")


func test_each_unit_reads_its_own_side_not_the_players() -> void:
	# All-teams control (and a spectated replay) can select the OTHER army's units, so the
	# caption has to follow the shown unit's team rather than the player's own faction.
	var hud := _hud()
	hud.set_team_factions([FactionScript.Type.SPARTA, FactionScript.Type.ROME])
	var enemy := _unit(1)
	hud.show_unit(enemy, 1)
	assert_string_contains(_formation_button_text(hud), "(acies)",
			"a team-1 unit is named in team 1's own language, not the player's")
	assert_false(_formation_button_text(hud).contains("pyknosis"),
			"team 0's Spartan name never leaks onto a team-1 unit")
	assert_string_contains(hud._info.text, "Faction: %s" % FactionScript.get_faction_name(
			FactionScript.Type.ROME))


func test_faction_for_team_falls_back_to_none_outside_the_table() -> void:
	var hud := _hud()
	hud.set_team_factions([FactionScript.Type.CARTHAGE])
	assert_eq(hud.faction_for_team(0), FactionScript.Type.CARTHAGE)
	assert_eq(hud.faction_for_team(1), FactionScript.NONE, "a team past the end has none")
	assert_eq(hud.faction_for_team(-1), FactionScript.NONE, "a negative team has none")


func test_set_team_factions_copies_the_array() -> void:
	# Battle hands over its own live team_factions; the HUD must not alias it, or a later
	# write on either side would silently retitle the other's captions.
	var hud := _hud()
	var source: Array = [FactionScript.Type.MACEDON]
	hud.set_team_factions(source)
	source[0] = FactionScript.Type.ROME
	assert_eq(hud.faction_for_team(0), FactionScript.Type.MACEDON)


# --- the formation drop-up menu -------------------------------------------------------

func test_the_formation_menu_names_every_mode_in_the_factions_language() -> void:
	var hud := _hud()
	var u := _unit()
	hud.set_team_factions([FactionScript.Type.CARTHAGE])
	hud.show_unit(u, 1)
	var popup: PopupMenu = hud._ctrl_formation_btn.get_popup()
	for mode: int in HUDScript._FORMATION_MENU_ORDER:
		var idx: int = popup.get_item_index(mode)
		assert_gte(idx, 0, "formation mode %d has a menu item" % mode)
		assert_string_contains(popup.get_item_text(idx),
				"(%s)" % FactionScript.HISTORICAL_FORMATIONS[FactionScript.Type.CARTHAGE][mode],
				"menu item for mode %d carries Carthage's own name" % mode)


func test_the_formation_menu_stays_plain_without_a_faction() -> void:
	var hud := _hud()
	var u := _unit()
	hud.show_unit(u, 1)
	var popup: PopupMenu = hud._ctrl_formation_btn.get_popup()
	for mode: int in HUDScript._FORMATION_MENU_ORDER:
		assert_eq(popup.get_item_text(popup.get_item_index(mode)),
				u.formation_label_for_mode(mode),
				"menu item for mode %d is the bare interval caption" % mode)


# --- the Menu's form-up items ---------------------------------------------------------

func test_the_form_up_menu_names_the_player_factions_own_manoeuvres() -> void:
	var hud := _hud()
	hud.set_team_factions([FactionScript.Type.SPARTA, FactionScript.Type.ROME])
	var popup: PopupMenu = hud._menu_button.get_popup()
	var echelon_right: int = popup.get_item_index(HUDScript.MENU_FORMUP_ECHELON_RIGHT)
	assert_string_contains(popup.get_item_text(echelon_right), "(lophos dexios)",
			"the default-picker item reads in the PLAYER's language, not the enemy's")
	var cycle_right: int = popup.get_item_index(HUDScript.MENU_FORMUP_CYCLE_ECHELON_RIGHT)
	assert_string_contains(popup.get_item_text(cycle_right), "(lophos dexios)",
			"the Y-key cycle checkbox for the same mode shares that label")


func test_the_form_up_menu_leaves_unnamed_modes_plain() -> void:
	var hud := _hud()
	hud.set_team_factions([FactionScript.Type.SPARTA])
	var popup: PopupMenu = hud._menu_button.get_popup()
	var idx: int = popup.get_item_index(HUDScript.MENU_FORMUP_EQUAL_DEPTH)
	assert_eq(popup.get_item_text(idx), "Equal depth (count)",
			"HISTORICAL_FORM_UP covers only the checkerboard/echelon modes")


func test_the_checkerboard_item_never_doubles_the_quincunx() -> void:
	# The plain label already spells "Checkerboard (quincunx)", which is itself Rome's own
	# name for it -- appending the table's entry again would read "(quincunx) (quincunx)".
	var hud := _hud()
	hud.set_team_factions([FactionScript.Type.ROME])
	var popup: PopupMenu = hud._menu_button.get_popup()
	var idx: int = popup.get_item_index(HUDScript.MENU_FORMUP_CHECKERBOARD)
	assert_eq(popup.get_item_text(idx), "Checkerboard (quincunx)")


func test_a_non_roman_faction_still_gets_its_own_checkerboard_name() -> void:
	var hud := _hud()
	hud.set_team_factions([FactionScript.Type.CARTHAGE])
	var popup: PopupMenu = hud._menu_button.get_popup()
	var idx: int = popup.get_item_index(HUDScript.MENU_FORMUP_CHECKERBOARD)
	assert_string_contains(popup.get_item_text(idx), "(shatranj)")


func test_the_form_up_menu_stays_plain_without_a_faction() -> void:
	var hud := _hud()
	var popup: PopupMenu = hud._menu_button.get_popup()
	assert_eq(popup.get_item_text(popup.get_item_index(HUDScript.MENU_FORMUP_ECHELON_LEFT)),
			str(SelectionManagerScript.FORM_UP_DIST_NAMES[
					SelectionManagerScript.FormUpDist.ECHELON_LEFT]))


# --- the doctrine (strategy) readout --------------------------------------------------

func test_the_info_panel_names_the_sides_faction_and_doctrine() -> void:
	for f_id in FactionScript.ALL_TYPES:
		var hud := _hud()
		var u := _unit()
		hud.set_team_factions([f_id])
		hud.show_unit(u, 1)
		assert_string_contains(hud._info.text,
				"Faction: %s" % FactionScript.get_faction_name(f_id))
		assert_string_contains(hud._info.text,
				"Doctrine: %s" % FactionScript.get_strategy_name(f_id))
