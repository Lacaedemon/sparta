class_name UnitSprites
## The regimental flag drawn on a Unit's chrome layer, extracted from Unit.gd. Each
## function draws straight onto the passed-in unit (a CanvasItem), so it must be called
## from within that unit's `_draw()`. Pure presentation: shapes are a function of the
## unit's type/colours only, nothing writes back into the simulation. Sizes key off
## `Unit.RADIUS` / `Unit.FLAG_*`.
##
## The former per-type centre emblem (a large icon hovering over the whole block) was
## removed: unit type is already conveyed by the per-soldier mark/figure shapes
## (see UnitMeshes — dart/kite/pointer marks and the figure silhouettes, both distinct
## per type at any zoom), the flag's own mini emblem below, and the selected-unit info
## card (HUD.gd).


## The local-space bounding box of a unit's raised standard (pole + flag), in the same
## unrotated screen frame `flag()` draws in (origin = the unit centre). Single-sources the
## standard's geometry so a hit test (clicking the flag to select the unit) stays in step
## with what's drawn. `extent` is the unit's render block half-size; `centre` is the
## block's footprint centre in that same frame (Unit.block_centre_offset -- ZERO unless
## a standing anchor offset shifts the block off the regiment point).
static func standard_bounds(extent: float, centre: Vector2 = Vector2.ZERO) -> Rect2:
	# Pole foot sits FLAG_POLE_BASE_GAP above the block; the pole rises FLAG_POLE_HEIGHT to
	# the flag attachment, and the brass finial caps it FLAG_FINIAL_OFFSET above the tip
	# with FLAG_FINIAL_RADIUS reach -- so the bound grows past the pole span by the
	# finial's own extents (up and left; its right side stays inside the flag's width).
	# The flag hangs from the pole tip and FLAG_HEIGHT (8) < FLAG_POLE_HEIGHT (18), so it's
	# fully nested in the pole span. (If the flag were ever re-anchored below the pole
	# base, this bound would need to grow to cover it.)
	var finial_reach: float = Unit.FLAG_FINIAL_OFFSET + Unit.FLAG_FINIAL_RADIUS
	var top: float = centre.y - extent - Unit.FLAG_POLE_BASE_GAP - Unit.FLAG_POLE_HEIGHT 			- finial_reach
	return Rect2(centre.x - Unit.FLAG_FINIAL_RADIUS, top,
			Unit.FLAG_WIDTH + Unit.FLAG_FINIAL_RADIUS,
			Unit.FLAG_POLE_HEIGHT + finial_reach)


## A regimental standard: a pole rising above the stat bars with a coloured flag bearing a
## per-type emblem. Drawn in screen space (called after draw_set_transform reset) so it
## always stands upright regardless of the unit's facing direction. Dead units skip it.
static func flag(u: Unit, body_c: Color, alpha: float, extent: float,
		centre: Vector2 = Vector2.ZERO) -> void:
	if u.state == Unit.State.DEAD:
		return
	# Pole rises from just above the soldier-count text (which sits ~14 px above bar top).
	var pole_base := centre + Vector2(0.0, -extent - Unit.FLAG_POLE_BASE_GAP)
	var pole_top  := Vector2(pole_base.x, pole_base.y - Unit.FLAG_POLE_HEIGHT)
	u.draw_line(pole_base, pole_top, Color(0.85, 0.85, 0.85, alpha), 1.5)
	# The cloth hangs below the pole tip (positive-Y in screen space = downward): a
	# swallowtail pennant -- a V-notch cut into the fly edge -- with a darker lower
	# fold, so the standard reads as hanging cloth rather than a flat chip. Both
	# polygons take the team colour (the fold via darkened, which preserves alpha, so
	# the routing fade flows through unchanged); the whole shape nests inside the
	# FLAG_WIDTH x FLAG_HEIGHT rect standard_bounds already reports.
	var fx: float = pole_top.x
	var fy: float = pole_top.y
	var fw: float = Unit.FLAG_WIDTH
	var fh: float = Unit.FLAG_HEIGHT
	var notch: float = fw * 0.28
	var cloth := PackedVector2Array([
		Vector2(fx, fy), Vector2(fx + fw, fy),
		Vector2(fx + fw - notch, fy + fh * 0.5), Vector2(fx + fw, fy + fh),
		Vector2(fx, fy + fh),
	])
	u.draw_colored_polygon(cloth, body_c)
	u.draw_colored_polygon(PackedVector2Array([
		Vector2(fx, fy + fh * 0.5), Vector2(fx + fw - notch, fy + fh * 0.5),
		Vector2(fx + fw, fy + fh), Vector2(fx, fy + fh),
	]), body_c.darkened(0.18))
	var rim: PackedVector2Array = cloth.duplicate()
	rim.push_back(cloth[0])
	u.draw_polyline(rim, Color(1.0, 1.0, 1.0, alpha * 0.5), 1.0)
	# Brass finial capping the pole above the attachment.
	u.draw_circle(pole_top + Vector2(0.0, -Unit.FLAG_FINIAL_OFFSET), Unit.FLAG_FINIAL_RADIUS,
			Color(0.82, 0.68, 0.28, alpha))
	# Type emblem on the cloth body (nudged off-centre toward the hoist, clear of the
	# notch): spear = vertical, bow = arc, lance = diagonal, cross = infantry.
	var fc := Vector2(fx + fw * 0.42, fy + fh * 0.5)
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
