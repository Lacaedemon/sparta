extends GutTest
## Live-updating performance graph overlay unit tests.

const SettingsScript = preload("res://scripts/Settings.gd")


func test_performance_graph_overlay_sample_and_trim() -> void:
	var graph := PerformanceGraphOverlay.new(5)
	add_child_autofree(graph)

	assert_eq(graph.history_size, 5)
	assert_true(graph.fps_history.is_empty())

	for i in range(10):
		graph.add_sample(60.0 + i, 30.0 + i)

	assert_eq(graph.fps_history.size(), 5, "samples trim to history_size")
	assert_eq(graph.tick_history.size(), 5)
	assert_eq(graph.fps_history.back(), 69.0)
	assert_eq(graph.tick_history.back(), 39.0)

	graph.clear_history()
	assert_true(graph.fps_history.is_empty(), "clear_history resets history arrays")


func test_settings_show_performance_graph_defaults_off() -> void:
	assert_false(SettingsScript.show_performance_graph, "show_performance_graph defaults to false")
