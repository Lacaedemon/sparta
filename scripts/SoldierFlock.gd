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


## Block half-size: the farthest slot plus a mark radius, floored at the collision RADIUS.
## Sizes the state ring, selection halo, stat bars (in _draw) and the ground shadow.
## `centre` is the local-frame point the radius is measured about. The ZERO default
## measures reach from the regiment point (`Unit.position`) -- the containment
## semantics steering/separation consumers want, where a standing anchor offset
## genuinely extends the block's reach on one side. Chrome passes the block's own
## local centre (the anchor shift) instead, so the ring hugs the block's footprint
## rather than inflating to cover the offset.
static func compute_extent(unit: Unit, slots: PackedVector2Array,
		centre: Vector2 = Vector2.ZERO) -> float:
	var mark_r: float = Unit.CAV_MARK_RADIUS if unit.is_cavalry else Unit.MARK_RADIUS
	var extent: float = Unit.RADIUS
	for s in slots:
		extent = maxf(extent, (s - centre).length())
	return extent + mark_r + 2.0


## Per-axis counterpart to compute_extent(): (half-width along local x/files, half-depth
## along local y/ranks) of the same slot set, each padded by the same mark radius + margin.
## compute_extent()'s single circumradius bounds the block's reach in EVERY direction at
## once (the farthest slot, i.e. a corner); these two numbers let a caller bound the reach
## along one SPECIFIC direction instead, via the standard axis-aligned-rectangle support
## formula (`hw*|dx| + hd*|dy|` for a direction (dx,dy) in the block's own local frame) --
## tighter than the circumradius everywhere except along the exact diagonal.
static func compute_half_extents(unit: Unit, slots: PackedVector2Array) -> Vector2:
	var mark_r: float = Unit.CAV_MARK_RADIUS if unit.is_cavalry else Unit.MARK_RADIUS
	var hw: float = 0.0
	var hd: float = 0.0
	for s in slots:
		hw = maxf(hw, absf(s.x))
		hd = maxf(hd, absf(s.y))
	return Vector2(hw + mark_r + 2.0, hd + mark_r + 2.0)
