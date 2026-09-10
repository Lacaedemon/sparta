class_name ReinforceApproach
## The approach geometry of reinforcement insertion (UnitReinforce): where a reserve must
## stand behind its host, and whether it stands there yet. Both are measured along the
## HOST's facing from the blocks' actual bodies, not from a local slot frame, so a turned
## block (nonzero formation angle) or one still settling onto its slots measures as it
## stands. Pure and static; no scene tree.

## Arrival slack along the host's facing, in host rank pitches: the commit fires once the
## reserve's front edge is within the one-pitch rendezvous gap plus this many pitches of
## the host's rear edge. The default is the one pitch a decelerating arrival can stop short.
const ARRIVAL_SLACK_PITCHES: float = 1.0
## How far past the host's rear edge the reserve's front edge may press (bodies touching
## the rear rank) before the arrival counts as an overshoot and the commit waits.
const OVERSHOOT_TOLERANCE_PITCHES: float = 0.25
## Lateral error allowed between the two blocks' lines of advance, in host rank pitches.
const LATERAL_TOLERANCE_PITCHES: float = 1.0


## The host's physical front/rear axis: the slot grid's depth axis, which is the heading
## rotated by the formation angle (soldier_block_world_angle's own formula). A quarter-turn
## or about-face turns the men in place and leaves the grid folded, so the raw heading is
## the wrong axis for where "behind the block" is until a fresh move re-squares it.
static func depth_axis(host: Unit) -> Vector2:
	return host.facing.rotated(host._formation_angle)


## The largest entry of a per-file count or per-man rank array (0 when empty).
static func deepest(values: PackedInt32Array) -> int:
	var out: int = 0
	for v in values:
		out = maxi(out, v)
	return out


## Signed extents of `u`'s bodies about its position along `dir`, as (rear, front)
## measuring the true min and max bounds (Vector2.ZERO when empty).
## Parent-local, like the bodies and `position` themselves.
static func extent_along(u: Unit, dir: Vector2) -> Vector2:
	if u._sim_soldier_pos.is_empty():
		return Vector2.ZERO
	var lo: float = INF
	var hi: float = -INF
	for p in u._sim_soldier_pos:
		var d: float = (p - u.position).dot(dir)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


## Where the reserve marches to: straight behind the host's block, with its front edge one
## host rank pitch behind the host's rear edge, both edges measured along the depth axis.
static func rendezvous_point(host: Unit, reserve: Unit) -> Vector2:
	var dir: Vector2 = depth_axis(host)
	var gap: float = -extent_along(host, dir).x + extent_along(reserve, dir).y + host.rank_pitch_wu()
	var centre_delta: Vector2 = \
			host.block_centre_offset() - reserve.block_centre_offset()
	return host.position + centre_delta - dir * gap


## True once the reserve stands at the rendezvous: its front edge behind the host's rear
## edge by at most the rendezvous gap plus the arrival slack, pressed no further into the
## host than the overshoot tolerance, and within the lateral tolerance of the host's line.
static func at_rendezvous(reserve: Unit, host: Unit,
		slack_pitches: float = ARRIVAL_SLACK_PITCHES,
		overshoot_pitches: float = OVERSHOOT_TOLERANCE_PITCHES,
		lateral_pitches: float = LATERAL_TOLERANCE_PITCHES) -> bool:
	var dir: Vector2 = depth_axis(host)
	var pitch: float = host.rank_pitch_wu()
	var host_rear: float = host.position.dot(dir) + extent_along(host, dir).x
	var reserve_front: float = reserve.position.dot(dir) + extent_along(reserve, dir).y
	var gap: float = host_rear - reserve_front
	var host_centre: Vector2 = host.position + host.block_centre_offset()
	var reserve_centre: Vector2 = reserve.position + reserve.block_centre_offset()
	var across: float = absf((reserve_centre - host_centre).dot(dir.orthogonal()))
	return gap >= -overshoot_pitches * pitch and gap <= (1.0 + slack_pitches) * pitch \
			and across <= lateral_pitches * pitch

