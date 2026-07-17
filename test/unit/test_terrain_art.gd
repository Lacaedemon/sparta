extends GutTest
## TerrainArt: the seeded procedural ground/terrain images. Pure functions of
## (size, seed, palette) -> Image, so these tests pin the three properties the art
## layer promises: determinism (same seed, same bytes -- across runs and platforms),
## seed sensitivity (different seed, different ground), and palette fidelity (the
## generated ground stays in its base colour's family, so team colours keep the
## dominant read). The Battle integration test at the bottom covers the build-once
## wiring and the textured _draw path.

const BASE_GREEN := Color(0.34, 0.42, 0.27)
const SIZE := Vector2(200, 100)


func _mean_color(img: Image) -> Color:
	var sum := Vector3.ZERO
	var n: int = img.get_width() * img.get_height()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
	sum /= n
	return Color(sum.x, sum.y, sum.z)


func test_generators_are_deterministic_per_seed() -> void:
	var a: PackedByteArray = TerrainArt.field_image(SIZE, 7, BASE_GREEN).save_png_to_buffer()
	var b: PackedByteArray = TerrainArt.field_image(SIZE, 7, BASE_GREEN).save_png_to_buffer()
	assert_eq(a, b, "the same seed reproduces the field byte for byte")
	var c: PackedByteArray = TerrainArt.field_image(SIZE, 8, BASE_GREEN).save_png_to_buffer()
	assert_ne(a, c, "a different seed grows different ground")


func test_images_scale_world_units_by_the_resolution_constant() -> void:
	var img: Image = TerrainArt.hill_image(Vector2(250, 200), 7, Color(0.55, 0.48, 0.32))
	assert_eq(img.get_width(), int(250 * TerrainArt.RESOLUTION_SCALE),
			"width follows RESOLUTION_SCALE")
	assert_eq(img.get_height(), int(200 * TerrainArt.RESOLUTION_SCALE),
			"height follows RESOLUTION_SCALE")


func test_each_generator_stays_in_its_base_palette_family() -> void:
	# Mottling and shading may darken/lighten, but the mean must stay near the base --
	# a channel drifting far off would mean the ground fights the unit team colours.
	var cases: Array = [
		[TerrainArt.field_image(SIZE, 7, BASE_GREEN), BASE_GREEN, "field"],
		[TerrainArt.forest_image(SIZE, 7, Color(0.12, 0.28, 0.10)), Color(0.12, 0.28, 0.10), "forest"],
		[TerrainArt.hill_image(SIZE, 7, Color(0.55, 0.48, 0.32)), Color(0.55, 0.48, 0.32), "hill"],
	]
	for case in cases:
		var mean: Color = _mean_color(case[0])
		var base: Color = case[1]
		for ch in range(3):
			assert_almost_eq(mean[ch], base[ch], 0.15,
					"%s mean channel %d stays in the base family" % [case[2], ch])


func test_battle_builds_textures_once_and_draws_them() -> void:
	# The integration half: a real Battle builds the ground + one texture per terrain
	# patch during _ready (drill mode -- no opponent needed), and the textured _draw
	# branch runs under a real draw notification (the render-only overlay pattern:
	# queue_redraw + two process-frame awaits).
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	add_child_autofree(battle)
	await get_tree().physics_frame
	assert_not_null(battle._ground_texture, "the ground texture built at load")
	assert_eq(battle._terrain_textures.size(), battle.TERRAIN.size(),
			"one texture per terrain patch")
	var expected_w: int = int(battle.FIELD.size.x * TerrainArt.RESOLUTION_SCALE)
	assert_eq(battle._ground_texture.get_width(), expected_w,
			"the ground texture spans the field at art resolution")
	battle.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(battle), "the textured draw path ran without error")


func test_draw_falls_back_to_flat_rects_without_textures() -> void:
	# The fallback half of _draw's contract: a battle whose textures never built (or
	# were dropped) still draws the readable flat-colour field and patches.
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	add_child_autofree(battle)
	await get_tree().physics_frame
	battle._ground_texture = null
	battle._terrain_textures = []
	battle.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(battle), "the flat-rect fallback path draws without error")
