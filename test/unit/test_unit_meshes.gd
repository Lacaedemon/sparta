extends GutTest
## Mark-glyph geometry (#400): the archer kite and the spearmen dart must be *directional*
## (reach further toward +X than back) so rotating each instance by its soldier's facing
## reads as an arrow, AND compact (no longer along the facing axis than the infantry
## pointer) so a rotated rank can't merge into a bar — the failure of the old elongated
## rect / symmetric diamond.

const R: float = 1.7


## Longest extent of a mesh along the +X / -X facing axis (front reach + rear reach).
func _facing_span(mesh: ArrayMesh) -> float:
	return _max_x(mesh) - _min_x(mesh)


func _verts(mesh: ArrayMesh) -> PackedVector2Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _max_x(mesh: ArrayMesh) -> float:
	var m: float = -INF
	for v in _verts(mesh):
		m = maxf(m, v.x)
	return m


func _min_x(mesh: ArrayMesh) -> float:
	var m: float = INF
	for v in _verts(mesh):
		m = minf(m, v.x)
	return m


func _max_abs_y(mesh: ArrayMesh) -> float:
	var m: float = 0.0
	for v in _verts(mesh):
		m = maxf(m, absf(v.y))
	return m


# --- archer kite -------------------------------------------------------------

func test_kite_points_forward_more_than_it_reaches_back() -> void:
	var kite := UnitMeshes.kite_mesh(R)
	assert_gt(_max_x(kite), absf(_min_x(kite)),
		"the front tip extends further along +X than the rear, so the kite reads directional")


func test_kite_front_reach_exceeds_its_half_width() -> void:
	# The cross-axis must stay shorter than the forward reach: a rank of these rotated to
	# ~90° can't merge into a flat horizontal bar the way the old symmetric diamond did.
	var kite := UnitMeshes.kite_mesh(R)
	assert_gt(_max_x(kite), _max_abs_y(kite),
		"forward reach is longer than half-width, so a rotated rank can't flatten into a stripe")


func test_kite_mesh_is_cached() -> void:
	assert_eq(UnitMeshes.kite_mesh(R), UnitMeshes.kite_mesh(R),
		"the same radius returns the shared cached mesh")


func test_kite_is_no_longer_along_facing_than_the_infantry_pointer() -> void:
	# Compactness guard: the kite's facing-axis span must not exceed the infantry pointer's,
	# so it can't stripe any worse than the glyph the issue calls clean at any angle.
	assert_lte(_facing_span(UnitMeshes.kite_mesh(R)), _facing_span(UnitMeshes.pointer_mesh(R)) + 0.01,
		"the kite stays at least as compact along facing as the infantry pointer")


# --- spearmen dart -----------------------------------------------------------

func test_dart_points_forward_more_than_it_reaches_back() -> void:
	var dart := UnitMeshes.dart_mesh(R)
	assert_gt(_max_x(dart), absf(_min_x(dart)),
		"the dart's tip extends further along +X than its flat rear, so it reads directional")


func test_dart_is_no_longer_along_facing_than_the_infantry_pointer() -> void:
	assert_lte(_facing_span(UnitMeshes.dart_mesh(R)), _facing_span(UnitMeshes.pointer_mesh(R)) + 0.01,
		"the dart stays at least as compact along facing as the infantry pointer")


func test_dart_front_reach_exceeds_its_half_width() -> void:
	# The 90°-rotation anti-stripe guard (parallel to the kite's): forward reach must beat
	# half-width, so a rank rotated sideways can't merge into a flat horizontal bar.
	var dart := UnitMeshes.dart_mesh(R)
	assert_gt(_max_x(dart), _max_abs_y(dart),
		"forward reach is longer than half-width, so a rotated rank can't flatten into a stripe")


func test_dart_mesh_is_cached() -> void:
	assert_eq(UnitMeshes.dart_mesh(R), UnitMeshes.dart_mesh(R),
		"the same radius returns the shared cached mesh")


# --- weapon/shield hold-angle orientation (docs/soldier-loadout-design.md phase 3) -----

func test_rotate_polys_about_is_a_no_op_at_zero_angle() -> void:
	# 0.0 must reproduce the originally-authored polygon bit-for-bit (returns the input
	# array unchanged, not a rotated copy), so a type left at LoadoutRegistry's neutral
	# default renders identically to the pre-phase-3 baked orientation.
	var poly := PackedVector2Array([Vector2(1, 0), Vector2(0, 1)])
	var out: Array = UnitMeshes._rotate_polys_about([poly], Vector2(3, 4), 0.0)
	assert_eq(out[0], poly)


func test_rotate_polys_about_rotates_around_the_given_pivot() -> void:
	# (2,0) about pivot (1,0) by 90 degrees: the relative vector (1,0) rotates to (0,1),
	# then the pivot is added back -> (1,1).
	var poly := PackedVector2Array([Vector2(2, 0)])
	var out: Array = UnitMeshes._rotate_polys_about([poly], Vector2(1, 0), PI * 0.5)
	var rotated: Vector2 = out[0][0]
	assert_almost_eq(rotated.x, 1.0, 0.0001)
	assert_almost_eq(rotated.y, 1.0, 0.0001)


func test_spear_polys_hold_angle_zero_matches_the_originally_authored_shaft() -> void:
	# Regression guard: passing the default hold_angle must reproduce the exact vertices
	# _spear_polys always returned, before the hold-angle parameter existed.
	var polys: Array = UnitMeshes._spear_polys(R)
	var shaft: PackedVector2Array = polys[0]
	assert_eq(shaft[0], Vector2(0.78 * R, -2.0 * R))
	assert_eq(shaft[2], Vector2(1.0 * R, 1.55 * R))


func test_spear_polys_hold_angle_reorients_the_shaft() -> void:
	var rest: Array = UnitMeshes._spear_polys(R)
	var tilted: Array = UnitMeshes._spear_polys(R, deg_to_rad(20.0))
	var rest_shaft: PackedVector2Array = rest[0]
	var tilted_shaft: PackedVector2Array = tilted[0]
	assert_ne(rest_shaft[0], tilted_shaft[0], "a nonzero hold angle moves the shaft's vertices")


func test_shield_polys_hold_angle_zero_matches_the_originally_authored_shield() -> void:
	var polys: Array = UnitMeshes._shield_polys(R)
	var shield: PackedVector2Array = polys[0]
	assert_eq(shield[0], Vector2(-1.3 * R, -0.7 * R))
	assert_eq(shield[3], Vector2(-0.9 * R, 0.7 * R))


func test_shield_polys_hold_angle_reorients_the_shield() -> void:
	var rest: Array = UnitMeshes._shield_polys(R)
	var tilted: Array = UnitMeshes._shield_polys(R, deg_to_rad(20.0))
	var rest_shield: PackedVector2Array = rest[0]
	var tilted_shield: PackedVector2Array = tilted[0]
	assert_ne(rest_shield[0], tilted_shield[0], "a nonzero hold angle moves the shield's vertices")


func test_figure_mesh_hold_angle_participates_in_the_cache_key() -> void:
	# A different weapon hold angle must bake a genuinely different mesh, not collide in
	# the shared cache with the neutral orientation.
	var neutral := UnitMeshes.figure_mesh(false, UnitMeshes.FOOT_SPEAR, R, false, false)
	var tilted := UnitMeshes.figure_mesh(false, UnitMeshes.FOOT_SPEAR, R, false, false, deg_to_rad(20.0))
	assert_true(neutral != tilted, "a different weapon hold angle bakes a different mesh")


func test_figure_mesh_hold_angle_defaults_reproduce_the_pre_phase_3_mesh() -> void:
	# Omitting the trailing hold-angle args (every pre-phase-3 call site) must still return
	# the SAME cached mesh as passing 0.0 explicitly.
	var omitted := UnitMeshes.figure_mesh(false, UnitMeshes.FOOT_INFANTRY, R, false, false)
	var explicit_zero := UnitMeshes.figure_mesh(false, UnitMeshes.FOOT_INFANTRY, R, false, false, 0.0, 0.0)
	assert_eq(omitted, explicit_zero)


# --- figure shading and contact shadows (vertex colours) ----------------------

func _surface_colors(mesh: ArrayMesh) -> PackedColorArray:
	var arrays: Array = mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()


func test_figure_body_meshes_carry_part_shading_as_vertex_colours() -> void:
	# Body figures bake per-part shading (values around white, multiplying with the
	# instance team tint) -- so the colour array exists and holds more than one value.
	for is_cav in [false, true]:
		var body: ArrayMesh = UnitMeshes.figure_mesh(is_cav, UnitMeshes.FOOT_SPEAR, R, false, false)
		var colors: PackedColorArray = _surface_colors(body)
		assert_gt(colors.size(), 0, "body mesh carries vertex colours (cav=%s)" % is_cav)
		var distinct: Dictionary = {}
		for c in colors:
			distinct[c] = true
		assert_gt(distinct.size(), 2,
			"shading distinguishes several parts, not one flat value (cav=%s)" % is_cav)


func test_figure_body_first_part_is_the_translucent_contact_shadow() -> void:
	# The shadow ellipse is inserted first so the figure's own parts overdraw it: its
	# vertices are black with partial alpha, unlike every shading value (opaque, near
	# white).
	var body: ArrayMesh = UnitMeshes.figure_mesh(false, UnitMeshes.FOOT_INFANTRY, R, false, false)
	var colors: PackedColorArray = _surface_colors(body)
	assert_almost_eq(colors[0].r, 0.0, 0.001, "shadow is black")
	assert_lt(colors[0].a, 1.0, "and translucent")
	assert_gt(colors[0].a, 0.0, "but visible")


func test_figure_outline_meshes_stay_flat_and_shadowless() -> void:
	# The outline is a rim: no vertex colours (a scaled shadow copy would ring the
	# figure, and shading a rim just muddies it).
	var outline: ArrayMesh = UnitMeshes.figure_mesh(false, UnitMeshes.FOOT_SPEAR, R, true, false)
	assert_eq(_surface_colors(outline).size(), 0, "outline carries no vertex colours")


func test_mark_meshes_stay_flat() -> void:
	# The zoomed-out marks are unchanged by the figure shading work.
	assert_eq(_surface_colors(UnitMeshes.pointer_mesh(R)).size(), 0, "pointer stays flat")
	assert_eq(_surface_colors(UnitMeshes.dart_mesh(R)).size(), 0, "dart stays flat")
	assert_eq(_surface_colors(UnitMeshes.kite_mesh(R)).size(), 0, "kite stays flat")


func test_horse_figure_spans_a_real_warhorse_nose_to_tail() -> void:
	# The mounted silhouette reads at real warhorse length (2.4-3.0 m) at the actual
	# cavalry mark radius, rather than the ~1.8 m the raw authored parts span -- the
	# per-type grid pitch gives the figure the room.
	var polys: Array = UnitMeshes._horse_figure_polys(Unit.CAV_MARK_RADIUS)
	var min_x := INF
	var max_x := -INF
	for poly in polys:
		for v in poly:
			min_x = minf(min_x, v.x)
			max_x = maxf(max_x, v.x)
	var span_m: float = (max_x - min_x) / WorldScale.WU_PER_M
	assert_between(span_m, 2.4, 3.0,
			"nose-to-tail span %.2f m should sit in the real warhorse range" % span_m)


func test_cavalry_contact_shadow_tracks_the_figure_scale() -> void:
	# The shadow ellipse (first part of the body mesh) must sit under the scaled
	# figure's hooves, not at the unscaled authored position -- its centroid y equals
	# the authored 1.3 mark-radii offset lifted by MOUNT_FIGURE_SCALE.
	var body: ArrayMesh = UnitMeshes.figure_mesh(true, UnitMeshes.FOOT_INFANTRY, R, false, false)
	var arrays: Array = body.surface_get_arrays(0)
	var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = _surface_colors(body)
	var sum_y := 0.0
	var n := 0
	for i in range(verts.size()):
		if colors[i].r < 0.001 and colors[i].a < 1.0:   # shadow vertices are translucent black
			sum_y += verts[i].y
			n += 1
	assert_gt(n, 0, "found the shadow part's vertices")
	assert_almost_eq(sum_y / n, 1.3 * R * UnitMeshes.MOUNT_FIGURE_SCALE, 0.05,
			"shadow centroid rides the scaled hoof line")
