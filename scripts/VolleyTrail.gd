class_name VolleyTrail
extends TransientEffect
## A short-lived arrow-volley trail: a small cluster of streaks that fly from a
## ranged unit toward its target when it looses a volley (Unit._shoot), fading as they
## land. Purely cosmetic — spawned on the deterministic sim tick but animated on render
## time (_process), so it carries no sim/replay/determinism state and frees itself when
## done. Not in the "units"/"routers" groups, so no scan ever picks it up.

const LIFETIME := 0.30          # seconds a volley streak stays visible
const STREAKS := 3              # number of streaks drawn to suggest a volley
const SPREAD := 6.0             # perpendicular spacing between streaks (px)
const STREAK_LEN := 0.16        # streak length as a fraction of the whole flight
const ARC_HEIGHT := 0.18        # parabolic arc peak as a fraction of the flight distance
const ARC_STEPS := 6            # polyline segments per streak for the curved path

var _delta: Vector2 = Vector2.ZERO    # shooter -> target offset, in local space
var _lift_dir: Vector2 = Vector2.ZERO # unit-length perpendicular to _delta, for the arc
var _color: Color = Color.WHITE
var _streaks: int = STREAKS
var _spread: float = SPREAD
var _streak_len: float = STREAK_LEN
var _arc_height: float = ARC_HEIGHT
var _arc_steps: int = ARC_STEPS


## Spawn a trail under `parent` flying from `from` to `to` (both world-space). Colour
## is the shooter's team colour, brightened so the arrows read against the field.
static func spawn(parent: Node, from: Vector2, to: Vector2, color: Color,
		lifetime: float = LIFETIME, streaks: int = STREAKS, spread: float = SPREAD,
		streak_len: float = STREAK_LEN, arc_height: float = ARC_HEIGHT,
		arc_steps: int = ARC_STEPS) -> void:
	var trail := VolleyTrail.new()
	trail._lifetime = lifetime
	trail._streaks = streaks
	trail._spread = spread
	trail._streak_len = streak_len
	trail._arc_height = arc_height
	trail._arc_steps = arc_steps
	parent.add_child(trail)
	trail.global_position = from
	trail._delta = to - from
	trail._color = color.lerp(Color.WHITE, 0.5)
	trail.z_index = 5   # above unit bodies, below the HUD / selection overlay
	# orthogonal() rotates 90° counterclockwise, so all streaks arc to the left
	# relative to their flight direction. Two opposing volleys arc in opposite
	# on-screen directions, which looks natural and is consistent per-shot.
	if trail._delta.length() > 0.001:
		trail._lift_dir = trail._delta.orthogonal().normalized()


func _draw() -> void:
	var t: float = clampf(_age / _lifetime, 0.0, 1.0)
	var tail_t: float = maxf(0.0, t - _streak_len)   # streak trails behind the arrowhead
	var col := Color(_color, (1.0 - t) * 0.9)       # streaks dim as they land
	var arc_peak: float = _delta.length() * _arc_height
	for i in range(_streaks):
		var lane: float = float(i) - float(_streaks - 1) * 0.5   # centered offsets
		var off: Vector2 = _lift_dir * _spread * lane
		var pts := PackedVector2Array()
		for s in range(_arc_steps + 1):
			var u: float = tail_t + (t - tail_t) * float(s) / float(_arc_steps)
			var arc_lift: Vector2 = _lift_dir * arc_peak * sin(u * PI)
			pts.append(_delta * u + arc_lift + off)
		draw_polyline(pts, col, 1.5)
