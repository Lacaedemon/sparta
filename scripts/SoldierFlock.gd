class_name SoldierFlock
## Render-support helpers for the soldier mark layer. The cosmetic spring and all
## render-only animation offsets (lunge, weapon stroke, rank-cycle widen, relief
## spread) have been removed; marks now render directly from _sim_soldier_pos.
## Only the LOD threshold logic and block-extent computation remain here.


## Whether the zoomed-in figure LOD should be active, with hysteresis: switch ON at or past
## LOD_ZOOM_IN, OFF at or below LOD_ZOOM_OUT, and HOLD the current level in the band between
## (so the figures don't flicker on and off at the threshold).
static func lod_should_detail(currently_detailed: bool, zoom: float) -> bool:
	if zoom >= Unit.LOD_ZOOM_IN:
		return true
	if zoom <= Unit.LOD_ZOOM_OUT:
		return false
	return currently_detailed


## Block half-size: the farthest man plus a mark radius, floored at the collision RADIUS.
## Sizes the state ring, selection halo, stat bars (in _draw) and the ground shadow.
## `about_footprint` picks the point the radius is measured about. False measures reach from
## the regiment point (`Unit.position`) -- the containment semantics steering/separation
## consumers want, where a footprint standing off the position genuinely extends the block's
## reach on one side. True measures about the block's own footprint centre
## (Unit.block_centre_offset), so chrome hugs the block instead of inflating to cover the
## offset. A block with no men yet reads its layout (Unit.layout_reach), the spawn data the
## men are seeded from.
static func compute_extent(unit: Unit, about_footprint: bool = false) -> float:
	var mark_r: float = Unit.CAV_MARK_RADIUS if unit.is_cavalry else Unit.MARK_RADIUS
	var reach: float
	if MenExtent.has_men(unit):
		reach = MenExtent.reach(unit, unit.block_centre_offset() if about_footprint else Vector2.ZERO)
	else:
		reach = unit.layout_reach(about_footprint)
	return maxf(Unit.RADIUS, reach) + mark_r + 2.0


## Per-axis counterpart to compute_extent(): (half-width along local x/files, half-depth
## along local y/ranks) of the men, each padded by the same mark radius + margin.
## compute_extent()'s single circumradius bounds the block's reach in EVERY direction at
## once (the farthest man, i.e. a corner); these two numbers let a caller bound the reach
## along one SPECIFIC direction instead, via the standard axis-aligned-rectangle support
## formula (`hw*|dx| + hd*|dy|` for a direction (dx,dy) in the block's own local frame) --
## tighter than the circumradius everywhere except along the exact diagonal.
static func compute_half_extents(unit: Unit) -> Vector2:
	var mark_r: float = Unit.CAV_MARK_RADIUS if unit.is_cavalry else Unit.MARK_RADIUS
	return unit._formation_local_half_extents() + Vector2(mark_r + 2.0, mark_r + 2.0)
