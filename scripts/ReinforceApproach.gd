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


## Signed extents of `u`'s bodies about its position along `dir`, as (rear, front) with
## rear <= 0 <= front. Parent-local, like the bodies and `position` themselves.
static func extent_along(u: Unit, dir: Vector2) -> Vector2:
	var lo: float = 0.0
	var hi: float = 0.0
	for p in u._sim_soldier_pos:
		var d: float = (p - u.position).dot(dir)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


## Where the reserve marches to: straight behind the host, with its front edge one host
## rank pitch behind the host's rear edge, both edges measured along the host's facing.
static func rendezvous_point(host: Unit, reserve: Unit) -> Vector2:
	var dir: Vector2 = host.facing
	var gap: float = -extent_along(host, dir).x + extent_along(reserve, dir).y + host.rank_pitch_wu()
	return host.position - dir * gap


## True once the reserve stands at the rendezvous: its front edge behind the host's rear
## edge by at most the rendezvous gap plus the arrival slack, pressed no further into the
## host than the overshoot tolerance, and within the lateral tolerance of the host's line.
static func at_rendezvous(reserve: Unit, host: Unit,
		slack_pitches: float = ARRIVAL_SLACK_PITCHES,
		overshoot_pitches: float = OVERSHOOT_TOLERANCE_PITCHES,
		lateral_pitches: float = LATERAL_TOLERANCE_PITCHES) -> bool:
	var dir: Vector2 = host.facing
	var pitch: float = host.rank_pitch_wu()
	var host_rear: float = host.position.dot(dir) + extent_along(host, dir).x
	var reserve_front: float = reserve.position.dot(dir) + extent_along(reserve, dir).y
	var gap: float = host_rear - reserve_front
	var across: float = absf((reserve.position - host.position).dot(dir.orthogonal()))
	return gap >= -overshoot_pitches * pitch and gap <= (1.0 + slack_pitches) * pitch \
			and across <= lateral_pitches * pitch
