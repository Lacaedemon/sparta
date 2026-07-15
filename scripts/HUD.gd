extends CanvasLayer
## On-screen UI, built in code (no .tscn needed):
##   - top hint bar
##   - top-right Menu button: restart the battle plus global options
##   - selected-unit info panel (bottom-left)
##   - victory/defeat overlay with a restart button

const BattleRef = preload("res://scripts/Battle.gd")
const BuildInfoRef = preload("res://scripts/BuildInfo.gd")
const CampaignBattleRef = preload("res://scripts/campaign/CampaignBattle.gd")
const SelectionManagerRef = preload("res://scripts/SelectionManager.gd")
const UnitRef = preload("res://scripts/Unit.gd")

# Stable ids for the Menu popup's items (independent of index / separators). The seven
# MENU_FORMUP_EQUAL_*/MENU_FORMUP_CHECKERBOARD/MENU_FORMUP_ECHELON_* ids set the default
# multi-unit form-up distribution (radio-checked); the matching MENU_FORMUP_CYCLE_* ids
# toggle Y-key cycle membership (see _FORMUP_ENTRIES below).
enum { MENU_RESTART, MENU_RESTART_REPLAY, MENU_LOAD, MENU_EDGE_SCROLL, MENU_SFX,
		MENU_FORMUP_EQUAL_DEPTH_SPACE, MENU_FORMUP_EQUAL_DEPTH,
		MENU_FORMUP_EQUAL_WIDTH, MENU_FORMUP_EQUAL_WIDTH_COUNT, MENU_FORMUP_CHECKERBOARD,
		MENU_FORMUP_ECHELON_RIGHT, MENU_FORMUP_ECHELON_LEFT,
		MENU_FORMUP_CYCLE_DEPTH_SPACE, MENU_FORMUP_CYCLE_DEPTH,
		MENU_FORMUP_CYCLE_WIDTH, MENU_FORMUP_CYCLE_WIDTH_COUNT, MENU_FORMUP_CYCLE_CHECKERBOARD,
		MENU_FORMUP_CYCLE_ECHELON_RIGHT, MENU_FORMUP_CYCLE_ECHELON_LEFT,
		MENU_REFORM_BEFORE_MOVE, MENU_WALK_ADVANCE, MENU_DISTANCE_LEGEND, MENU_ORDER_DISTANCE,
		MENU_UNIT_SPEED, MENU_SOLDIER_IDS, MENU_ENGAGED_HIGHLIGHT, MENU_POSITION_ANCHOR, MENU_SHOW_FPS,
		MENU_FPS_CORNER_TOP_LEFT, MENU_FPS_CORNER_TOP_RIGHT, MENU_FPS_CORNER_BOTTOM_LEFT,
		MENU_FPS_CORNER_BOTTOM_RIGHT, MENU_KEYBINDINGS, MENU_SHORTCUTS,
		MENU_QUIT_TO_MENU }

var _hint: Label
var _info: Label
var _overlay: ColorRect
var _overlay_label: Label
var _menu_button: MenuButton
var _status: Label
var _paused_label: Label
var _order_mode_label: Label
var _flash_label: Label
var _watch_button: Button
var _load_dialog: FileDialog
var _error_dialog: AcceptDialog
var _save_replay_dialog: ConfirmationDialog
# Which exit to actually perform once the save-replay prompt resolves (Save or Discard).
# Set right before popping the dialog; see _confirm_exit_with_unsaved_replay.
var _pending_exit_action: Callable
var _keybindings_dialog: AcceptDialog
var _shortcuts_dialog: AcceptDialog
var _legend_panel: PanelContainer
var _legend_bar: ColorRect
var _legend_label: Label
var _legend_last_zoom: float = -1.0   # forces a first sync; _process re-syncs only on change
var _fps_label: Label
# Live-measured physics tick rate (distinct from Engine.physics_ticks_per_second, the
# configured TARGET): counts physics_frame emissions over a rolling real-time window, so it
# reads below target if the sim can't keep up with a large battle. See _on_physics_tick.
var _tick_count: int = 0
var _tick_rate_window: float = 0.0
var _live_tick_rate: float = Engine.physics_ticks_per_second   # sane value before the first sample
const PANEL_MIN := Vector2(240, 90)
const PANEL_BOTTOM_GAP := 20.0   # clearance between info panel and screen edge

# Single source of truth for the rebindable stance modes shown in the control-bar
# dropup. Each entry carries the popup item id, the OrderMode it maps to, the
# display label (used both as the menu text and the button caption), and the
# rebind slug. NORMAL is fixed to Esc and has no rebindable slug (empty string).
# Adding an OrderMode here updates the menu, the rebind refresh, and the caption
# in one place. See _stance_key_str() for how the slug becomes a hotkey label.
const _STANCE_ENTRIES := [
	{"id": 0, "mode": BattleRef.OrderMode.NORMAL, "label": "Normal", "slug": ""},
	{"id": 1, "mode": BattleRef.OrderMode.HOLD, "label": "Hold", "slug": "hold"},
	{"id": 2, "mode": BattleRef.OrderMode.ATTACK_FLANK, "label": "Flank", "slug": "attack_flank"},
	{"id": 3, "mode": BattleRef.OrderMode.ATTACK_REAR, "label": "Rear", "slug": "attack_rear"},
	{"id": 4, "mode": BattleRef.OrderMode.SKIRMISH, "label": "Skirmish", "slug": "skirmish"},
	{"id": 5, "mode": BattleRef.OrderMode.SUPPORT, "label": "Support", "slug": "support"},
	{"id": 6, "mode": BattleRef.OrderMode.CYCLE_CHARGE, "label": "Cycle charge", "slug": "cycle_charge"},
	{"id": 7, "mode": BattleRef.OrderMode.SWEEP_ROUTERS, "label": "Sweep routers", "slug": "sweep_routers"},
	{"id": 8, "mode": BattleRef.OrderMode.ROLL_THE_LINE, "label": "Roll the line", "slug": "roll_the_line"},
	{"id": 9, "mode": BattleRef.OrderMode.PIN_DOWN, "label": "Pin down", "slug": "pin_down"},
	{"id": 10, "mode": BattleRef.OrderMode.ALL_OUT_ATTACK, "label": "All-out attack", "slug": "all_out_attack"},
	{"id": 11, "mode": BattleRef.OrderMode.CHASE, "label": "Chase", "slug": "chase"},
	{"id": 12, "mode": BattleRef.OrderMode.WEDGE_CHARGE, "label": "Wedge charge", "slug": "wedge_charge"},
	{"id": 13, "mode": BattleRef.OrderMode.KNOCKBACK_FOCUS, "label": "Knockback focus", "slug": "knockback_focus"},
]

# The multi-unit form-up distribution modes, in menu order (the default, EQUAL_DEPTH_SPACE,
# first). Each entry drives BOTH the "default" radio item and the "Y-key cycles through" check
# item for that mode, sharing one label so the two sections read consistently. Adding a mode
# updates the menu, the sync/dispatch logic, and the labels in one place -- see
# SelectionManager.FormUpDist's own doc comment for what each mode holds equal.
const _FORMUP_ENTRIES := [
	{"mode": SelectionManagerRef.FormUpDist.EQUAL_DEPTH_SPACE, "label": "Equal depth (space)",
		"default_id": MENU_FORMUP_EQUAL_DEPTH_SPACE, "cycle_id": MENU_FORMUP_CYCLE_DEPTH_SPACE},
	{"mode": SelectionManagerRef.FormUpDist.EQUAL_DEPTH, "label": "Equal depth (count)",
		"default_id": MENU_FORMUP_EQUAL_DEPTH, "cycle_id": MENU_FORMUP_CYCLE_DEPTH},
	{"mode": SelectionManagerRef.FormUpDist.EQUAL_WIDTH, "label": "Equal width (space)",
		"default_id": MENU_FORMUP_EQUAL_WIDTH, "cycle_id": MENU_FORMUP_CYCLE_WIDTH},
	{"mode": SelectionManagerRef.FormUpDist.EQUAL_WIDTH_COUNT, "label": "Equal width (count)",
		"default_id": MENU_FORMUP_EQUAL_WIDTH_COUNT, "cycle_id": MENU_FORMUP_CYCLE_WIDTH_COUNT},
	{"mode": SelectionManagerRef.FormUpDist.CHECKERBOARD, "label": "Checkerboard (quincunx)",
		"default_id": MENU_FORMUP_CHECKERBOARD, "cycle_id": MENU_FORMUP_CYCLE_CHECKERBOARD},
	{"mode": SelectionManagerRef.FormUpDist.ECHELON_RIGHT, "label": "Echelon (right leads)",
		"default_id": MENU_FORMUP_ECHELON_RIGHT, "cycle_id": MENU_FORMUP_CYCLE_ECHELON_RIGHT},
	{"mode": SelectionManagerRef.FormUpDist.ECHELON_LEFT, "label": "Echelon (left leads)",
		"default_id": MENU_FORMUP_ECHELON_LEFT, "cycle_id": MENU_FORMUP_CYCLE_ECHELON_LEFT},
]

# Which screen corner the frame-rate counter can render in, radio-picked from the
# Menu popup. Each entry drives both the menu item and the corner's anchor preset, sharing
# one table so adding a corner (there won't be a fifth, but see _FORMUP_ENTRIES above for
# the same reasoning) updates the menu, sync, dispatch, and layout in one place.
const _FPS_CORNER_ENTRIES := [
	{"corner": Settings.FPS_CORNER_TOP_LEFT, "label": "Top-left",
		"id": MENU_FPS_CORNER_TOP_LEFT, "preset": Control.PRESET_TOP_LEFT},
	{"corner": Settings.FPS_CORNER_TOP_RIGHT, "label": "Top-right",
		"id": MENU_FPS_CORNER_TOP_RIGHT, "preset": Control.PRESET_TOP_RIGHT},
	{"corner": Settings.FPS_CORNER_BOTTOM_LEFT, "label": "Bottom-left",
		"id": MENU_FPS_CORNER_BOTTOM_LEFT, "preset": Control.PRESET_BOTTOM_LEFT},
	{"corner": Settings.FPS_CORNER_BOTTOM_RIGHT, "label": "Bottom-right",
		"id": MENU_FPS_CORNER_BOTTOM_RIGHT, "preset": Control.PRESET_BOTTOM_RIGHT},
]

# Display names and menu order for every formation mode, shared by the button
# caption and the drop-up menu so the two never drift apart.
const _FORMATION_NAMES := {
	UnitRef.FORMATION_NORMAL: "Normal",
	UnitRef.FORMATION_TIGHT: "Tight",
	UnitRef.FORMATION_LOOSE: "Loose",
	UnitRef.FORMATION_SQUARE: "Square (Orbis)",
	UnitRef.FORMATION_SHIELD_WALL: "Shield Wall",
	UnitRef.FORMATION_TESTUDO: "Testudo",
	UnitRef.FORMATION_SCHILTRON: "Schiltron",
}
const _FORMATION_MENU_ORDER := [
	UnitRef.FORMATION_NORMAL,
	UnitRef.FORMATION_TIGHT,
	UnitRef.FORMATION_LOOSE,
	UnitRef.FORMATION_SQUARE,
	UnitRef.FORMATION_SCHILTRON,
	UnitRef.FORMATION_SHIELD_WALL,
	UnitRef.FORMATION_TESTUDO,
]

var _ctrl_bar: PanelContainer
var _ctrl_formation_btn: MenuButton
var _ctrl_stance_btn: MenuButton
var _ctrl_reform_btn: Button
var _ctrl_group_attack_btn: Button
var _sel_mgr = null
var _info_panel: PanelContainer
var _order_tree_box: VBoxContainer
# Expand/collapse state for the order-tree rows below the info label, keyed by
# "<unit instance id>:<path>" where `path` is a dot-joined chain of child indices from the
# root order ("0", "0.1", "0.1.0", ...) -- see _order_tree_rows. A path missing from this
# dict defaults to expanded, so a freshly-decomposed composite order (a rear-move that just
# armed its turn+march children) shows its active leaf immediately, with no click needed.
# Keying by unit instance id keeps one selected unit's collapsed nodes from leaking onto a
# different unit whose tree happens to share the same shape (e.g. every rear-move composite
# has the same two-child path layout).
var _order_tree_expanded: Dictionary = {}
# Signature of the rows _rebuild_order_tree last actually rendered (see
# _order_tree_row_signature) -- null means "nothing built yet" (the initial state, which
# always triggers a real rebuild since a rendered tree's signature is never null). Lets
# _rebuild_order_tree skip tearing down/recreating the row Controls when nothing changed
# since the last call; see that function's doc comment for why that matters.
var _order_tree_last_signature = null
const _ORDER_TREE_INDENT := 14.0
const _ORDER_TREE_TOGGLE_WIDTH := 18.0
# Matches _order_mode_label's amber -- both mark "the order currently in effect".
const _ORDER_TREE_ACTIVE_COLOR := Color(1.0, 0.78, 0.35)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # stays responsive when paused

	# Controls hint. The order-mode keys are rendered from the live Settings bindings
	# so the bar stays accurate after a rebind; _refresh_hint re-renders on change.
	_hint = Label.new()
	_hint.position = Vector2(14, 10)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hint.add_theme_font_size_override("font_size", 14)
	add_child(_hint)
	_refresh_hint()

	# Recording / replay status (top-center).
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.position = Vector2(-90, 30)
	_status.custom_minimum_size = Vector2(180, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	if Replay.mode == Replay.Mode.PLAYBACK:
		_status.text = "▶ REPLAY"
		_status.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	else:
		_status.text = "● REC"
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	add_child(_status)

	# Active-pause indicator (top-center, below the REC/REPLAY status). Hidden
	# until the player toggles pause with Space.
	_paused_label = Label.new()
	_paused_label.text = "⏸ PAUSED"
	_paused_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_paused_label.position = Vector2(-90, 54)
	_paused_label.custom_minimum_size = Vector2(180, 0)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.add_theme_font_size_override("font_size", 18)
	_paused_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.35))
	_paused_label.visible = false
	add_child(_paused_label)

	# Armed order-mode indicator, top-center below the pause banner. Hidden
	# for the default stance; SelectionManager calls set_order_mode() to update it.
	_order_mode_label = Label.new()
	_order_mode_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_order_mode_label.position = Vector2(-120, 80)
	_order_mode_label.custom_minimum_size = Vector2(240, 0)
	_order_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_mode_label.add_theme_font_size_override("font_size", 16)
	_order_mode_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	_order_mode_label.visible = false
	add_child(_order_mode_label)

	# Transient toast just below the order-mode indicator, for brief one-off feedback
	# (e.g. the form-up distribution cycle hotkey). Auto-hides after a moment; see flash_message().
	_flash_label = Label.new()
	_flash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash_label.position = Vector2(-120, 104)
	_flash_label.custom_minimum_size = Vector2(240, 0)
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_font_size_override("font_size", 15)
	_flash_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	_flash_label.visible = false
	add_child(_flash_label)

	# Menu button (top-right) gathering the global options that used to be
	# scattered across the HUD — restart, replay loading, and the edge-scroll
	# toggle. Its popup is PROCESS_MODE_ALWAYS so it stays usable while the
	# simulation is paused. Give the button an explicit width so its placement is
	# derived from that, not a font-metric-tuned magic offset.
	_menu_button = MenuButton.new()
	_menu_button.text = "☰ Menu"
	var menu_width := 120.0
	_menu_button.custom_minimum_size = Vector2(menu_width, 0)
	_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_button.position = Vector2(-menu_width - 6.0, 6)
	add_child(_menu_button)

	var popup := _menu_button.get_popup()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS   # usable while paused
	# "Restart Battle" works mid-fight, not just from the end-of-battle overlay;
	# it always starts a fresh LIVE battle (matching the overlay's "Fight Again").
	# "Restart Replay" instead rewinds the current playback to tick 0, so it's
	# only meaningful while watching a replay — disabled (greyed) in a live battle.
	popup.add_item("Restart Battle", MENU_RESTART)
	popup.add_item("Restart Replay", MENU_RESTART_REPLAY)
	popup.set_item_disabled(popup.get_item_index(MENU_RESTART_REPLAY),
			Replay.mode != Replay.Mode.PLAYBACK)
	popup.add_item("Load Replay…", MENU_LOAD)
	popup.add_separator()
	popup.add_check_item("Mouse-edge scroll", MENU_EDGE_SCROLL)
	popup.add_check_item("Sound effects", MENU_SFX)
	# Default split for a multi-unit drag-to-form-up (radio: pick one). The live mode can
	# also be cycled mid-battle with the form-up distribution hotkey.
	popup.add_separator("Form-up: split a line by…")
	for entry in _FORMUP_ENTRIES:
		popup.add_radio_check_item(entry["label"], entry["default_id"])
	# Which modes the Y-key cycles through (check to include, uncheck to skip).
	popup.add_separator("Form-up: Y-key cycles through…")
	for entry in _FORMUP_ENTRIES:
		popup.add_check_item(entry["label"], entry["cycle_id"])
	popup.add_separator()
	popup.add_check_item("Reform before move", MENU_REFORM_BEFORE_MOVE)
	popup.add_check_item("Walk advance (no jog/sprint)", MENU_WALK_ADVANCE)
	popup.add_check_item("Distance legend (map scale)", MENU_DISTANCE_LEGEND)
	popup.add_check_item("Order distance labels", MENU_ORDER_DISTANCE)
	popup.add_check_item("Unit speed labels", MENU_UNIT_SPEED)
	popup.add_check_item("Soldier IDs (selected unit, zoom in)", MENU_SOLDIER_IDS)
	popup.add_check_item("Engaged-soldier highlight", MENU_ENGAGED_HIGHLIGHT)
	popup.add_check_item("Position-anchor marker", MENU_POSITION_ANCHOR)
	popup.add_check_item("Show frame rate", MENU_SHOW_FPS)
	popup.add_separator("Frame rate corner…")
	for entry in _FPS_CORNER_ENTRIES:
		popup.add_radio_check_item(entry["label"], entry["id"])
	popup.add_item("Keybindings…", MENU_KEYBINDINGS)
	popup.add_item("Shortcuts… (?)", MENU_SHORTCUTS)
	popup.add_separator()
	# The only way back to the main menu from a battle that never auto-ends (drill mode
	# has no enemy to win against) — also handy as a plain "give up" from any other battle.
	popup.add_item("Quit to Main Menu", MENU_QUIT_TO_MENU)
	_sync_setting_toggles()
	popup.id_pressed.connect(_on_menu_id)
	# Keep the check items in sync if a setting changes elsewhere. Use a named
	# method (not a lambda) so the connection is tied to this node's lifetime and
	# torn down in _exit_tree() — otherwise it would dangle on the persistent
	# Settings autoload after reload_current_scene() frees this HUD.
	Settings.changed.connect(_sync_setting_toggles)
	# Same lifetime concern: keep the hint's order-mode keys in sync after a rebind.
	Settings.changed.connect(_refresh_hint)
	# Keep the stance dropup labels in sync after a rebind (see _ctrl_bar_refresh_stance_popup).
	Settings.changed.connect(_ctrl_bar_refresh_stance_popup)
	# Counts physics steps for the frame-rate counter's tick-rate readout. A tree-level
	# signal, not tied to any one node's process mode, so it keeps counting even while paused
	# and needs no reference to the live Battle node.
	get_tree().physics_frame.connect(_on_physics_tick)

	# File picker for choosing a saved replay, plus an error popup for bad files.
	# Both stay responsive while the tree is paused (end-of-battle overlay).
	_load_dialog = FileDialog.new()
	_load_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_load_dialog.access = FileDialog.ACCESS_USERDATA
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.filters = PackedStringArray(["*.json ; Replay files"])
	_load_dialog.title = "Load Replay"
	_load_dialog.size = Vector2i(640, 480)
	_load_dialog.file_selected.connect(_on_replay_chosen)
	add_child(_load_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	# Neutral default; each caller sets a context-specific title before popping it.
	_error_dialog.title = "Replay"
	add_child(_error_dialog)

	# A commit-mismatch warning survives reload_current_scene() (Replay is an autoload), so
	# it's shown here rather than at the call site that triggered playback -- covers every
	# entry point (Load Replay, Restart Replay, a main-menu picker) in one place, right after
	# the scene that will actually run the mismatched replay has loaded. One-shot: clear it
	# immediately so a later restart of the *same* file re-warns (still relevant), but this
	# particular _ready() doesn't loop back and show it again.
	if Replay.mode == Replay.Mode.PLAYBACK and Replay.last_load_sha_mismatch != "":
		var mismatched_sha := Replay.last_load_sha_mismatch
		Replay.last_load_sha_mismatch = ""
		_error_dialog.title = "Replay"
		_error_dialog.dialog_text = ("This replay was recorded on commit %s; this build is %s. " +
				"It should still play, but a game-logic change between them could cause a desync.") \
				% [mismatched_sha, BuildInfoRef.COMMIT_SHA]
		_error_dialog.popup_centered()

	# Offered on every exit that would otherwise silently discard an unsaved recording
	# (Quit to Main Menu, Return to Campaign) -- see _confirm_exit_with_unsaved_replay.
	_save_replay_dialog = ConfirmationDialog.new()
	_save_replay_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_replay_dialog.title = "Save Replay?"
	_save_replay_dialog.dialog_text = "This battle hasn't been saved as a replay yet. Save it before leaving?"
	_save_replay_dialog.ok_button_text = "Save"
	_save_replay_dialog.add_button("Discard", true, "discard")
	_save_replay_dialog.confirmed.connect(_on_save_replay_confirmed)
	_save_replay_dialog.custom_action.connect(_on_save_replay_custom_action)
	add_child(_save_replay_dialog)

	# Rebindable order-mode hotkeys. Its own PROCESS_MODE_ALWAYS dialog so it's
	# usable while paused, like the other menu dialogs.
	_keybindings_dialog = preload("res://scripts/KeybindingsDialog.gd").new()
	add_child(_keybindings_dialog)

	# Read-only "every shortcut" reference, opened by ? or ☰ Menu → Shortcuts.
	_shortcuts_dialog = preload("res://scripts/ShortcutsOverlay.gd").new()
	add_child(_shortcuts_dialog)

	# Selected-unit info panel, pinned above the bottom-left corner. The top
	# offset is derived from the panel's own min-height + bottom margin (not a
	# hand-tuned magic number), and grow_vertical = BEGIN lets it expand UPWARD
	# if a content row or a larger font is added — so it never clips past the
	# screen's bottom edge. offset_left/offset_top/offset_bottom are set directly
	# (not via `position`) since this Control is anchored bottom-left
	# (anchor_top == anchor_bottom == 1): offset_top/offset_bottom are the true
	# pixel distances from that anchor line, while `position` resolves anchors
	# against whatever the parent size happens to be AT THE MOMENT it's set —
	# see _info_panel_raise()/_info_panel_lower()'s doc comment for how that bit
	# every later per-frame reposition. offset_top/offset_bottom are set once here
	# to their at-rest values; _info_panel_raise()/_info_panel_lower() move both by
	# the same amount later so the panel translates as a rigid rectangle instead of
	# stretching.
	_info_panel = PanelContainer.new()
	_info_panel.custom_minimum_size = PANEL_MIN
	_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_panel.offset_left = 14.0
	_info_panel.offset_top = -(PANEL_MIN.y + PANEL_BOTTOM_GAP)
	_info_panel.offset_bottom = -PANEL_BOTTOM_GAP
	add_child(_info_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_info_panel.add_child(margin)

	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 2)
	margin.add_child(info_col)

	_info = Label.new()
	_info.text = "No unit selected"
	info_col.add_child(_info)

	# Order-tree rows (see _rebuild_order_tree): rebuilt fresh each show_unit() call, right
	# below the stats block. Empty/hidden until a unit with a current_order is shown.
	_order_tree_box = VBoxContainer.new()
	_order_tree_box.add_theme_constant_override("separation", 1)
	_order_tree_box.visible = false
	info_col.add_child(_order_tree_box)

	_sel_mgr = get_node_or_null("../SelectionManager")
	_build_ctrl_bar()
	_build_distance_legend()
	_build_fps_label()

	# End-of-battle overlay.
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	_overlay_label = Label.new()
	_overlay_label.text = "Battle Over"
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 48)
	box.add_child(_overlay_label)

	# A campaign-launched battle returns its result to the map instead of
	# restarting; "Fight Again"/"Load Replay" (which replace this battle) would strand
	# the campaign, so only offer Return + Watch Replay there. Safe to decide at _ready
	# (rather than in show_end): `active` is set before the battle scene loads and stays
	# fixed for the battle's whole lifetime — nothing toggles it mid-battle.
	if CampaignBattleRef.active:
		var ret := Button.new()
		ret.text = "⮐ Return to Campaign"
		ret.custom_minimum_size = Vector2(220, 44)
		ret.pressed.connect(_on_return_to_campaign)
		box.add_child(ret)
	else:
		var restart := Button.new()
		restart.text = "Fight Again"
		restart.custom_minimum_size = Vector2(180, 44)
		restart.pressed.connect(_on_restart)
		box.add_child(restart)

	# Replay the battle that just finished (re-runs the saved log).
	_watch_button = Button.new()
	_watch_button.text = "Watch Again" if Replay.mode == Replay.Mode.PLAYBACK else "Watch Replay"
	_watch_button.custom_minimum_size = Vector2(180, 44)
	_watch_button.pressed.connect(_on_watch_replay)
	box.add_child(_watch_button)

	# Open an older saved replay (not just the one that just finished). Hidden for a
	# campaign battle, whose only forward path is back to the map.
	if not CampaignBattleRef.active:
		var load_saved := Button.new()
		load_saved.text = "Load Replay…"
		load_saved.custom_minimum_size = Vector2(180, 44)
		load_saved.pressed.connect(_open_load_dialog)
		box.add_child(load_saved)


func _exit_tree() -> void:
	# Settings is a persistent autoload; drop our connection so it doesn't
	# outlive this HUD (e.g. across reload_current_scene()).
	if Settings.changed.is_connected(_sync_setting_toggles):
		Settings.changed.disconnect(_sync_setting_toggles)
	if Settings.changed.is_connected(_refresh_hint):
		Settings.changed.disconnect(_refresh_hint)
	if Settings.changed.is_connected(_ctrl_bar_refresh_stance_popup):
		Settings.changed.disconnect(_ctrl_bar_refresh_stance_popup)
	if get_tree() != null and get_tree().physics_frame.is_connected(_on_physics_tick):
		get_tree().physics_frame.disconnect(_on_physics_tick)


func _sync_setting_toggles() -> void:
	var popup := _menu_button.get_popup()
	popup.set_item_checked(popup.get_item_index(MENU_EDGE_SCROLL), Settings.edge_scroll)
	popup.set_item_checked(popup.get_item_index(MENU_SFX), Settings.sfx_enabled)
	# Radio-check the chosen default form-up distribution. Compare each item to the setting
	# directly (not e.g. `not depth`), so a table with any number of modes can't leave more
	# or fewer than exactly one item checked.
	for entry in _FORMUP_ENTRIES:
		popup.set_item_checked(popup.get_item_index(entry["default_id"]),
				Settings.form_up_dist_default == entry["mode"])
		popup.set_item_checked(popup.get_item_index(entry["cycle_id"]),
				Settings.form_up_dist_cycle.has(entry["mode"]))
		# Disable the cycle checkbox for whichever mode is the current battle default:
		# unchecking it would leave the default unreachable by the Y-key cycle, with no
		# feedback that it happened. Disabling it (rather than warning after the fact) makes
		# the inconsistency impossible instead of just visible.
		popup.set_item_disabled(popup.get_item_index(entry["cycle_id"]),
				Settings.form_up_dist_default == entry["mode"])
	# The default can also become excluded the other way: the player narrows the cycle to one
	# OTHER mode, then later switches the default radio to the excluded one. Guarantee the
	# current default is always in the cycle, and re-check its (now-disabled) box directly —
	# not via the Settings.changed signal this setter emits, since the very first call here
	# (from _ready, before the signal is connected) must also self-correct synchronously.
	if not Settings.form_up_dist_cycle.has(Settings.form_up_dist_default):
		var cycle: Array = Settings.form_up_dist_cycle.duplicate()
		cycle.append(Settings.form_up_dist_default)
		Settings.form_up_dist_cycle = SelectionManagerRef.FORM_UP_DIST_CYCLE.filter(
				func(m) -> bool: return cycle.has(m))
		for entry in _FORMUP_ENTRIES:
			popup.set_item_checked(popup.get_item_index(entry["cycle_id"]),
					Settings.form_up_dist_cycle.has(entry["mode"]))
	popup.set_item_checked(popup.get_item_index(MENU_REFORM_BEFORE_MOVE),
			Settings.reform_before_move)
	popup.set_item_checked(popup.get_item_index(MENU_WALK_ADVANCE),
			Settings.walk_advance)
	popup.set_item_checked(popup.get_item_index(MENU_DISTANCE_LEGEND),
			Settings.show_distance_legend)
	popup.set_item_checked(popup.get_item_index(MENU_ORDER_DISTANCE),
			Settings.show_order_distance)
	popup.set_item_checked(popup.get_item_index(MENU_UNIT_SPEED),
			Settings.show_unit_speed)
	popup.set_item_checked(popup.get_item_index(MENU_SOLDIER_IDS),
			Settings.show_soldier_ids)
	popup.set_item_checked(popup.get_item_index(MENU_ENGAGED_HIGHLIGHT),
			Settings.show_engaged_highlight)
	popup.set_item_checked(popup.get_item_index(MENU_POSITION_ANCHOR),
			Settings.show_position_anchor)
	popup.set_item_checked(popup.get_item_index(MENU_SHOW_FPS), Settings.show_fps)
	for entry in _FPS_CORNER_ENTRIES:
		popup.set_item_checked(popup.get_item_index(entry["id"]),
				Settings.fps_corner == entry["corner"])
	_sync_distance_legend_visibility()
	_sync_fps_label()
	_ctrl_bar_sync_settings()


## Rebuild the controls hint, rendering the order-mode keys from the live Settings
## bindings so the bar reflects rebinds instead of the hardcoded defaults.
func _refresh_hint() -> void:
	if _hint == null:
		return
	var keys: String = ""
	for entry in BattleRef.ORDER_MODE_HOTKEYS:
		if keys != "":
			keys += "/"
		keys += OS.get_keycode_string(Settings.order_binding(entry["slug"]))
	_hint.text = "LMB select / drag-box   •   RMB move or attack   •   Shift+RMB add waypoint   •   %s order mode (Esc clear)   •   T formation (Tight/Loose/Square/Normal)   •   O orbis / Shift+O schiltron   •   WASD / two-finger pan   •   wheel / pinch zoom   •   P pause   •   hold Space show orders" % keys


## Dispatch a Menu popup selection by its stable item id.
func _on_menu_id(id: int) -> void:
	# Dispatched via a table scan ahead of the match: match's case list is static, so it
	# can't loop over _FORMUP_ENTRIES the way this scan does -- one case per entry would
	# defeat the point of the table.
	for entry in _FORMUP_ENTRIES:
		if id == entry["default_id"]:
			# Settings.changed -> _sync_setting_toggles re-checks the radios.
			Settings.form_up_dist_default = entry["mode"]
			return
		if id == entry["cycle_id"]:
			_toggle_form_up_cycle(entry["mode"])
			return
	for entry in _FPS_CORNER_ENTRIES:
		if id == entry["id"]:
			# Settings.changed -> _sync_setting_toggles re-checks the radios and repositions
			# the label via _sync_fps_label.
			Settings.fps_corner = entry["corner"]
			return
	match id:
		MENU_RESTART:
			_on_restart()
		MENU_RESTART_REPLAY:
			_on_restart_replay()
		MENU_LOAD:
			_open_load_dialog()
		MENU_EDGE_SCROLL:
			# Flip the setting; Settings.changed -> _sync_setting_toggles re-checks it.
			Settings.edge_scroll = not Settings.edge_scroll
		MENU_SFX:
			Settings.sfx_enabled = not Settings.sfx_enabled
		MENU_REFORM_BEFORE_MOVE:
			Settings.reform_before_move = not Settings.reform_before_move
		MENU_WALK_ADVANCE:
			Settings.walk_advance = not Settings.walk_advance
		MENU_DISTANCE_LEGEND:
			# Settings.changed -> _sync_setting_toggles -> _sync_distance_legend_visibility,
			# same as every other menu toggle here.
			Settings.show_distance_legend = not Settings.show_distance_legend
		MENU_ORDER_DISTANCE:
			Settings.show_order_distance = not Settings.show_order_distance
		MENU_UNIT_SPEED:
			Settings.show_unit_speed = not Settings.show_unit_speed
		MENU_SOLDIER_IDS:
			Settings.show_soldier_ids = not Settings.show_soldier_ids
		MENU_ENGAGED_HIGHLIGHT:
			Settings.show_engaged_highlight = not Settings.show_engaged_highlight
		MENU_POSITION_ANCHOR:
			Settings.show_position_anchor = not Settings.show_position_anchor
		MENU_SHOW_FPS:
			Settings.show_fps = not Settings.show_fps
		MENU_KEYBINDINGS:
			_keybindings_dialog.popup_centered()
		MENU_SHORTCUTS:
			_shortcuts_dialog.popup_centered()
		MENU_QUIT_TO_MENU:
			_on_quit_to_menu()


func _toggle_form_up_cycle(mode: int) -> void:
	var enabled: Array = Settings.form_up_dist_cycle.duplicate()
	if enabled.has(mode):
		# The menu item is disabled for the current default (see _sync_setting_toggles), so
		# this normally can't fire for it; guard anyway since it's cheap and keeps the
		# invariant (default stays reachable by Y) true regardless of how this is reached.
		if mode == Settings.form_up_dist_default:
			_sync_setting_toggles()
			return
		enabled.erase(mode)
		# Keep at least one mode so the UI and Y-key behavior stay consistent.
		# (An empty cycle falls back silently to all modes in SelectionManager,
		# which would leave the checkboxes unchecked while Y still cycles both.)
		if enabled.is_empty():
			_sync_setting_toggles()   # Godot already auto-toggled before id_pressed; restore the checkbox
			return
	else:
		enabled.append(mode)
	# Rebuild in canonical order so the Y-key sequence is predictable regardless of
	# the order modes were checked/unchecked.
	Settings.form_up_dist_cycle = SelectionManagerRef.FORM_UP_DIST_CYCLE.filter(
			func(m) -> bool: return enabled.has(m))


const _TICK_RATE_SAMPLE_SECONDS := 1.0


func _process(delta: float) -> void:
	_update_distance_legend()
	_tick_rate_window += delta
	if _tick_rate_window >= _TICK_RATE_SAMPLE_SECONDS:
		_live_tick_rate = _tick_count / _tick_rate_window
		_tick_count = 0
		_tick_rate_window = 0.0
	_update_fps_label()


func _on_physics_tick() -> void:
	_tick_count += 1


func _unhandled_input(event: InputEvent) -> void:
	# P toggles active pause: the sim freezes but selection and camera stay
	# live (they run as PROCESS_MODE_ALWAYS), so orders can be queued while paused
	# and apply on resume. Disabled once the end-of-battle overlay is up.
	if _is_pause_keypress(event) and not _overlay.visible:
		_toggle_pause()
	elif _is_shortcuts_keypress(event) and not _overlay.visible:
		_shortcuts_dialog.popup_centered()
		get_viewport().set_input_as_handled()


## Shift+/ produces "?" on a standard layout; physical_keycode (the / key) keeps the
## binding layout-independent, like the pause/edge-scroll keys. Same shape as
## _is_pause_keypress -- Shift carries the second meaning of an otherwise-plain key.
func _is_shortcuts_keypress(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	return event.physical_keycode == KEY_SLASH and event.shift_pressed


func _is_pause_keypress(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	# P toggles pause; Shift+Space does too (plain Space is reserved for the
	# hold-to-show-orders overlay, so it must carry Shift to mean "pause"). Use
	# physical_keycode so the binding is layout-independent and unaffected by the
	# held modifier. Shift+Space is used rather than Ctrl+Space because macOS
	# reserves Ctrl+Space for input-source switching, so it never reaches the app.
	if event.physical_keycode == KEY_P:
		return true
	return event.physical_keycode == KEY_SPACE and event.shift_pressed


func _toggle_pause() -> void:
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	_paused_label.visible = paused
	get_viewport().set_input_as_handled()


func show_unit(u, group_count: int) -> void:
	if u == null or not is_instance_valid(u):
		clear_unit()
		return
	var extra: String = "" if group_count <= 1 else "  (+%d more)" % (group_count - 1)
	var kind: String
	if u.is_cavalry:
		kind = "Cavalry"
	elif u.anti_cavalry:
		kind = "Spearmen"
	elif u.is_ranged:
		kind = "Archers"
	else:
		kind = "Infantry"
	var cohesion_text: String = "" if u.cohesion >= 1.0 \
			else "  Cohesion: %d%%" % mini(roundi(u.cohesion * 100.0), 99)
	var training_text: String = "" if u.training <= 0.0 \
			else "  Training: %d%%" % clampi(roundi(u.training * 100.0), 1, 100)
	_info.text = "%s%s\nType: %s  Commander: %s\nSoldiers: %d / %d\nMorale: %d  Fatigue: %d%%%s%s\nFormation: %s  Width: %s  Order: %s" % [
		u.unit_name, extra, kind, OfficerRank.title_for(u), u.soldiers, u.max_soldiers, int(u.morale), int(u.fatigue),
		cohesion_text, training_text, u.formation_summary(), UnitFormation.files_label(UnitFormation.frontage(u)),
		u.order_summary()
	]
	_rebuild_order_tree(u)
	if _ctrl_bar != null:
		_ctrl_bar.visible = true
		_info_panel_raise()
		_ctrl_bar_update_formation(u)
		_ctrl_bar_update_stance(_sel_mgr.get_armed_mode() if _sel_mgr != null else 0)
		update_group_attack_mode(_sel_mgr.get_group_attack_mode() if _sel_mgr != null else 0)


func clear_unit() -> void:
	_info.text = "No unit selected"
	_rebuild_order_tree(null)
	if _ctrl_bar != null:
		_ctrl_bar.visible = false
		_info_panel_lower()


# --- Order-tree display (docs/atomic-order-decomposition-design.md, "HUD: the tree
# renders naturally") ---------------------------------------------------------------
# The stats panel's plain "Order: <order_summary()>" line above stays exactly as it was --
# it's the human-readable one-liner ("Attacking X", "Wheeling", ...) and doesn't touch Order
# state directly. This section renders the actual order tree underneath it: current_order's
# own describe() as the top row, its children (if any) indented recursively, the leaf
# Unit._think is actually driving highlighted, and a collapse toggle on any composite node.
# A leaf-only current_order (no children -- the common case today) is just that one row, with
# no toggle and no indentation: the tree adds nothing visible beyond the single top row until
# an order actually decomposes.

## Flattens the order tree rooted at `order` into display rows, depth-first pre-order: each
## row is {"order": Order, "depth": int, "path": String, "has_children": bool}. `path` is a
## dot-joined chain of child indices from the root ("0", "0.1", "0.1.0", ...) -- a stable key
## into `expanded` that survives the per-frame rebuild _rebuild_order_tree does (unlike the
## transient Order/Control instances). A composite node collapsed in `expanded` stops the
## walk there -- its children are omitted from the returned rows entirely, not just hidden.
## Pure and UI-free so it's directly unit-testable against plain Order trees.
func _order_tree_rows(order, expanded: Dictionary, depth: int = 0, path: String = "0") -> Array:
	if order == null:
		return []
	var has_children: bool = not order.children.is_empty()
	var rows: Array = [{"order": order, "depth": depth, "path": path, "has_children": has_children}]
	if has_children and expanded.get(path, true):
		for i in order.children.size():
			rows.append_array(_order_tree_rows(order.children[i], expanded, depth + 1, "%s.%d" % [path, i]))
	return rows


## Snapshot of exactly what a row list would render: for each row, the path (which already
## encodes the owning unit's instance id -- see the root_path built in _rebuild_order_tree --
## so a change of selected unit always changes the signature), whether it shows a toggle vs a
## blank gap, its describe() text, and whether it's highlighted as the active leaf. Two calls
## that produce equal signatures render identically, so _rebuild_order_tree can skip rebuilding
## the Controls entirely on the second call. Deliberately NOT keyed on Order instance identity:
## a leaf order being replaced by a new one that happens to describe() the same (same type,
## phase, guard) still renders identically, so treating that as "unchanged" is correct, not a
## missed update.
func _order_tree_row_signature(rows: Array, leaf) -> Array:
	var sig: Array = []
	for row: Dictionary in rows:
		var order = row["order"]
		sig.append([row["path"], row["has_children"], order.describe(), order == leaf])
	return sig


## Rebuilds the order-tree rows against `u.current_order` -- called every time show_unit()/
## clear_unit() runs (SelectionManager._refresh_hud() drives that every frame for the selected
## unit), so the tree always reflects the live _active_child cursor. Actually tearing down and
## recreating the row Controls is skipped whenever the rows would render identically to last
## time (see _order_tree_row_signature): rebuilding on every one of those per-frame calls
## regardless of whether anything changed would queue_free() and recreate the expand/collapse
## toggle Buttons even when nothing about the tree changed. Since a real mouse click's
## press-then-release can straddle more than one frame, and Godot's BaseButton only fires
## `pressed` when both land on the SAME Button instance, doing that would silently break the
## toggle: the down click's instance is gone by the time the up click lands on its freshly
## rebuilt replacement, so `pressed` never fires. Skipping the rebuild when nothing changed
## keeps the toggle Buttons -- and every other row Control -- alive across those frames.
func _rebuild_order_tree(u) -> void:
	if u == null or not is_instance_valid(u) or u.current_order == null:
		if _order_tree_last_signature == null:
			return   # already empty/hidden from a previous call (or never built) -- nothing to do
		for row_node in _order_tree_box.get_children():
			row_node.queue_free()
		_order_tree_box.visible = false
		_order_tree_last_signature = null
		return
	var leaf = u.active_leaf()
	var root_path := "%d:0" % u.get_instance_id()
	var rows: Array = _order_tree_rows(u.current_order, _order_tree_expanded, 0, root_path)
	var signature := _order_tree_row_signature(rows, leaf)
	if signature == _order_tree_last_signature:
		return   # would render identically to what's already there -- keep the existing Controls
	_order_tree_last_signature = signature
	for row_node in _order_tree_box.get_children():
		# remove_child before queue_free, not queue_free alone: queue_free defers removal to
		# the end of THIS frame, so the old rows would still be in get_children() when the new
		# ones are add_child'ed two lines down -- a VBoxContainer showing both generations at
		# once for one frame (e.g. collapsing 3 rows to 1 would transiently render 4).
		_order_tree_box.remove_child(row_node)
		row_node.queue_free()
	_order_tree_box.visible = true
	for row: Dictionary in rows:
		_order_tree_box.add_child(_build_order_tree_row(row, leaf))


## One row: depth-indent spacer, an expand/collapse toggle for a composite node (a same-width
## blank spacer for a leaf, so every row's label lines up in the same column regardless of
## whether its siblings have children), then the describe() label -- highlighted in the same
## amber _order_mode_label uses for "the order currently in effect" when `order` is the
## active leaf Unit._think is actually driving.
func _build_order_tree_row(row: Dictionary, leaf) -> Control:
	var order = row["order"]
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	if row["depth"] > 0:
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(row["depth"] * _ORDER_TREE_INDENT, 0)
		hbox.add_child(indent)
	if row["has_children"]:
		var toggle := Button.new()
		toggle.flat = true
		toggle.custom_minimum_size = Vector2(_ORDER_TREE_TOGGLE_WIDTH, 0)
		toggle.add_theme_font_size_override("font_size", 12)
		var path: String = row["path"]
		toggle.text = "▾" if _order_tree_expanded.get(path, true) else "▸"
		toggle.pressed.connect(_on_order_tree_toggle.bind(path))
		hbox.add_child(toggle)
	else:
		var toggle_gap := Control.new()
		toggle_gap.custom_minimum_size = Vector2(_ORDER_TREE_TOGGLE_WIDTH, 0)
		hbox.add_child(toggle_gap)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	var is_active_leaf: bool = order == leaf
	lbl.text = "▶ %s" % order.describe() if is_active_leaf else order.describe()
	if is_active_leaf:
		lbl.add_theme_color_override("font_color", _ORDER_TREE_ACTIVE_COLOR)
	hbox.add_child(lbl)
	return hbox


func _on_order_tree_toggle(path: String) -> void:
	_order_tree_expanded[path] = not _order_tree_expanded.get(path, true)


## Show the armed order mode. Empty text hides the indicator (default stance).
func set_order_mode(text: String, mode: int = BattleRef.OrderMode.NORMAL) -> void:
	if text == "":
		_order_mode_label.visible = false
	else:
		_order_mode_label.text = "Order: %s" % text
		_order_mode_label.visible = true
	_ctrl_bar_update_stance(mode)


## Briefly show a one-line toast, then auto-hide it. Used for transient feedback like the
## form-up distribution cycle. A fresh call supersedes any toast still showing (the newer
## text wins, so the older timer's hide is a no-op).
const FLASH_SECONDS := 1.3
func flash_message(text: String) -> void:
	_flash_label.text = text
	_flash_label.visible = true
	# process_always so it ticks while the sim is paused (orders/cycles work paused too).
	var timer := get_tree().create_timer(FLASH_SECONDS, true)
	timer.timeout.connect(_hide_flash.bind(text))


## Hide the toast unless a newer flash_message() has since replaced its text. Guarded against
## a freed label so a deferred timer can't touch this HUD after a scene reload.
func _hide_flash(text: String) -> void:
	if is_instance_valid(_flash_label) and _flash_label.text == text:
		_flash_label.visible = false


## Reflect the current group-order distribution mode on the ctrl bar button --
## spreads a multi-unit attack across nearby enemies, or a multi-unit line-relief
## across nearby engaged friendlies (Focused sends every ordered unit at the one
## target clicked either way).
func update_group_attack_mode(mode: int) -> void:
	if _ctrl_group_attack_btn == null:
		return
	var labels := {
		BattleRef.GroupAttackMode.FOCUSED: "Focused",
		BattleRef.GroupAttackMode.DISTRIBUTED: "Spread",
	}
	_ctrl_group_attack_btn.text = labels.get(mode, "Group mode")


func _ctrl_bar_sync_settings() -> void:
	if _ctrl_reform_btn == null:
		return
	_ctrl_reform_btn.button_pressed = Settings.reform_before_move


# --- Distance legend (map scale bar, #364) ----------------------------------
# A small semi-translucent panel in the bottom-right corner showing the battlefield's
# real metre scale at the current camera zoom (DistanceLegend has the pure math). Bottom-
# left is the selected-unit info panel and bottom-center is the control bar, so bottom-
# right is the free corner.

const _LEGEND_MARGIN := Vector2(14.0, 14.0)
const _LEGEND_BAR_HEIGHT := 6.0
const _LEGEND_PAD := 10.0

func _build_distance_legend() -> void:
	_legend_panel = PanelContainer.new()
	_legend_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_legend_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_legend_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legend_panel.position = -_LEGEND_MARGIN   # offset off the corner; grows up-and-left from here
	_legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Semi-translucent panel background (distinct from the opaque default panel style),
	# per #364's spec -- the battlefield should stay visible through it.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(_LEGEND_PAD)
	_legend_panel.add_theme_stylebox_override("panel", style)
	add_child(_legend_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_legend_panel.add_child(col)

	_legend_bar = ColorRect.new()
	_legend_bar.color = Color(1, 1, 1, 0.9)
	_legend_bar.custom_minimum_size = Vector2(DistanceLegend.MIN_PX, _LEGEND_BAR_HEIGHT)
	col.add_child(_legend_bar)

	_legend_label = Label.new()
	_legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend_label.add_theme_font_size_override("font_size", 13)
	_legend_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	col.add_child(_legend_label)

	_sync_distance_legend_visibility()


func _sync_distance_legend_visibility() -> void:
	if _legend_panel == null:
		return
	_legend_panel.visible = Settings.show_distance_legend
	if _legend_panel.visible:
		_legend_last_zoom = -1.0   # force an immediate resync; _process only updates on change


## Re-measure the bar against the live camera zoom each frame, but cheaply: skip the work
## entirely when the zoom hasn't moved (the common case while the player isn't scrolling).
func _update_distance_legend() -> void:
	if _legend_panel == null or not _legend_panel.visible:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if is_equal_approx(cam.zoom.x, _legend_last_zoom):
		return
	_legend_last_zoom = cam.zoom.x
	var mpp: float = DistanceLegend.metres_per_pixel(cam.zoom.x, BattleRef.WORLD_UNITS_PER_METER)
	var metres: float = DistanceLegend.pick_round_metres(mpp)
	_legend_bar.custom_minimum_size.x = DistanceLegend.bar_width_px(metres, mpp)
	_legend_label.text = DistanceLegend.label_text(metres)


# --- Frame-rate counter -----------------------------------------------------
# A one-line readout of render FPS (Engine.get_frames_per_second()) and the live-measured
# physics tick rate (_live_tick_rate, below -- distinct from the target
# Engine.physics_ticks_per_second, since a large battle can fall behind it), user-placeable
# in any of the four screen corners (Settings.fps_corner / _FPS_CORNER_ENTRIES above).

const _FPS_MARGIN := Vector2(14.0, 10.0)
# The always-on controls hint (top-left, single line at y=10, font size 14) runs the full
# width of the top edge, so a top-anchored FPS label needs to clear it vertically or the
# two overlap the instant the counter is turned on.
const _FPS_TOP_MARGIN_Y := 34.0


func _build_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)
	_sync_fps_label()


## Show/hide the frame-rate label and (re)anchor it to Settings.fps_corner. Grow direction
## is set opposite the anchored edge on each axis so the label doesn't drift as its digit
## count changes ("9" -> "144") -- same reasoning as the distance legend's grow_horizontal/
## grow_vertical = GROW_DIRECTION_BEGIN for its bottom-right anchor.
func _sync_fps_label() -> void:
	if _fps_label == null:
		return
	_fps_label.visible = Settings.show_fps
	if not _fps_label.visible:
		return
	var corner: int = Settings.fps_corner
	var left: bool = (corner == Settings.FPS_CORNER_TOP_LEFT
			or corner == Settings.FPS_CORNER_BOTTOM_LEFT)
	var top: bool = (corner == Settings.FPS_CORNER_TOP_LEFT
			or corner == Settings.FPS_CORNER_TOP_RIGHT)
	for entry in _FPS_CORNER_ENTRIES:
		if entry["corner"] == corner:
			_fps_label.set_anchors_preset(entry["preset"])
			break
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_END if left else Control.GROW_DIRECTION_BEGIN
	_fps_label.grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN
	var top_margin: float = _FPS_TOP_MARGIN_Y if top else _FPS_MARGIN.y
	_fps_label.position = Vector2(
			_FPS_MARGIN.x if left else -_FPS_MARGIN.x,
			top_margin if top else -_FPS_MARGIN.y)
	_update_fps_label()


func _update_fps_label() -> void:
	if _fps_label == null or not _fps_label.visible:
		return
	_fps_label.text = "%d FPS · %d ticks/s" % [Engine.get_frames_per_second(), roundi(_live_tick_rate)]


func _ctrl_bar_refresh_stance_popup() -> void:
	if _ctrl_stance_btn == null:
		return
	var popup := _ctrl_stance_btn.get_popup()
	for entry: Dictionary in _STANCE_ENTRIES:
		var item_id: int = entry["id"]
		popup.set_item_text(popup.get_item_index(item_id), _stance_item_text(entry))


func _ctrl_bar_update_formation(unit) -> void:
	if _ctrl_formation_btn == null or unit == null or not is_instance_valid(unit):
		return
	_ctrl_formation_btn.text = _FORMATION_NAMES.get(unit.formation_mode, "Formation") + " ▾"


func _ctrl_bar_update_stance(mode: int) -> void:
	if _ctrl_stance_btn == null:
		return
	_ctrl_stance_btn.text = _stance_label_for_mode(mode) + " ▾"


## The hotkey label shown next to a stance item: "Esc" for the fixed Normal
## entry (no rebindable slug), else the player's current binding for its slug.
func _stance_key_str(entry: Dictionary) -> String:
	var slug: String = entry["slug"]
	if slug == "":
		return "Esc"
	return OS.get_keycode_string(Settings.order_binding(slug))


## Full menu text for a stance entry: "Label  (Key)".
func _stance_item_text(entry: Dictionary) -> String:
	return "%s  (%s)" % [entry["label"], _stance_key_str(entry)]


## The display label for an OrderMode, used as the stance button caption.
## Falls back to "Normal" for an unmapped mode, matching the previous behavior.
func _stance_label_for_mode(mode: int) -> String:
	for entry: Dictionary in _STANCE_ENTRIES:
		if entry["mode"] == mode:
			return entry["label"]
	return "Normal"


## Build the bottom control bar: formation, stance, and per-order options.
func _build_ctrl_bar() -> void:
	_ctrl_bar = PanelContainer.new()
	_ctrl_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ctrl_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ctrl_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ctrl_bar.position = Vector2(0, -10)
	_ctrl_bar.visible = false
	add_child(_ctrl_bar)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 8)
	outer.add_theme_constant_override("margin_right", 8)
	outer.add_theme_constant_override("margin_top", 6)
	outer.add_theme_constant_override("margin_bottom", 6)
	_ctrl_bar.add_child(outer)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	outer.add_child(hbox)

	hbox.add_child(_build_ctrl_section("Formation", _build_ctrl_formation_menu()))
	hbox.add_child(VSeparator.new())
	hbox.add_child(_build_ctrl_section("Stance", _build_ctrl_stance_menu()))
	hbox.add_child(VSeparator.new())
	hbox.add_child(_build_ctrl_section("Options", _build_ctrl_option_buttons()))

	_ctrl_bar_sync_settings()
	update_group_attack_mode(BattleRef.GroupAttackMode.FOCUSED)


func _build_ctrl_section(label_text: String, content: Control) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vbox.add_child(lbl)
	vbox.add_child(content)
	return vbox


func _build_ctrl_formation_menu() -> Control:
	_ctrl_formation_btn = MenuButton.new()
	_ctrl_formation_btn.text = "Normal ▾"
	_ctrl_formation_btn.custom_minimum_size = Vector2(90, 28)
	_ctrl_formation_btn.add_theme_font_size_override("font_size", 13)
	var popup := _ctrl_formation_btn.get_popup()
	for mode: int in _FORMATION_MENU_ORDER:
		popup.add_item(_FORMATION_NAMES[mode], mode)
		popup.set_item_metadata(popup.get_item_index(mode), mode)
	popup.about_to_popup.connect(_reposition_dropup.bind(popup, _ctrl_formation_btn))
	popup.id_pressed.connect(_on_formation_popup_id)
	return _ctrl_formation_btn


func _build_ctrl_stance_menu() -> Control:
	_ctrl_stance_btn = MenuButton.new()
	_ctrl_stance_btn.text = "Normal ▾"
	_ctrl_stance_btn.custom_minimum_size = Vector2(110, 28)
	_ctrl_stance_btn.add_theme_font_size_override("font_size", 13)
	var popup := _ctrl_stance_btn.get_popup()
	# NORMAL (Esc) is fixed and not rebindable; the other entries show their
	# current keybinding. _STANCE_ENTRIES drives all three stance sites.
	for entry: Dictionary in _STANCE_ENTRIES:
		var item_id: int = entry["id"]
		popup.add_item(_stance_item_text(entry), item_id)
		popup.set_item_metadata(popup.get_item_index(item_id), entry["mode"])
	popup.about_to_popup.connect(_reposition_dropup.bind(popup, _ctrl_stance_btn))
	popup.id_pressed.connect(_on_stance_popup_id)
	return _ctrl_stance_btn


func _reposition_dropup(popup: PopupMenu, btn: Control) -> void:
	# Defer so Godot finishes its first layout pass before we read popup.size.
	(func():
		popup.position = Vector2i(
			int(btn.global_position.x),
			int(btn.global_position.y) - popup.size.y
		)).call_deferred()


func _on_formation_popup_id(id: int) -> void:
	if _sel_mgr != null:
		_sel_mgr.set_formation_to(id)
	_ctrl_formation_btn.text = _FORMATION_NAMES.get(id, "Formation") + " ▾"


func _on_stance_popup_id(id: int) -> void:
	var popup := _ctrl_stance_btn.get_popup()
	var mode: int = popup.get_item_metadata(popup.get_item_index(id))
	if _sel_mgr != null:
		_sel_mgr.arm_order_mode(mode)


func _info_panel_raise() -> void:
	if _info_panel == null or _ctrl_bar == null:
		return
	var bar_h := _ctrl_bar.get_combined_minimum_size().y
	# offset_top/offset_bottom, not position: _info_panel is anchored bottom-left
	# (anchor_top == anchor_bottom == 1), so offset_top/offset_bottom ARE the pixel
	# distances from that anchor line -- exactly what this raise/lower math wants
	# ("translate the whole panel N px above the bottom edge"). Control.position, in
	# contrast, resolves anchors against the CURRENT parent size at the moment it's
	# set: called once from _ready() (before the CanvasLayer's viewport size is
	# established, so anchor*parent_size == 0) it happens to equal the offset and
	# "just works" -- but _process()'s per-frame SelectionManager._refresh_hud() ->
	# show_unit()/clear_unit() calls this every frame, by which point the real
	# viewport size (not 0) is baked into the anchor math, so `position=` silently
	# shoves the panel hundreds of pixels off the top of the screen instead of the
	# few pixels intended. offset_top/offset_bottom have no such ambiguity: they're
	# always anchor-relative, keeping the panel on screen at every call site. Both
	# are moved by the same raise_amount here so the panel translates as a rigid
	# rectangle -- clearing the control bar beneath it -- rather than stretching
	# taller with its bottom edge fixed.
	var raise_amount := bar_h + 8.0
	_info_panel.set_deferred("offset_top", -(PANEL_MIN.y + PANEL_BOTTOM_GAP + raise_amount))
	_info_panel.set_deferred("offset_bottom", -(PANEL_BOTTOM_GAP + raise_amount))


func _info_panel_lower() -> void:
	if _info_panel == null:
		return
	_info_panel.set_deferred("offset_top", -(PANEL_MIN.y + PANEL_BOTTOM_GAP))
	_info_panel.set_deferred("offset_bottom", -PANEL_BOTTOM_GAP)


func _build_ctrl_option_buttons() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	_ctrl_reform_btn = Button.new()
	_ctrl_reform_btn.text = "Reform"
	_ctrl_reform_btn.toggle_mode = true
	_ctrl_reform_btn.custom_minimum_size = Vector2(68, 28)
	_ctrl_reform_btn.add_theme_font_size_override("font_size", 13)
	_ctrl_reform_btn.pressed.connect(func():
		Settings.reform_before_move = not Settings.reform_before_move)
	hbox.add_child(_ctrl_reform_btn)

	_ctrl_group_attack_btn = Button.new()
	_ctrl_group_attack_btn.custom_minimum_size = Vector2(100, 28)
	_ctrl_group_attack_btn.add_theme_font_size_override("font_size", 13)
	_ctrl_group_attack_btn.pressed.connect(func():
		if _sel_mgr != null:
			_sel_mgr.toggle_group_attack_mode())
	hbox.add_child(_ctrl_group_attack_btn)

	return hbox


func show_end(text: String) -> void:
	_paused_label.visible = false   # the end overlay supersedes the pause banner
	_order_mode_label.visible = false   # armed-mode indicator is irrelevant on the end screen
	_overlay_label.text = text
	_overlay.visible = true
	get_tree().paused = true


## Inverse of show_end, for a replay rewind that jumps back before the battle's
## conclusion: the end overlay comes down and the tree resumes ticking.
func hide_end() -> void:
	_overlay.visible = false
	get_tree().paused = false


func _on_restart() -> void:
	# Fresh battle: drop back to IDLE so Battle._ready starts a new recording.
	Replay.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_return_to_campaign() -> void:
	# Hand control back to the campaign map; CampaignBattle still holds the
	# result, which CampaignMap applies on load.
	_confirm_exit_with_unsaved_replay(_finish_return_to_campaign)


func _finish_return_to_campaign() -> void:
	Replay.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Campaign.tscn")


## Drop the in-progress recording and unpause, same prelude _on_restart/_finish_return_to_campaign
## use before their own transition -- split out here (rather than inlined like theirs) so it's
## directly testable without triggering _on_quit_to_menu's real change_scene_to_file, which
## this codebase deliberately doesn't unit test (see test_main_menu.gd's own note on why).
func _reset_for_quit_to_menu() -> void:
	Replay.reset()
	get_tree().paused = false


func _on_quit_to_menu() -> void:
	# Bail out of the battle entirely — the only way back to the menu from a drill-mode
	# rehearsal, which never auto-ends. MainMenu._ready() clears CampaignBattle/ParadeGround
	# defensively, so no in-flight hand-off is left dangling.
	_confirm_exit_with_unsaved_replay(_finish_quit_to_menu)


func _finish_quit_to_menu() -> void:
	_reset_for_quit_to_menu()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


## Offers to save the in-progress recording before an exit that would otherwise discard it
## silently. Covers every exit path that doesn't go through Battle._end()'s own auto-save --
## a mid-battle "Quit to Main Menu"/"Return to Campaign", and (since drill-mode/parade-ground
## battles never auto-end) that as the *only* way out of one. A battle that already reached
## its formal end has Replay.last_saved_path already set by that auto-save, so this no-ops
## straight to on_resolved -- nothing to re-save, no redundant prompt on top of one that
## already happened.
func _confirm_exit_with_unsaved_replay(on_resolved: Callable) -> void:
	if Replay.mode != Replay.Mode.RECORD or Replay.last_saved_path != "":
		on_resolved.call()
		return
	_pending_exit_action = on_resolved
	_save_replay_dialog.popup_centered()


func _on_save_replay_confirmed() -> void:
	var battle := get_parent() as BattleRef
	if battle != null:
		Replay.save("Quit (unfinished)", battle.current_tick())
	_pending_exit_action.call()


func _on_save_replay_custom_action(action: StringName) -> void:
	if action == "discard":
		_save_replay_dialog.hide()
		_pending_exit_action.call()


func _on_restart_replay() -> void:
	# Rewind the watched replay to tick 0: start_playback re-reads loaded_path and
	# resets the play index, then the scene reload replays from the start. PLAYBACK
	# only (the menu item is disabled otherwise); guarded in case it's reached anyway.
	if Replay.mode != Replay.Mode.PLAYBACK:
		return
	if not Replay.start_playback(Replay.loaded_path):
		# Loaded fine on entering PLAYBACK, so a failure now means it vanished
		# mid-watch — report it like _on_replay_chosen rather than bailing silently.
		_error_dialog.title = "Restart Replay"
		_error_dialog.dialog_text = "That replay is no longer available."
		_error_dialog.popup_centered()
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func _open_load_dialog() -> void:
	_load_dialog.current_dir = Replay.replays_dir()
	_load_dialog.popup_centered()


func _on_replay_chosen(path: String) -> void:
	if not Replay.start_playback(path):
		# Bad/incompatible file — report it without clobbering any result label.
		_error_dialog.title = "Load Replay"
		_error_dialog.dialog_text = "That file isn't a compatible replay."
		_error_dialog.popup_centered()
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_watch_replay() -> void:
	# Re-run the battle just shown. While watching a replay, "Watch Again" must
	# re-run *that* file (loaded_path) — which may be an older one opened via the
	# picker — not the last live battle. After a live battle, replay what we just
	# saved. If neither exists, say so rather than playing the wrong battle.
	var path := Replay.loaded_path if Replay.mode == Replay.Mode.PLAYBACK else Replay.last_saved_path
	if path == "" or not Replay.start_playback(path):
		# Report on the button itself so the battle result label is preserved.
		_watch_button.text = "No replay available"
		_watch_button.disabled = true
		return
	get_tree().paused = false
	get_tree().reload_current_scene()
