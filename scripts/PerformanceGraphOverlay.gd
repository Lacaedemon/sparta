class_name PerformanceGraphOverlay
extends Control
## Live-updating performance graph overlay displaying rolling history of rendering FPS
## and simulation tick-rate (TPS).

signal history_updated

const DEFAULT_HISTORY_SIZE := 60
const DEFAULT_GRAPH_SIZE := Vector2(220.0, 90.0)

var history_size: int = DEFAULT_HISTORY_SIZE:
	set(v):
		history_size = maxi(10, v)
		_trim_history()
		queue_redraw()

var show_legend: bool = true:
	set(v):
		show_legend = v
		queue_redraw()

var fps_history: Array[float] = []
var tick_history: Array[float] = []

var _bg_color := Color(0.08, 0.1, 0.14, 0.85)
var _border_color := Color(0.3, 0.4, 0.55, 0.6)
var _grid_color := Color(0.4, 0.5, 0.6, 0.2)
var _fps_line_color := Color(0.2, 0.85, 1.0, 0.95)
var _tick_line_color := Color(0.35, 0.95, 0.55, 0.95)
var _text_color := Color(0.9, 0.95, 1.0, 0.9)


func _init(p_history_size: int = DEFAULT_HISTORY_SIZE) -> void:
	history_size = p_history_size
	custom_minimum_size = DEFAULT_GRAPH_SIZE


func add_sample(fps: float, tick_rate: float) -> void:
	fps_history.append(maxf(0.0, fps))
	tick_history.append(maxf(0.0, tick_rate))
	_trim_history()
	queue_redraw()
	history_updated.emit()


func clear_history() -> void:
	fps_history.clear()
	tick_history.clear()
	queue_redraw()


func _trim_history() -> void:
	while fps_history.size() > history_size:
		fps_history.pop_front()
	while tick_history.size() > history_size:
		tick_history.pop_front()


func _draw() -> void:
	var size_rect := Rect2(Vector2.ZERO, size)
	draw_rect(size_rect, _bg_color)
	draw_rect(size_rect, _border_color, false, 1.5)

	# Draw grid lines at 25%, 50%, 75% height
	for i in range(1, 4):
		var y := size.y * (float(i) / 4.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), _grid_color, 1.0)

	var max_val := 120.0
	for v in fps_history:
		if v > max_val:
			max_val = v
	for v in tick_history:
		if v > max_val:
			max_val = v

	_draw_series(fps_history, max_val, _fps_line_color)
	_draw_series(tick_history, max_val, _tick_line_color)

	if show_legend and not fps_history.is_empty():
		var cur_fps: float = fps_history.back()
		var cur_ticks: float = tick_history.back()
		var font := get_theme_default_font()
		var font_size := 11
		var fps_str := "FPS: %d" % roundi(cur_fps)
		var tick_str := "TPS: %d" % roundi(cur_ticks)
		draw_string(font, Vector2(6, 14), fps_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _fps_line_color)
		draw_string(font, Vector2(70, 14), tick_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _tick_line_color)


func _draw_series(values: Array[float], max_val: float, color: Color) -> void:
	var count := values.size()
	if count < 2 or max_val <= 0.0:
		return
	var step_x := size.x / float(history_size - 1)
	var start_idx := history_size - count
	var points := PackedVector2Array()
	for i in range(count):
		var x := float(start_idx + i) * step_x
		var norm_y := clampf(values[i] / max_val, 0.0, 1.0)
		var y := size.y - (norm_y * (size.y - 18.0) + 4.0)
		points.append(Vector2(x, y))
	draw_polyline(points, color, 2.0)
