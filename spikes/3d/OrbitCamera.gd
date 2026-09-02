extends Camera3D
## THROWAWAY SPIKE (3D-0b). Not production code, not covered by the GUT suite.
##
## Minimal Total War-style orbit camera: full yaw orbit, clamped pitch, zoom, and
## keyboard pan, plus the ray-to-ground picking the projection shell needs in place
## of SelectionManager._cursor_world(). Proves the camera model and the picking maths
## only -- it deliberately does NOT reproduce CameraController.gd's edge pan, bounds,
## smoothing, or replay presentation track.
##
## Controls: middle-drag orbits, wheel zooms, arrow keys pan, R resets yaw and focus.
## The pan reads the built-in ui_left/ui_right/ui_up/ui_down actions, and this project
## defines no [input] section, so Godot's defaults apply: arrow keys and gamepad, no
## WASD. The shipped camera binds WASD by raw keycode instead (CameraController.gd);
## the spike deliberately does not, so those keys move nothing here.

## Point the camera orbits, in metres. Panning moves this. The projection shell
## overwrites it with the battlefield centre before the first frame, so the spike
## does not open on an empty corner of the ground plane.
@export var focus_m: Vector3 = Vector3.ZERO
## Distance from the focus, in metres.
@export var distance_m: float = 60.0
@export var min_distance_m: float = 8.0
@export var max_distance_m: float = 240.0
## Fraction of the current distance one wheel notch adds or removes.
@export var zoom_step_fraction: float = 0.12
## Yaw about +Y, radians. Zero puts the camera on the -Z side of the focus.
@export var yaw_rad: float = 0.0
## Pitch below the horizon, radians, clamped to the range below.
@export var pitch_rad: float = deg_to_rad(-45.0)
@export var min_pitch_rad: float = deg_to_rad(-85.0)
@export var max_pitch_rad: float = deg_to_rad(-12.0)
## Radians per pixel of middle-drag.
@export var orbit_sensitivity_rad_per_px: float = 0.006
## Metres per second of keyboard pan, at the reference distance below.
@export var pan_speed_m_per_s: float = 40.0
## Distance at which pan_speed_m_per_s applies; pan scales with distance so a
## zoomed-out camera crosses the field in the same number of seconds.
@export var pan_reference_distance_m: float = 60.0

var _orbiting: bool = false
var _home_focus_m: Vector3 = Vector3.ZERO


func _ready() -> void:
	_home_focus_m = focus_m
	_apply()


## Recentre the camera on a new home point, in metres, and make R return to it.
## The shell calls this once the sim scene has published its battlefield rect.
func set_home_focus(new_focus_m: Vector3) -> void:
	_home_focus_m = new_focus_m
	focus_m = new_focus_m
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance_m = clampf(distance_m * (1.0 - zoom_step_fraction), min_distance_m, max_distance_m)
			_apply()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance_m = clampf(distance_m * (1.0 + zoom_step_fraction), min_distance_m, max_distance_m)
			_apply()
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		yaw_rad = wrapf(yaw_rad - mm.relative.x * orbit_sensitivity_rad_per_px, -PI, PI)
		pitch_rad = clampf(pitch_rad - mm.relative.y * orbit_sensitivity_rad_per_px, min_pitch_rad, max_pitch_rad)
		_apply()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_R:
			yaw_rad = 0.0
			focus_m = _home_focus_m
			_apply()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	# get_axis(negative, positive): the positive action is named second, so these
	# read +1 for right and +1 for up the screen, matching CameraController.gd.
	move.x = Input.get_axis("ui_left", "ui_right")
	move.y = Input.get_axis("ui_down", "ui_up")
	if move == Vector2.ZERO:
		return
	var scale_factor: float = distance_m / maxf(pan_reference_distance_m, 0.001)
	var step: float = pan_speed_m_per_s * scale_factor * delta
	# Pan in the camera's own ground plane, so the keys stay intuitive after an orbit.
	# These are the camera basis vectors flattened onto the ground: look_at() builds
	# basis.x as up.cross(-forward), which points along -cos(yaw) rather than +cos(yaw),
	# so screen-right is the negation of the naive right-hand guess.
	var forward := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
	var right := Vector3(-cos(yaw_rad), 0.0, sin(yaw_rad))
	focus_m += (right * move.x + forward * move.y) * step
	_apply()


## Analytic ray-plane intersection against the flat ground (y = ground_y_m). This is
## the spike's stand-in for SelectionManager._cursor_world(): it returns a ground
## point in metres, which the shell converts back to sim world units. A heightfield
## world would walk the ray instead (design document, phase 3D-4).
func ground_point(screen_pos: Vector2, ground_y_m: float = 0.0) -> Variant:
	var origin: Vector3 = project_ray_origin(screen_pos)
	var dir: Vector3 = project_ray_normal(screen_pos)
	if absf(dir.y) < 0.00001:
		return null
	var t: float = (ground_y_m - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


func _apply() -> void:
	var dir := Vector3(0.0, sin(pitch_rad), cos(pitch_rad)).rotated(Vector3.UP, yaw_rad)
	position = focus_m - dir * distance_m
	look_at(focus_m, Vector3.UP)
