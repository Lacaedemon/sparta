extends GutTest
## Campaign map substrate: the province polygon overlay (point-in-polygon lookup,
## adjacency, anchor points) and the per-campaign lat-long projection. Both are pure
## RefCounteds, so these run headless against small hand-made maps.

const CampaignGeography = preload("res://scripts/campaign/CampaignGeography.gd")
const CampaignProjection = preload("res://scripts/campaign/CampaignProjection.gd")
const CampaignLoader = preload("res://scripts/campaign/CampaignLoader.gd")

# Two unit squares side by side, plus a detached third: province 0 spans x 0-100,
# province 1 spans x 100-200, province 2 sits far to the south.
const SQUARE_SIDE := 100.0


func _map() -> Dictionary:
	return {
		"provinces": [
			{"id": 0, "name": "West", "adj": [1],
				"polygon": [[0, 0], [100, 0], [100, 100], [0, 100]]},
			{"id": 1, "name": "East", "adj": [0],
				"polygon": [[100, 0], [200, 0], [200, 100], [100, 100]]},
			{"id": 2, "name": "South", "adj": [],
				"polygon": [[0, 400], [100, 400], [100, 500], [0, 500]]},
		],
	}


func _geo() -> RefCounted:
	return CampaignGeography.new(_map())


func test_builds_every_province_in_map_order() -> void:
	var geo := _geo()
	assert_eq(geo.ids(), [0, 1, 2], "ids in map order")
	assert_true(geo.has_province(1), "a province the map declared")
	assert_false(geo.has_province(9), "one it did not")


func test_empty_map_builds_an_empty_overlay() -> void:
	var geo := CampaignGeography.new()
	assert_eq(geo.ids().size(), 0, "no provinces")
	assert_eq(geo.province_at(Vector2(10, 10)), CampaignGeography.NO_PROVINCE,
			"nothing to fall inside")


func test_malformed_entries_are_skipped_not_fatal() -> void:
	# A province with no id, and a second copy of an id already taken: the overlay
	# keeps the first declaration of each id and drops the rest rather than letting a
	# broken data file silently redefine a province's shape.
	var geo := CampaignGeography.new({
		"provinces": [
			{"id": 0, "adj": [], "polygon": [[0, 0], [100, 0], [100, 100], [0, 100]]},
			{"adj": [], "polygon": [[0, 0], [10, 0], [10, 10], [0, 10]]},
			{"id": 0, "adj": [], "polygon": [[500, 500], [600, 500], [600, 600]]},
		],
	})
	assert_eq(geo.ids(), [0], "one usable province out of three entries")
	assert_eq(geo.province_at(Vector2(50, 50)), 0, "the first declaration is the one kept")
	assert_eq(geo.province_at(Vector2(550, 530)), CampaignGeography.NO_PROVINCE,
			"the duplicate never became a province")


func test_province_at_resolves_a_position_to_its_province() -> void:
	var geo := _geo()
	assert_eq(geo.province_at(Vector2(50, 50)), 0, "inside the western square")
	assert_eq(geo.province_at(Vector2(150, 50)), 1, "inside the eastern one")
	assert_eq(geo.province_at(Vector2(50, 450)), 2, "inside the southern one")


func test_province_at_misses_outside_every_polygon() -> void:
	var geo := _geo()
	assert_eq(geo.province_at(Vector2(-10, 50)), CampaignGeography.NO_PROVINCE,
			"west of the map")
	assert_eq(geo.province_at(Vector2(150, 250)), CampaignGeography.NO_PROVINCE,
			"in the gap between the squares and the south")


func test_adjacency_is_the_political_graph() -> void:
	var geo := _geo()
	assert_eq(geo.neighbours(0), [1], "the western square borders the eastern one")
	assert_eq(geo.neighbours(2), [], "the southern one borders nothing")
	assert_true(geo.are_neighbours(1, 0), "adjacency reads both ways in this map")
	assert_false(geo.are_neighbours(0, 2), "detached provinces are not neighbours")


func test_neighbours_returns_a_copy() -> void:
	var geo := _geo()
	var first: Array = geo.neighbours(0)
	first.append(2)
	assert_eq(geo.neighbours(0), [1], "mutating the result does not corrupt the overlay")


func test_centre_is_the_loader_polygon_anchor() -> void:
	var geo := _geo()
	var centre: Vector2 = geo.centre(0)
	assert_almost_eq(centre.x, SQUARE_SIDE / 2.0, 0.001, "centred in x")
	assert_almost_eq(centre.y, SQUARE_SIDE / 2.0, 0.001, "centred in y")
	assert_eq(centre, CampaignLoader.polygon_centre(geo.polygon(0)),
			"one formula, shared with the loader's own label anchor")
	assert_eq(geo.centre(99), Vector2.ZERO, "an unknown province has no centre")


func test_polygon_reads_back_the_authored_shape() -> void:
	var geo := _geo()
	assert_eq(geo.polygon(0).size(), 4, "a square has four vertices")
	assert_eq(geo.polygon(99).size(), 0, "an unknown province has no shape")


func test_projection_origin_maps_to_the_plane_origin() -> void:
	var proj := CampaignProjection.new()
	var point: Vector2 = proj.to_plane(
			CampaignProjection.DEFAULT_ORIGIN_LAT, CampaignProjection.DEFAULT_ORIGIN_LON)
	assert_almost_eq(point.x, 0.0, 0.001, "no easting at the origin")
	assert_almost_eq(point.y, 0.0, 0.001, "no northing at the origin")


func test_projection_puts_north_up_and_east_right() -> void:
	var proj := CampaignProjection.new()
	var north: Vector2 = proj.to_plane(
			CampaignProjection.DEFAULT_ORIGIN_LAT + 1.0, CampaignProjection.DEFAULT_ORIGIN_LON)
	var east: Vector2 = proj.to_plane(
			CampaignProjection.DEFAULT_ORIGIN_LAT, CampaignProjection.DEFAULT_ORIGIN_LON + 1.0)
	assert_lt(north.y, 0.0, "further north is further up the screen")
	assert_almost_eq(north.x, 0.0, 0.001, "due north does not drift east")
	assert_gt(east.x, 0.0, "further east is further right")
	assert_almost_eq(east.y, 0.0, 0.001, "due east does not drift north")


func test_projection_round_trips_a_position() -> void:
	var proj := CampaignProjection.new()
	var lat := CampaignProjection.DEFAULT_ORIGIN_LAT + 1.25
	var lon := CampaignProjection.DEFAULT_ORIGIN_LON - 2.5
	var back: Vector2 = proj.to_geo(proj.to_plane(lat, lon))
	assert_almost_eq(back.x, lat, 0.0001, "latitude survives the round trip")
	assert_almost_eq(back.y, lon, 0.0001, "longitude survives the round trip")


func test_projection_measures_ground_distance() -> void:
	var metres_per_unit := 800.0
	var proj := CampaignProjection.new(0.0, 0.0, metres_per_unit)
	var span: float = proj.distance_m(Vector2.ZERO, Vector2(100.0, 0.0))
	assert_almost_eq(span, 100.0 * metres_per_unit, 0.001, "plane units scale to metres")
	assert_almost_eq(proj.units_for_metres(span), 100.0, 0.001, "and back again")


func test_projection_reads_its_parameters_from_the_map() -> void:
	var map := {"origin": [40.0, 15.0], "metres_per_unit": 250.0}
	assert_eq(CampaignProjection.origin_of(map), Vector2(40.0, 15.0), "origin from the data")
	assert_eq(CampaignProjection.metres_per_unit_of(map), 250.0, "scale from the data")


func test_projection_falls_back_to_defaults() -> void:
	assert_eq(CampaignProjection.origin_of({}),
			Vector2(CampaignProjection.DEFAULT_ORIGIN_LAT, CampaignProjection.DEFAULT_ORIGIN_LON),
			"a map that declares no origin gets the default one")
	assert_eq(CampaignProjection.metres_per_unit_of({}),
			CampaignProjection.DEFAULT_METRES_PER_UNIT, "and the default scale")
