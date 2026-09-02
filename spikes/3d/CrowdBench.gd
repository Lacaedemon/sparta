extends Node3D
## THROWAWAY SPIKE (3D-0a). Not production code, not covered by the GUT suite.
##
## Measures MultiMeshInstance3D crowd throughput: N instances whose transforms are
## fully rewritten every frame, which is the worst case a projection shell would ever
## ask for (a real shell rewrites only dirty units). Prints a frame-rate summary and
## quits, so it can be driven from a script.
##
## Run (Compatibility, the CI floor):
##   godot --rendering-driver opengl3 --path . res://spikes/3d/CrowdBench.tscn
## Run (Forward+):
##   godot --rendering-method forward_plus --path . res://spikes/3d/CrowdBench.tscn
## Override the instance count with SPARTA_SPIKE_INSTANCES=1000.

## Instances to render. Every value here is caller-configurable (repo convention);
## the default is the design document's 1-2k crowd target.
@export var instance_count: int = 2000
## Seconds of rendering discarded before measuring, so shader compilation and the
## first-frame allocation spike do not land in the average.
@export var warmup_seconds: float = 2.0
## Seconds of frame times averaged into the reported numbers.
@export var measure_seconds: float = 8.0
## Half-extent of the square the crowd is scattered over, in metres.
@export var field_half_extent_m: float = 60.0
## Metres each instance sways per second, so every transform genuinely changes.
@export var sway_amplitude_m: float = 1.5

var _mm: MultiMesh
var _elapsed: float = 0.0
var _samples: PackedFloat32Array = PackedFloat32Array()
var _origins: PackedVector3Array = PackedVector3Array()
var _phases: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var env_count: String = OS.get_environment("SPARTA_SPIKE_INSTANCES")
	if env_count.is_valid_int():
		instance_count = maxi(1, int(env_count))
	# Uncap the frame rate: a vsynced run reports the monitor's refresh rate and says
	# nothing about headroom, which is the only thing this spike is measuring.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var mesh := BoxMesh.new()
	# A soldier-sized box: roughly 0.5 m across and 1.8 m tall.
	mesh.size = Vector3(0.5, 1.8, 0.5)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = instance_count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	add_child(mmi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 947
	for i in range(instance_count):
		var x: float = rng.randf_range(-field_half_extent_m, field_half_extent_m)
		var z: float = rng.randf_range(-field_half_extent_m, field_half_extent_m)
		_origins.push_back(Vector3(x, 0.9, z))
		_phases.push_back(rng.randf_range(0.0, TAU))
		_mm.set_instance_color(i, Color(0.7, 0.2 + 0.6 * rng.randf(), 0.3))
	print("[crowd-bench] instances=%d adapter=%s" % [instance_count, RenderingServer.get_video_adapter_name()])


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed
	for i in range(instance_count):
		var phase: float = _phases[i]
		var sway := Vector3(sin(t + phase), 0.0, cos(t + phase)) * sway_amplitude_m
		var basis := Basis(Vector3.UP, t * 0.5 + phase)
		_mm.set_instance_transform(i, Transform3D(basis, _origins[i] + sway))
	if _elapsed > warmup_seconds:
		_samples.push_back(delta)
	if _elapsed > warmup_seconds + measure_seconds:
		_report()
		get_tree().quit()


func _report() -> void:
	if _samples.is_empty():
		print("[crowd-bench] no samples collected")
		return
	var total: float = 0.0
	var worst: float = 0.0
	for s in _samples:
		total += s
		worst = maxf(worst, s)
	var mean: float = total / float(_samples.size())
	print("[crowd-bench] frames=%d mean=%.1f fps worst-frame=%.1f fps (%.2f ms)" % [
		_samples.size(), 1.0 / maxf(mean, 0.00001), 1.0 / maxf(worst, 0.00001), worst * 1000.0])
