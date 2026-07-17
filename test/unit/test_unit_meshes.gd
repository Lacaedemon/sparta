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
