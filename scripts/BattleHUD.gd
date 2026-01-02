# BattleHUD.gd
# Simple HUD + input handler for selecting units and issuing move commands by clicking the terrain.
# Left-click to select a unit (must be owned by your peer), or click on empty ground to issue a move for the selected unit.

extends CanvasLayer
class_name BattleHUD

@export var select_radius: float = 2.0   # meters for selecting a unit near the click
var selected_unit: Node = null

# Visual marker for move target (created on demand)
var move_marker: MeshInstance3D = null

func _ready():
    # create a simple spherical marker for move target (hidden until used)
    move_marker = MeshInstance3D.new()
    var sphere = SphereMesh.new()
    sphere.radius = 0.15
    sphere.height = 0.15
    move_marker.mesh = sphere
    move_marker.visible = false
    # small material for visibility
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.9, 0.2)
    mat.metallic = 0.1
    move_marker.material_override = mat
    # add marker to the Battle root (scene world)
    var battle_root = get_tree().current_scene.get_node_or_null("Battle")
    if not battle_root:
        # fallback: add to root
        get_tree().current_scene.add_child(move_marker)
    else:
        battle_root.add_child(move_marker)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.LEFT:
        _on_left_click()

func _on_left_click() -> void:
    var viewport = get_viewport()
    var cam = viewport.get_camera_3d()
    if not cam:
        return
    var mouse_pos = viewport.get_mouse_position()
    var from = cam.project_ray_origin(mouse_pos)
    var dir = cam.project_ray_direction(mouse_pos)
    var to = from + dir * 2000.0

    # perform world raycast to find ground hit
    var space_state = get_world_3d().direct_space_state
    var hit = space_state.intersect_ray(from, to, [], collision_mask=0x7FFFFFFF)
    if not hit:
        return
    var hit_pos: Vector3 = hit.position

    # Try to select a nearby unit (owned by this peer)
    var my_id = get_tree().get_multiplayer().get_unique_id()
    var best_unit := null
    var best_dist = 99999.0
    for u in get_tree().get_nodes_in_group("units"):
        if not is_instance_valid(u):
            continue
        # optional: only allow selecting your own units
        if int(u.owner_peer) != int(my_id):
            continue
        var d = u.global_transform.origin.distance_to(hit_pos)
        if d < best_dist and d <= select_radius:
            best_unit = u
            best_dist = d

    if best_unit:
        selected_unit = best_unit
        _show_selection_feedback(selected_unit)
        # clicking on a unit selects it but does not issue a move
        return

    # If no unit selected and player has a previously selected unit, issue move
    if selected_unit and is_instance_valid(selected_unit):
        selected_unit.request_move(hit_pos)
        _show_move_marker(hit_pos)
    else:
        # nothing selected -> optionally select nearest owned unit to click point even if slightly out of radius
        var fallback_best := null
        var fallback_dist = 99999.0
        for u in get_tree().get_nodes_in_group("units"):
            if not is_instance_valid(u):
                continue
            if int(u.owner_peer) != int(my_id):
                continue
            var d = u.global_transform.origin.distance_to(hit_pos)
            if d < fallback_dist:
                fallback_best = u
                fallback_dist = d
        if fallback_best and fallback_dist <= select_radius * 2.0:
            selected_unit = fallback_best
            _show_selection_feedback(selected_unit)
        else:
            # nothing to do
            pass

func _show_selection_feedback(unit: Node) -> void:
    # Minimal feedback: print and (optionally) place move marker on the unit
    if not is_instance_valid(unit):
        return
    print("Selected unit:", unit.name, "id=", unit.unit_id)
    # show marker at unit to indicate selection
    if move_marker:
        move_marker.global_transform.origin = unit.global_transform.origin
        move_marker.visible = true

func _show_move_marker(pos: Vector3) -> void:
    if not move_marker:
        return
    move_marker.global_transform.origin = pos
    move_marker.visible = true
    # hide marker after a short delay
    call_deferred("_hide_move_marker_after_frame")

func _hide_move_marker_after_frame() -> void:
    await get_tree().process_frame
    # keep visible for a couple frames so it's visible
    await get_tree().create_timer(0.5).timeout
    if move_marker:
        move_marker.visible = false