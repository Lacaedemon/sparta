extends Node3D
## THROWAWAY SPIKE (3D-0b). Not production code, not covered by the GUT suite.
##
## The projection-shell path from docs/3d-conversion-design.md: the existing 2D
## battle tree runs unmodified inside a SubViewport with its canvas hidden, and this
## node hangs a second, read-only 3D consumer off the per-soldier arrays it already
## publishes. Nothing here writes into the sim.
##
## Run: godot --rendering-driver opengl3 --path . res://spikes/3d/ProjectionShell.tscn
##
## Proves: sim-drives-3D-view wiring, one MultiMeshInstance3D per unit, wu-to-metre
## conversion at the boundary, orbit camera, ray-to-ground picking.
## Does NOT prove: selection/orders routed back through set_cursor_override(),
## state-dump parity, LOD, animation, or terrain.

const SimScene := preload("res://scenes/Battle.tscn")
const WorldScaleRef = preload("res://scripts/WorldScale.gd")

## Ground plane extent, in metres. Sized generously rather than scaled to the
## battlefield, so the plane still reads as ground when the camera pans off it.
@export var ground_extent_m: float = 400.0
## Frame on which to fire a synthetic centre-screen pick, so a non-interactive run
## still exercises the ray-to-ground path. Zero disables it; the environment
## variable SPARTA_SPIKE_PICK_FRAME overrides it.
@export var self_test_pick_frame: int = 0
## Soldier proxy box, in metres: roughly a man's footprint and height.
@export var soldier_size_m: Vector3 = Vector3(0.5, 1.8, 0.5)

@onready var _sim_viewport: SubViewport = $SimViewport
@onready var _camera: Camera3D = $OrbitCamera
@onready var _crowd_root: Node3D = $Crowd

var _views: Dictionary = {}
var _last_units: int = -1
var _last_bodies: int = -1
var _frames: int = 0


func _ready() -> void:
	var sim: Node = SimScene.instantiate()
	_sim_viewport.add_child(sim)
	# A hidden CanvasItem still runs _physics_process, so the sim ticks exactly as it
	# does in the 2D scene; only its drawing is skipped.
	if sim is CanvasItem:
		(sim as CanvasItem).visible = false
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_extent_m, ground_extent_m)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	add_child(ground)
	_centre_camera_on_field(sim)
	var override: String = OS.get_environment("SPARTA_SPIKE_PICK_FRAME")
	if override.is_valid_int():
		self_test_pick_frame = int(override)


## Point the camera at the middle of the battle rather than the world origin.
## Battle publishes its rect as a plain `field` member in world units; the spike
## converts it once, here, and falls back to the origin if that member is absent.
func _centre_camera_on_field(sim: Node) -> void:
	var rect: Variant = sim.get("field")
	if not (rect is Rect2):
		return
	var centre_wu: Vector2 = (rect as Rect2).get_center()
	var centre_m := Vector3(
		centre_wu.x * WorldScaleRef.M_PER_WU,
		0.0,
		centre_wu.y * WorldScaleRef.M_PER_WU,
	)
	_camera.call("set_home_focus", centre_m)
	print("[shell] camera focus %.1f, %.1f m (battlefield centre)" % [centre_m.x, centre_m.z])


func _process(_delta: float) -> void:
	var seen: Dictionary = {}
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or not (unit is Node2D):
			continue
		seen[unit.get_instance_id()] = true
		_refresh_unit(unit as Node2D)
	for id in _views.keys():
		if not seen.has(id):
			(_views[id] as Node).queue_free()
			_views.erase(id)
	_log_census(seen.size())
	_frames += 1
	if self_test_pick_frame > 0 and _frames == self_test_pick_frame:
		_pick_at(get_viewport().get_visible_rect().size * 0.5)


## One line whenever the drawn population changes, so a headless or short run leaves
## evidence that the shell really read the sim rather than rendering an empty scene.
func _log_census(unit_count: int) -> void:
	var bodies: int = 0
	for mmi in _views.values():
		bodies += (mmi as MultiMeshInstance3D).multimesh.instance_count
	if unit_count == _last_units and bodies == _last_bodies:
		return
	_last_units = unit_count
	_last_bodies = bodies
	print("[shell] units=%d soldier-instances=%d" % [unit_count, bodies])


func _refresh_unit(unit: Node2D) -> void:
	var bodies: PackedVector2Array = _body_positions(unit)
	var mmi: MultiMeshInstance3D = _view_for(unit)
	var mm: MultiMesh = mmi.multimesh
	if mm.instance_count != bodies.size():
		mm.instance_count = bodies.size()
	for i in range(bodies.size()):
		mm.set_instance_transform(i, Transform3D(Basis(), _to_metres(bodies[i])))


## Read the sim's published per-soldier bodies. `_sim_soldier_pos` is the
## parent-local array scripts/Unit.gd documents as the one-way render contract; a
## production shell would want a public accessor for it rather than reaching in.
## A far-tier unit simulates no bodies, so fall back to its formation grid.
func _body_positions(unit: Node2D) -> PackedVector2Array:
	var raw: Variant = unit.get("_sim_soldier_pos")
	if raw is PackedVector2Array and not (raw as PackedVector2Array).is_empty():
		return raw as PackedVector2Array
	if unit.has_method("soldier_world_slots"):
		var count: Variant = unit.get("soldiers")
		if count is int and int(count) > 0:
			return unit.call("soldier_world_slots", int(count)) as PackedVector2Array
	return PackedVector2Array()


## The one unit conversion in the spike, at the render boundary: sim world units
## in, metres out, per docs/units-convention.md. The sim itself never sees metres.
func _to_metres(local_wu: Vector2) -> Vector3:
	var wu: Vector2 = local_wu
	return Vector3(wu.x * WorldScaleRef.M_PER_WU, soldier_size_m.y * 0.5, wu.y * WorldScaleRef.M_PER_WU)


func _view_for(unit: Node2D) -> MultiMeshInstance3D:
	var id: int = unit.get_instance_id()
	if _views.has(id):
		return _views[id] as MultiMeshInstance3D
	var mesh := BoxMesh.new()
	mesh.size = soldier_size_m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_crowd_root.add_child(mmi)
	_views[id] = mmi
	return mmi


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_pick_at(mb.position)


## The pick path itself, shared by the left-click handler and the self-test frame
## so a non-interactive run exercises exactly the code a click would.
func _pick_at(screen_pos: Vector2) -> void:
	var hit: Variant = _camera.call("ground_point", screen_pos, 0.0)
	if hit == null:
		print("[shell] pick missed the ground plane")
		return
	var ground_m: Vector3 = hit as Vector3
	# Through WorldScale's own boundary helper rather than a bare multiplication, per
	# docs/units-convention.md. This runs on a click, not in the tick loop, so the
	# helper's hot-loop caveat does not apply.
	var wu := Vector2(WorldScaleRef.m_to_wu(ground_m.x), WorldScaleRef.m_to_wu(ground_m.z))
	print("[shell] pick %.1f, %.1f m -> %.1f, %.1f wu" % [ground_m.x, ground_m.z, wu.x, wu.y])
