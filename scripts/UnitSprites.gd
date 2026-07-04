class_name UnitSprites
## The regimental flag drawn on a Unit's chrome layer, extracted from Unit.gd. Each
## function draws straight onto the passed-in unit (a CanvasItem), so it must be called
## from within that unit's `_draw()`. Pure presentation: shapes are a function of the
## unit's type/colours only, nothing writes back into the simulation. Sizes key off
## `Unit.RADIUS` / `Unit.FLAG_*`.
##
## The former per-type centre emblem (a large icon hovering over the whole block) was
## removed (#627): unit type is already conveyed by the per-soldier mark/figure shapes
## (see UnitMeshes — dart/kite/pointer marks and the figure silhouettes, both distinct
## per type at any zoom), the flag's own mini emblem below, and the selected-unit info
## card (HUD.gd).


## The local-space bounding box of a unit's raised standard (pole + flag), in the same
## unrotated screen frame `flag()` draws in (origin = the unit centre). Single-sources the
## standard's geometry so a hit test (clicking the flag to select the unit) stays in step
## with what's drawn. `extent` is the unit's render block half-size.
static func standard_bounds(extent: float) -> Rect2:
	# Pole foot sits FLAG_POLE_BASE_GAP above the block; the pole rises FLAG_POLE_HEIGHT to
	# the flag attachment. Width spans the flag rectangle (the pole sits on its left edge).
	# The flag hangs from the pole tip and FLAG_HEIGHT (8) < FLAG_POLE_HEIGHT (18), so it's
	# fully nested in the pole span — the height needn't add FLAG_HEIGHT. (If the flag were
	# ever re-anchored below the pole base, this bound would need to grow to cover it.)
	var top: float = -extent - Unit.FLAG_POLE_BASE_GAP - Unit.FLAG_POLE_HEIGHT
	return Rect2(0.0, top, Unit.FLAG_WIDTH, Unit.FLAG_POLE_HEIGHT)


## A regimental standard: a pole rising above the stat bars with a coloured flag bearing a
## per-type emblem. Drawn in screen space (called after draw_set_transform reset) so it
## always stands upright regardless of the unit's facing direction. Dead units skip it.
static func flag(u: Unit, body_c: Color, alpha: float, extent: float) -> void:
	if u.state == Unit.State.DEAD:
		return
	# Pole rises from just above the soldier-count text (which sits ~14 px above bar top).
	var pole_base := Vector2(0.0, -extent - Unit.FLAG_POLE_BASE_GAP)
	var pole_top  := Vector2(0.0, pole_base.y - Unit.FLAG_POLE_HEIGHT)
	u.draw_line(pole_base, pole_top, Color(0.85, 0.85, 0.85, alpha), 1.5)
	# Flag rectangle hangs below the pole tip (positive-Y in screen space = downward).
	var fx: float = pole_top.x
	var fy: float = pole_top.y
	u.draw_rect(Rect2(fx, fy, Unit.FLAG_WIDTH, Unit.FLAG_HEIGHT), body_c)
	u.draw_rect(Rect2(fx, fy, Unit.FLAG_WIDTH, Unit.FLAG_HEIGHT),
			Color(1.0, 1.0, 1.0, alpha * 0.5), false, 1.0)
	# Type emblem centred on the flag: spear = vertical, bow = arc, lance = diagonal, cross = infantry.
	var fc := Vector2(fx + Unit.FLAG_WIDTH * 0.5, fy + Unit.FLAG_HEIGHT * 0.5)
	var sym_c := Color(1.0, 1.0, 1.0, alpha)
	if u.is_cavalry:
		u.draw_line(fc + Vector2(-3.0, 2.5), fc + Vector2(3.0, -2.5), sym_c, 1.5)
	elif u.anti_cavalry:
		u.draw_line(fc + Vector2(0.0, 3.0), fc + Vector2(0.0, -3.0), sym_c, 1.5)
	elif u.is_ranged:
		u.draw_arc(fc, 2.5, -PI * 0.55, PI * 0.55, 6, sym_c, 1.5)
	else:
		u.draw_line(fc + Vector2(-2.5, 0.0), fc + Vector2(2.5, 0.0), sym_c, 1.5)
		u.draw_line(fc + Vector2(0.0, -2.5), fc + Vector2(0.0, 2.5), sym_c, 1.5)
