class_name ScreenIntervals
## Where the gaps in a formed line are: the lateral coordinates a withdrawing skirmisher
## screen can fall back THROUGH, so it passes between the heavy blocks the way Livy's
## manipular line opens for the front rank (8.8) rather than trying to walk through one.
## See docs/deployment-distance-design.md, "Skirmisher screening".
##
## Pure geometry over already-serialized positions: no RNG, no wall-clock, no unit-state
## writes, so the same line always yields the same intervals in the same order -- the same
## determinism contract Subcommander and General already carry.
const WorldScaleRef = preload("res://scripts/WorldScale.gd")

## How far outboard of the end block the line's open flank counts as an interval. Matched to
## Subcommander.FLANK_COVER_OFFSET's own reasoning: far enough out to clear the end block's
## own frontage rather than crowding into it.
const FLANK_INTERVAL_OFFSET := 4.0 * WorldScaleRef.WU_PER_M


## Median projection of `units` onto `axis` -- the line's own depth, the same median
## Subcommander._line_integrity_directives measures the line by, so "the line" means the
## same thing to the screen as it does to line discipline.
static func median_depth(units: Array, axis: Vector2) -> float:
	var proj: Array[float] = []
	for node in units:
		var u := node as Unit
		if u != null:
			proj.append(u.position.dot(axis))
	proj.sort()
	var n: int = proj.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return proj[n / 2]
	return (proj[n / 2 - 1] + proj[n / 2]) * 0.5


## The lateral (perpendicular-to-axis) coordinates of the line's intervals: the midpoint
## between each adjacent pair of blocks, plus one open flank `flank_offset` outboard of each
## end block. Sorted ascending, a function of position alone -- never of iteration order. A
## line of one block still has its two flanks; an empty line has no intervals at all.
static func interval_laterals(units: Array, perp: Vector2,
		flank_offset: float = FLANK_INTERVAL_OFFSET) -> Array[float]:
	var lat: Array[float] = []
	for node in units:
		var u := node as Unit
		if u != null:
			lat.append(u.position.dot(perp))
	lat.sort()
	var out: Array[float] = []
	if lat.is_empty():
		return out
	out.append(lat[0] - flank_offset)
	for i in range(1, lat.size()):
		out.append((lat[i - 1] + lat[i]) * 0.5)
	out.append(lat[lat.size() - 1] + flank_offset)
	return out


## The interval in `laterals` nearest `lateral`, or `lateral` itself when there are none.
## Strictly-less-than comparison keeps the FIRST of two equidistant intervals, and
## interval_laterals sorts ascending, so an exact tie resolves to the lower coordinate
## rather than to whichever the loop happened to reach last.
static func nearest(laterals: Array[float], lateral: float) -> float:
	var best: float = lateral
	var best_d: float = INF
	for v in laterals:
		var d: float = absf(v - lateral)
		if d < best_d:
			best_d = d
			best = v
	return best
