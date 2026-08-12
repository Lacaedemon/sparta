extends GutTest
## Fallen (Stage C): the cosmetic "men fall" body markers dropped where melee casualties
## occur -- one mark per REAL fallen-soldier position, never a synthetic scatter. It's a
## render-time visual, but the spawn geometry and self-cleanup are plain logic worth pinning
## (the drawing/fade is verified visually / in the demo clip).


func test_spawn_adds_one_node_with_a_mark_per_real_position() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	var positions := PackedVector2Array([Vector2(60, 70), Vector2(64, 72), Vector2(58, 68)])
	Fallen.spawn(parent, positions, Color.RED)
	assert_eq(parent.get_child_count(), 1, "spawn adds exactly one fallen-heap node")
	var fx: Fallen = parent.get_child(0)
	assert_eq(fx.global_position, positions[0],
		"the heap anchors at the first fallen soldier's own real position")
	assert_eq(fx._marks.size(), 3, "one mark per real fallen-soldier position")


func test_marks_sit_at_their_own_real_positions_not_a_synthetic_scatter() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	var positions := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(0, 10)])
	Fallen.spawn(parent, positions, Color.WHITE)
	var fx: Fallen = parent.get_child(0)
	# Marks are stored relative to the node's own origin (positions[0]) -- each one is the
	# EXACT offset of a real fallen soldier, not a golden-angle or other synthetic pattern.
	assert_eq(fx._marks[0], Vector2(0, 0))
	assert_eq(fx._marks[1], Vector2(10, 0))
	assert_eq(fx._marks[2], Vector2(0, 10))


func test_empty_positions_spawns_nothing() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	Fallen.spawn(parent, PackedVector2Array(), Color.WHITE)
	assert_eq(parent.get_child_count(), 0, "no fallen bodies means no heap spawns")


func test_mark_count_is_capped_for_a_pathological_mass_death() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	var positions := PackedVector2Array()
	for i in range(1000):
		positions.push_back(Vector2(i, 0))
	Fallen.spawn(parent, positions, Color.WHITE)
	var fx: Fallen = parent.get_child(0)
	assert_eq(fx._marks.size(), Fallen.MAX_MARKS,
		"an extreme mass-death event caps draw calls defensively")


func test_cavalry_casualties_leave_larger_bodies() -> void:
	# A cavalry heap uses the bigger cavalry mark size, so fallen horses read as bigger
	# than fallen foot soldiers -- matching the live marks.
	var foot_parent := Node2D.new()
	add_child_autofree(foot_parent)
	Fallen.spawn(foot_parent, PackedVector2Array([Vector2.ZERO]), Color.WHITE)
	var foot: Fallen = foot_parent.get_child(0)

	var cav_parent := Node2D.new()
	add_child_autofree(cav_parent)
	Fallen.spawn(cav_parent, PackedVector2Array([Vector2.ZERO]), Color.WHITE, Unit.CAV_MARK_RADIUS)
	var cav: Fallen = cav_parent.get_child(0)

	assert_gt(cav._mark_radius, foot._mark_radius, "cavalry casualties leave larger bodies")


func test_heap_frees_itself_after_its_lifetime() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	Fallen.spawn(parent, PackedVector2Array([Vector2.ZERO]), Color.WHITE)
	var fx: Fallen = parent.get_child(0)
	fx._process(0.01)
	assert_false(fx.is_queued_for_deletion(), "a fresh heap is still on the field")
	fx._process(Fallen.LIFETIME)   # age past its lifetime
	assert_true(fx.is_queued_for_deletion(), "a fully-faded heap frees itself")


func test_spawn_accepts_caller_configured_parameters() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	Fallen.spawn(parent, PackedVector2Array([Vector2.ZERO, Vector2(1, 1)]), Color.WHITE,
		Unit.MARK_RADIUS, 5.0, 0.8)
	var fx: Fallen = parent.get_child(0)
	assert_eq(fx._lifetime, 5.0, "custom lifetime is set")
	assert_eq(fx._fade_start, 0.8, "custom fade_start is set")
	assert_eq(fx._marks.size(), 2, "marks size reflects the real position count")
