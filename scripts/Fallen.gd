class_name Fallen
extends TransientEffect
## Fallen soldiers (Stage C): a small heap of dark body marks dropped exactly where men
## fall in melee -- one mark per REAL fallen-soldier position, never a synthetic scatter
## around an averaged point (bottom-up physics: the mark IS the data, not a stand-in for
## it). Spawned from UnitCombat.register_casualties on the deterministic sim tick but
## animated on render time (_process), in no sim group, and frees itself -- so it carries
## no sim/replay/determinism state. Fades into the ground as the fight moves on.
## Purely cosmetic -- the body count is verified visually / in the demo clip.

const LIFETIME := 2.2           # seconds a heap stays before it has fully faded
const MAX_MARKS := 200          # defensive cap on draw calls for a pathological mass-death event
const MARK_RADIUS: float = Unit.MARK_RADIUS   # default body size: a foot soldier (cavalry overrides)
const FADE_START := 0.5         # fraction of LIFETIME the heap stays opaque before fading

var _color: Color = Color(0.2, 0.2, 0.2)
var _marks: PackedVector2Array = PackedVector2Array()
var _mark_radius: float = MARK_RADIUS   # body size for this heap (foot vs cavalry, set by spawn)
var _fade_start: float = FADE_START


## Spawn a heap of dead-body marks at `positions` (world space, one entry per fallen
## soldier -- each position is that soldier's own real live position, never a synthetic
## scatter). A no-op if `positions` is empty (nothing fell, nothing to show). Colour is
## the dead unit's team colour, darkened so the bodies read as fallen rather than a live
## block. `mark_radius` is the per-body size -- foot soldiers by default, larger for
## cavalry (Unit.CAV_MARK_RADIUS), so a fallen cavalry heap reads as bigger bodies,
## matching the bigger live cavalry marks. `MAX_MARKS` caps the draw-call count for a
## pathological mass-death event; it is not a cosmetic density limit like the old
## synthetic-scatter design needed.
static func spawn(parent: Node, positions: PackedVector2Array, color: Color,
		mark_radius: float = MARK_RADIUS, lifetime: float = LIFETIME,
		fade_start: float = FADE_START) -> void:
	if positions.is_empty():
		return
	var fx := Fallen.new()
	fx._lifetime = lifetime
	fx._mark_radius = mark_radius
	fx._fade_start = fade_start
	var origin: Vector2 = positions[0]
	var n: int = mini(positions.size(), MAX_MARKS)
	var marks := PackedVector2Array()
	for i in range(n):
		marks.push_back(positions[i] - origin)
	fx._marks = marks
	fx._color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4)
	parent.add_child(fx)
	fx.global_position = origin
	fx.z_index = 1   # on the ground: above the field (0), below the soldier marks (eff 2)


func _draw() -> void:
	var t: float = clampf(_age / _lifetime, 0.0, 1.0)
	# Hold the bodies opaque for the first part of their life, then fade them out.
	var fade: float = 1.0 - smoothstep(_fade_start, 1.0, t)
	var col := Color(_color, fade * 0.7)
	for m in _marks:
		draw_circle(m, _mark_radius, col)
