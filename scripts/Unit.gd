# Unit.gd
# Minimal unit with server-side authoritative movement and client puppet state handling.

extends Node3D
class_name Unit

@export var move_speed: float = 6.0
var unit_id: int = 0
var owner_peer: int = 0

# server-only state
var server_target: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO

# client smoothing
var target_position: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO

func _ready():
    set_physics_process(true)
    # Add to "units" group so HUD can find and select units easily
    add_to_group("units")

# Called on server each simulation tick
func server_step(dt: float) -> void:
    # simple move toward target
    var dir = (server_target - global_transform.origin)
    var dist = dir.length()
    if dist > 0.1:
        dir = dir.normalized()
        velocity = dir * move_speed
        global_transform.origin += velocity * dt
    else:
        velocity = Vector3.ZERO

# Called by server to set movement target for this unit
func set_server_target(pos: Vector3) -> void:
    server_target = pos

# Client-side: apply authoritative state snapshot (from server)
func apply_puppet_state(pos: Vector3, vel: Vector3) -> void:
    # naive snap + simple smoothing
    global_transform.origin = pos
    last_velocity = vel

# Client function to ask server to move a unit. Sends RPC to server.
func request_move(target_pos: Vector3) -> void:
    var nm = get_node_or_null("/root/NetworkManager")
    # If NetworkManager exists and we're not host, send command to server
    if nm and not nm.is_host():
        # send to server Battle.gd's rpc_request_move_unit (server-authoritative)
        # rpc_id(1, ...) calls the RPC on the server (peer id 1 in ENet setup)
        rpc_id(1, "rpc_request_move_unit", unit_id, target_pos)
    else:
        # local singleplayer / host: set local server_target for direct testing
        set_server_target(target_pos)