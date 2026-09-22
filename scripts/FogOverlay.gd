extends Node2D
## Terrain fog-of-war overlay: darkens ground the fog team has never explored and dims
## ground it has explored before but does not currently see, leaving currently-visible
## ground undecorated. Independent of unit fog (Perception.gd/FogGhostLayer.gd), which
## hides enemy Unit nodes rather than ground -- this layer never touches a unit.
##
## Pure rendering: it reads the grid Battle hands it and never touches Battle or a unit.
## Battle owns and persists the underlying explored bits (Battle._fog_explored) so they
## survive capture_snapshot/restore_snapshot; this layer only draws whatever it was last
## handed. Inert (draws nothing) until update() is called, and again after clear().

## Cell edge length in world units, and the grid covering `field` at that size --
## Battle sets these once in _ready() from Battle.fog_cell and never resizes them again
## this battle (the field is fixed for the battle's lifetime).
var field: Rect2 = Rect2()
var cell_size: float = 40.0
var grid_w: int = 0
var grid_h: int = 0

## Fill color for an unexplored cell (alpha 1.0 by default: hides ground art and terrain
## entirely, per the design doc's "opaque unexplored layer"). The same color, at
## `explored_dim_alpha`, darkens an explored-but-not-currently-visible cell instead of
## hiding it. Both caller-configurable; Battle exposes them as fog_unexplored_color and
## fog_explored_dim_alpha.
var unexplored_color: Color = Color(0.05, 0.06, 0.05, 1.0)
var explored_dim_alpha: float = 0.45

var _active: bool = false
var _explored: PackedByteArray = PackedByteArray()
var _visible_now: Dictionary = {}


func _ready() -> void:
	add_to_group("fog_overlay")
	# Above the field/terrain (Battle._draw, effective z 0) and Fallen.gd's ground fx
	# (z 1), below units (Unit.z_index 3) and RoutShockwave.gd (z 4) -- ground dimming
	# must never paint over a unit that is actually rendering.
	z_index = 2


## Redraw from the latest fog pass. `explored` is Battle's persistent per-cell grid
## (grid_w * grid_h PackedByteArray, row-major, 0/1 -- monotonic, never shrinks);
## `visible_now` is this tick's currently-seen cell set (idx -> true), recomputed fresh
## every tick and never persisted. Neither is copied; the caller owns both.
func update(explored: PackedByteArray, visible_now: Dictionary) -> void:
	_active = true
	_explored = explored
	_visible_now = visible_now
	queue_redraw()


## Stop drawing (fog switched off, or all_teams_control forcing it off). The persistent
## explored grid itself is Battle's to keep or clear -- this only blanks the display.
func clear() -> void:
	_active = false
	_visible_now = {}
	queue_redraw()


## Summary counts for the state dump (tools/demo/DemoState.gd, mirroring
## FogGhostLayer.ghost_records()) and other verification tooling: grid shape, how many
## cells are explored (cumulative, out of the grid total), how many are currently visible
## this tick (a subset of explored, 0 while inert), and whether the overlay is currently
## drawing at all. Read-only; never consulted by rendering itself.
func terrain_stats() -> Dictionary:
	var explored_count: int = 0
	for b in _explored:
		if b != 0:
			explored_count += 1
	return {
		"active": _active,
		"grid_w": grid_w,
		"grid_h": grid_h,
		"cell_size": cell_size,
		"explored_count": explored_count,
		"total_cells": grid_w * grid_h,
		"visible_now_count": _visible_now.size(),
	}


func _draw() -> void:
	if not _active or grid_w <= 0 or grid_h <= 0:
		return
	var dim_color := unexplored_color
	dim_color.a = explored_dim_alpha
	for cy in range(grid_h):
		for cx in range(grid_w):
			var idx: int = cy * grid_w + cx
			var explored: bool = idx < _explored.size() and _explored[idx] != 0
			if not explored:
				var rect := Rect2(field.position + Vector2(cx, cy) * cell_size, Vector2(cell_size, cell_size))
				draw_rect(rect, unexplored_color)
			elif not _visible_now.has(idx):
				var rect2 := Rect2(field.position + Vector2(cx, cy) * cell_size, Vector2(cell_size, cell_size))
				draw_rect(rect2, dim_color)
