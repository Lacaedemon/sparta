class_name UnitSoldierLabels
## Dev/debug overlay (sparta#675): draws each living soldier's index into
## `Unit._sim_soldier_pos` above its mark, for the currently-selected unit only.
## Purely presentational -- reads the sim's per-soldier positions and draws text;
## nothing writes back into it. Called from within the unit's `_draw()`, gated by
## the caller on `selected and Settings.show_soldier_ids and _detailed_lod` (see
## Unit._draw() for why figure LOD is the right threshold: mark-LOD soldiers are
## ~4.5-10 world units and packed edge-to-edge, too small/dense for a legible label).
##
## IDs are per-unit LOCAL -- soldier k's label is `_sim_soldier_pos[k]`'s array index,
## which means nothing about soldier k in a different unit. This matches how
## `tools/demo/dump-state.sh`'s `soldiers_full` arrays are already index-aligned per
## unit, so a developer cross-referencing a state dump against the on-screen overlay
## reads the same number both places with no translation.


## Per-soldier label anchor points, in the unit's own `_draw()` local frame.
## `sim_positions` is the unit's parent-local `_sim_soldier_pos` (via
## Unit.soldier_sim_positions()); `unit_position` is the unit's own parent-local
## `position`. Subtracting `unit_position` lands each point in the unit's local draw
## frame -- the same conversion `Unit._refresh_flock_render` already uses for the
## soldier marks themselves (`_sim_soldier_pos[i] - position`), NOT `to_local()` (the
## project's own note is that these arrays are parent-local, not world-space, and the
## two only coincide by accident while the Battle scene sits at the world origin).
## Each anchor sits `mark_r` above (local -Y, i.e. "up" on screen) its soldier's mark
## so the digit doesn't sit on top of it. Pure and deterministic: a function of the
## positions/offset only, so it's directly unit-testable without a live unit or a
## render pass.
static func label_anchors(sim_positions: PackedVector2Array, unit_position: Vector2,
		mark_r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in sim_positions:
		out.push_back(p - unit_position - Vector2(0.0, mark_r))
	return out


## Draw one numeric ID label per living soldier, above its mark. Must be called from
## within `u._draw()` (draw_string is only valid inside a CanvasItem's own draw
## callback); the caller is responsible for the selected/Settings/LOD gate -- this
## function itself is unconditional so it can be smoke-tested directly, the same
## pattern as UnitShields.draw().
static func draw(u: Unit) -> void:
	var font := ThemeDB.fallback_font
	var anchors := label_anchors(u.soldier_sim_positions(), u.position, u.soldier_body_radius())
	for i in range(anchors.size()):
		u.draw_string(font, anchors[i] + Vector2(-4.0, 0.0), str(i),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.9))
