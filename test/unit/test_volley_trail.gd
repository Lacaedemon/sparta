extends GutTest
## VolleyTrail: the cosmetic arrow-volley streak spawned by a ranged volley.
## It's a render-time visual, but the spawn geometry and self-cleanup are plain logic
## worth pinning (the drawing itself is verified visually / in the demo clip).


func test_spawn_adds_one_positioned_trail() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	VolleyTrail.spawn(parent, Vector2(10, 20), Vector2(50, 20), Color.RED)
	assert_eq(parent.get_child_count(), 1, "spawn adds exactly one trail node")
	var trail: VolleyTrail = parent.get_child(0)
	assert_eq(trail.global_position, Vector2(10, 20), "the trail starts at the shooter")
	assert_eq(trail._delta, Vector2(40, 0), "and points at the target")


func test_trail_frees_itself_after_its_lifetime() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	VolleyTrail.spawn(parent, Vector2.ZERO, Vector2(100, 0), Color.WHITE)
	var trail: VolleyTrail = parent.get_child(0)
	trail._process(0.01)
	assert_false(trail.is_queued_for_deletion(), "a fresh trail is still alive")
	trail._process(VolleyTrail.LIFETIME)   # age past its lifetime
	assert_true(trail.is_queued_for_deletion(), "an expired trail frees itself")


func test_spawn_accepts_caller_configured_parameters() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	VolleyTrail.spawn(parent, Vector2.ZERO, Vector2(100, 0), Color.WHITE, 0.8, 5, 10.0, 0.3, 0.25, 12)
	var trail: VolleyTrail = parent.get_child(0)
	assert_eq(trail._lifetime, 0.8, "custom lifetime is set")
	assert_eq(trail._streaks, 5, "custom streaks count is set")
	assert_eq(trail._spread, 10.0, "custom streak spread is set")
	assert_eq(trail._streak_len, 0.3, "custom streak_len is set")
	assert_eq(trail._arc_height, 0.25, "custom arc_height is set")
	assert_eq(trail._arc_steps, 12, "custom arc_steps is set")
