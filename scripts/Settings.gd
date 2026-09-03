extends Node
## Game-wide settings (autoload singleton: "Settings").
## Persists to user://settings.cfg so choices survive between runs.

const SAVE_PATH := "user://settings.cfg"
const SettingsKeybindingsRef = preload("res://scripts/SettingsKeybindings.gd")
const SettingsStorageRef = preload("res://scripts/SettingsStorage.gd")

signal changed

# True while _load() applies persisted values, so the setter doesn't
# round-trip back to disk or fire `changed` during startup.
var _loading: bool = false

# Pan the camera when the mouse touches a screen edge. Default off.
var edge_scroll: bool = false:
	set(value):
		if value == edge_scroll:
			return
		edge_scroll = value
		if not _loading:
			_save()
			changed.emit()

# Play sound effects (combat, selection, orders, battle outcome). Default off.
var sfx_enabled: bool = false:
	set(value):
		if value == sfx_enabled:
			return
		sfx_enabled = value
		if not _loading:
			_save()
			changed.emit()

# Multi-unit drag-to-form-up: how the dragged flank line is split among the selected units,
# along two independent axes -- which dimension is held equal (depth/width) and which basis
# it's held equal in (space = physical world units; count = a plain integer rank/file count).
# Stored as an int (mirrors SelectionManager.FormUpDist) so Settings stays free of a
# dependency on that script. This is the DEFAULT a battle starts with; an on-the-fly hotkey
# cycles the live mode without rewriting this. The values are append-only: EQUAL_DEPTH/
# EQUAL_WIDTH keep their original 0/1 so an existing player's persisted choice doesn't
# silently change meaning. Bump FORM_UP_DIST_MAX when a mode is added.
const FORM_UP_DIST_EQUAL_DEPTH := 0
const FORM_UP_DIST_EQUAL_WIDTH := 1
const FORM_UP_DIST_EQUAL_DEPTH_SPACE := 2
const FORM_UP_DIST_EQUAL_WIDTH_COUNT := 3
# CHECKERBOARD (docs/acies-triplex-design.md) is a different axis from the four above (which
# historical layout, not which dimension/basis a single line holds equal) but reuses this
# same append-only int range rather than a parallel setting.
const FORM_UP_DIST_CHECKERBOARD := 4
# ECHELON_RIGHT/ECHELON_LEFT (Caesar's oblique deployments, Frederick the Great's oblique
# order at Leuthen): a third axis again -- stagger the line into a diagonal instead of
# picking a straight line's dimension/basis (the four above) or an alternate row layout
# (CHECKERBOARD). RIGHT/LEFT name which flank leads (advances furthest toward the facing
# direction); the other flank trails, refused from contact.
const FORM_UP_DIST_ECHELON_RIGHT := 5
const FORM_UP_DIST_ECHELON_LEFT := 6
const FORM_UP_DIST_MAX := 6
# The setter clamps to the valid range so a corrupt/hand-edited cfg (or a stale value after
# the modes change) can't propagate an out-of-range mode into the game.
var form_up_dist_default: int = FORM_UP_DIST_EQUAL_DEPTH_SPACE:
	set(value):
		var clamped: int = clampi(value, 0, FORM_UP_DIST_MAX)
		if clamped == form_up_dist_default:
			return
		form_up_dist_default = clamped
		if not _loading:
			_save()
			changed.emit()

# Which distribution modes the Y-key cycles through, in cycle order. An int array of
# FORM_UP_DIST_* values; modes absent from the list are skipped when cycling. Persisted
# so players can remove a mode they never use. Default: the original four "single-line"
# modes in canonical order -- CHECKERBOARD and ECHELON_RIGHT/ECHELON_LEFT are deliberately
# left out of the default (each produces a very different layout from a plain line), so a
# player opts in via the menu rather than have one silently appear mid-cycle for an existing
# saved preference.
# Filter out-of-range values on load (see _load) so a stale cfg doesn't break the cycle.
var form_up_dist_cycle: Array = [FORM_UP_DIST_EQUAL_DEPTH_SPACE, FORM_UP_DIST_EQUAL_DEPTH,
		FORM_UP_DIST_EQUAL_WIDTH, FORM_UP_DIST_EQUAL_WIDTH_COUNT]:
	set(value):
		if value == form_up_dist_cycle:
			return
		form_up_dist_cycle = value
		if not _loading:
			_save()
			changed.emit()

# walk_advance and reform_before_move used to live here as global, player-facing toggles
# applied uniformly to every order. They are now genuine per-unit, persistent properties
# (Unit.walk_advance / Unit.reform_before_move), defaulted per unit type at spawn
# (Battle._default_loadout's "walk_advance_default"/"reform_before_move_default" keys) and
# adjustable per-selected-unit via a checkbox in the HUD info panel
# (SelectionManager.set_selected_walk_advance/set_selected_reform_before_move).
# No global fallback remains.

# Distance legend: a semi-translucent map-scale bar in a HUD corner, showing the
# battlefield's real metre scale at the current camera zoom. Cosmetic only. Default on.
var show_distance_legend: bool = true:
	set(value):
		if value == show_distance_legend:
			return
		show_distance_legend = value
		if not _loading:
			_save()
			changed.emit()

# Order-overlay distance label: the metric distance to each order's target, drawn on the
# hold-Space order overlay's move/attack/support lines. Cosmetic only. Default on.
var show_order_distance: bool = true:
	set(value):
		if value == show_order_distance:
			return
		show_order_distance = value
		if not _loading:
			_save()
			changed.emit()

# Order-overlay speed label: each unit's current speed in metres/second, drawn on the
# hold-Space order overlay beside the unit. Cosmetic only. Default off — it's extra
# clutter most players won't want, but handy for tuning/observing pace behaviour.
var show_unit_speed: bool = false:
	set(value):
		if value == show_unit_speed:
			return
		show_unit_speed = value
		if not _loading:
			_save()
			changed.emit()

# Soldier ID overlay: display the per-unit-local array index for each soldier in the
# selected unit at figure LOD (zoomed in). Dev/debug visual only. Default off.
var show_soldier_ids: bool = false:
	set(value):
		if value == show_soldier_ids:
			return
		show_soldier_ids = value
		if not _loading:
			_save()
			changed.emit()

# Engaged-soldier highlight: tint the soldiers Unit.engaged_soldier_indices() currently
# returns (the front ranks, or the live SQUARE/SCHILTRON ring) a distinct color, for every
# engaged unit, at any LOD. Dev/debug visual only. Default off.
var show_engaged_highlight: bool = false:
	set(value):
		if value == show_engaged_highlight:
			return
		show_engaged_highlight = value
		if not _loading:
			_save()
			changed.emit()

# Position-anchor marker: draw a small dot at each unit's `position` -- the regiment's own
# kinematic anchor point (SoldierBodies.couple()), as distinct from where any individual
# soldier body sits. Dev/debug visual only, for verifying the anchor tracks the front rank
# correctly rather than drifting with the block's centroid. Default off.
var show_position_anchor: bool = false:
	set(value):
		if value == show_position_anchor:
			return
		show_position_anchor = value
		if not _loading:
			_save()
			changed.emit()

# Frame-rate counter: display Engine.get_frames_per_second() in a HUD corner. Handy for
# spotting perf regressions. Default off -- most players don't want it as permanent clutter.
var show_fps: bool = false:
	set(value):
		if value == show_fps:
			return
		show_fps = value
		if not _loading:
			_save()
			changed.emit()

# Live performance graph overlay (rolling FPS and tick-rate history). Default off.
var show_performance_graph: bool = false:
	set(value):
		if value == show_performance_graph:
			return
		show_performance_graph = value
		if not _loading:
			_save()
			changed.emit()

# Multi-row unit card tray in HUD. Default off.
var show_unit_card_tray: bool = false:
	set(value):
		if value == show_unit_card_tray:
			return
		show_unit_card_tray = value
		if not _loading:
			_save()
			changed.emit()

# When on, a multi-unit form-up drag deploys the selection from the unit-card tray's 2D
# grid (Line 1 = front rank, columns left-to-right, empty cells = gaps). A single filled
# tray line still only reorders left-to-right under the live FormUpDist mode. Default off.
var tray_row_order_placement: bool = false:
	set(value):
		if value == tray_row_order_placement:
			return
		tray_row_order_placement = value
		if not _loading:
			_save()
			changed.emit()

# Which corner the frame-rate counter renders in. Values are append-only (mirrors
# FORM_UP_DIST_* above) so a persisted choice keeps its meaning if a corner is ever added.
const FPS_CORNER_TOP_LEFT := 0
const FPS_CORNER_TOP_RIGHT := 1
const FPS_CORNER_BOTTOM_LEFT := 2
const FPS_CORNER_BOTTOM_RIGHT := 3
const FPS_CORNER_MAX := 3
# Top-left by default. The distance legend also lives there (on by default), so
# HUD.gd's _sync_fps_label() offsets the frame-rate label below it -- same idea as
# the top-right corner offsetting below the always-on Menu button.
var fps_corner: int = FPS_CORNER_TOP_LEFT:
	set(value):
		var clamped: int = clampi(value, 0, FPS_CORNER_MAX)
		if clamped == fps_corner:
			return
		fps_corner = clamped
		if not _loading:
			_save()
			changed.emit()

# Order-mode selector hotkeys: stable slug -> physical keycode. Slugs (and the
# menu order) are owned by Battle.ORDER_MODE_HOTKEYS; these are the factory defaults.
# Physical keycodes keep the bindings layout-independent (like the camera/pause keys).
const DEFAULT_ORDER_BINDINGS = SettingsKeybindingsRef.DEFAULT_ORDER_BINDINGS

# Active bindings: a copy of the defaults overlaid with any persisted overrides.
# Mutated only via set_order_binding() / reset_order_bindings() so saves + the
# `changed` signal stay centralized.
var order_bindings: Dictionary = DEFAULT_ORDER_BINDINGS.duplicate()


func _ready() -> void:
	_load()


## Set sfx_enabled for this run only — no persist to disk, no `changed` signal
## (reusing the _load() guard). The demo recorder (tools/demo/DemoRunner.gd) calls
## this so a recording carries the game's sound (SFX default off) without rewriting
## a developer's saved preference when the recorder is run locally. Saves/restores
## the prior _loading state rather than hard-clearing it, so it stays correct if
## ever called while a load is already in progress.
func set_sfx_enabled_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	sfx_enabled = value
	_loading = was_loading


## Set show_unit_speed for this run only — no persist to disk, no `changed` signal (same
## _load()-guard trick as set_sfx_enabled_session above). A demo input script can request
## this label on for its recording (so the HUD speed readout is visible in the clip)
## without rewriting a developer's saved preference when the recorder is run locally.
func set_show_unit_speed_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	show_unit_speed = value
	_loading = was_loading


## Set show_engaged_highlight for this run only — no persist to disk, no `changed` signal
## (same _load()-guard trick as set_sfx_enabled_session above). A demo input script can
## request this overlay on for its recording without rewriting a developer's saved
## preference when the recorder is run locally.
func set_show_engaged_highlight_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	show_engaged_highlight = value
	_loading = was_loading


## Set show_position_anchor for this run only — no persist to disk, no `changed` signal
## (same _load()-guard trick as set_sfx_enabled_session above). A demo input script can
## request the position-anchor marker on for its recording without rewriting a developer's
## saved preference when the recorder is run locally.
func set_show_position_anchor_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	show_position_anchor = value
	_loading = was_loading


## Set show_soldier_ids for this run only — no persist to disk, no `changed` signal
## (same _load()-guard trick as set_sfx_enabled_session above). A demo input script can
## request the per-soldier ID overlay on for its recording without rewriting a developer's
## saved preference when the recorder is run locally.
func set_show_soldier_ids_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	show_soldier_ids = value
	_loading = was_loading


## Set show_unit_card_tray for this run only -- no persist to disk, no `changed` signal
## (same _load()-guard trick as set_sfx_enabled_session above). A demo input script can
## show the tray in its recording without rewriting a developer's saved preference.
func set_show_unit_card_tray_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	show_unit_card_tray = value
	_loading = was_loading


## Set tray_row_order_placement for this run only -- no persist to disk, no `changed`
## signal. A demo input script that seeds a tray grid and then form-up-drags it on can
## request the 2D deploy without rewriting a developer's saved preference.
func set_tray_row_order_placement_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	tray_row_order_placement = value
	_loading = was_loading


## The physical keycode currently bound to a mode slug (or its default / KEY_NONE).
func order_binding(slug: String) -> int:
	return SettingsKeybindingsRef.get_binding(order_bindings, slug)


## The mode slug currently bound to a physical keycode, or "" if none. Used by the
## selector (keycode -> mode) and by the rebind UI to detect conflicts.
func slug_for_keycode(keycode: int) -> String:
	return SettingsKeybindingsRef.slug_for_keycode(order_bindings, keycode)


## Rebind a single order mode. No-ops on an unknown slug or an unchanged value.
## Callers (the rebind dialog) are responsible for conflict checks first.
func set_order_binding(slug: String, keycode: int) -> void:
	if not SettingsKeybindingsRef.set_binding(order_bindings, slug, keycode):
		return
	if not _loading:
		_save()
		changed.emit()


## Restore every order-mode hotkey to its factory default.
func reset_order_bindings() -> void:
	if order_bindings == DEFAULT_ORDER_BINDINGS:
		return
	order_bindings = SettingsKeybindingsRef.reset_bindings()
	if not _loading:
		_save()
		changed.emit()


func _to_storage_dict() -> Dictionary:
	return {
		"edge_scroll": edge_scroll,
		"sfx_enabled": sfx_enabled,
		"form_up_dist_default": form_up_dist_default,
		"form_up_dist_cycle": form_up_dist_cycle,
		"tray_row_order_placement": tray_row_order_placement,
		"show_distance_legend": show_distance_legend,
		"show_order_distance": show_order_distance,
		"show_unit_speed": show_unit_speed,
		"show_soldier_ids": show_soldier_ids,
		"show_engaged_highlight": show_engaged_highlight,
		"show_position_anchor": show_position_anchor,
		"show_fps": show_fps,
		"show_performance_graph": show_performance_graph,
		"show_unit_card_tray": show_unit_card_tray,
		"fps_corner": fps_corner,
		"order_bindings": order_bindings,
	}


func _load(path: String = SAVE_PATH) -> void:
	var loaded: Dictionary = SettingsStorageRef.load_from_path(path, _to_storage_dict(), FORM_UP_DIST_MAX)
	if loaded.is_empty():
		return
	_loading = true
	edge_scroll = loaded.get("edge_scroll", edge_scroll)
	sfx_enabled = loaded.get("sfx_enabled", sfx_enabled)
	form_up_dist_default = loaded.get("form_up_dist_default", form_up_dist_default)
	form_up_dist_cycle = loaded.get("form_up_dist_cycle", form_up_dist_cycle)
	tray_row_order_placement = loaded.get("tray_row_order_placement", tray_row_order_placement)
	show_distance_legend = loaded.get("show_distance_legend", show_distance_legend)
	show_order_distance = loaded.get("show_order_distance", show_order_distance)
	show_unit_speed = loaded.get("show_unit_speed", show_unit_speed)
	show_soldier_ids = loaded.get("show_soldier_ids", show_soldier_ids)
	show_engaged_highlight = loaded.get("show_engaged_highlight", show_engaged_highlight)
	show_position_anchor = loaded.get("show_position_anchor", show_position_anchor)
	show_fps = loaded.get("show_fps", show_fps)
	show_performance_graph = loaded.get("show_performance_graph", show_performance_graph)
	show_unit_card_tray = loaded.get("show_unit_card_tray", show_unit_card_tray)
	fps_corner = loaded.get("fps_corner", fps_corner)
	order_bindings = loaded.get("order_bindings", order_bindings)
	_loading = false


func _save(path: String = SAVE_PATH) -> void:
	SettingsStorageRef.save_to_path(path, _to_storage_dict())
