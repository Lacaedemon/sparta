extends Node2D
## Ghost markers for remembered enemy contacts under fog of war: a translucent block
## outline, in the contact's team color, at the position and facing it was last seen at,
## fading from `fresh_alpha` toward `stale_alpha` as the sighting ages past
## `stale_ticks`. Draws only contacts that are NOT currently visible (a visible enemy
## renders normally through its own Unit node). Pure rendering: it reads the table
## Battle hands it and never touches a unit.

const WorldScaleRef = preload("res://scripts/WorldScale.gd")

# Marker footprint: half-extents of the outline (half-width across the front, half-depth
# along the facing), turned to the last-known facing. A fixed silhouette rather than the
# unit's real frontage -- the marker says "something was here, facing that way", not how
# wide it was.
var half_size: Vector2 = Vector2(1.5, 0.75) * WorldScaleRef.WU_PER_M
# Length of the facing tick drawn forward from the outline's center, as a multiple of the
# half-depth. Dimensionless.
var facing_tick_scale: float = 1.5
var line_width: float = 2.0   # tuned in wu (screen legibility at the default zoom)
# Alpha of a marker on the tick it was last seen, and the floor it fades to once the
# sighting is `stale_ticks` old or older.
var fresh_alpha: float = 0.6
var stale_alpha: float = 0.2
var stale_ticks: int = 600

var _contacts: Dictionary = {}
var _seen: Dictionary = {}
var _tick: int = 0


func _ready() -> void:
	# Same layer as the rout shockwave: above the field and the units' own cosmetic stack,
	# below volley trails, the selection box, and the HUD.
	z_index = 4


## Redraw from the latest fog pass: `contacts` is the team's last-known table
## (Perception.record_contacts's shape), `seen` the uids visible this tick (those draw no
## ghost), `tick` the current physics tick that dates each entry's age.
func update(contacts: Dictionary, seen: Dictionary, tick: int) -> void:
	_contacts = contacts
	_seen = seen
	_tick = tick
	queue_redraw()


## Drop every marker (fog switched off).
func clear() -> void:
	_contacts = {}
	_seen = {}
	queue_redraw()


## Marker alpha for a sighting `age` ticks old: linear from fresh_alpha at 0 to stale_alpha
## at stale_ticks, clamped there.
func alpha_for_age(age: int) -> float:
	if stale_ticks <= 0:
		return stale_alpha
	var t: float = clampf(float(age) / float(stale_ticks), 0.0, 1.0)
	return lerpf(fresh_alpha, stale_alpha, t)


func _draw() -> void:
	for uid in _contacts:
		if _seen.has(uid):
			continue
		var c: Dictionary = _contacts[uid]
		var color: Color = c["color"]
		color.a = alpha_for_age(_tick - int(c["tick"]))
		var pos: Vector2 = c["position"]
		var forward: Vector2 = c["facing"]
		if forward.length_squared() == 0.0:
			forward = Vector2.DOWN
		forward = forward.normalized()
		var right := Vector2(-forward.y, forward.x)
		var across: Vector2 = right * half_size.x
		var deep: Vector2 = forward * half_size.y
		var outline := PackedVector2Array([
			pos + across - deep, pos + across + deep,
			pos - across + deep, pos - across - deep,
			pos + across - deep,
		])
		draw_polyline(outline, color, line_width)
		draw_line(pos, pos + forward * half_size.y * facing_tick_scale, color, line_width)
