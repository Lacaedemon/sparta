extends RefCounted
## Province polygon overlay over the continuous campaign substrate
## (docs/campaign-layer-design.md, "Map representation").
##
## Everything political -- ownership, victory, diplomacy, recruitment -- stays
## province-level, but a position's province is a DERIVED point-in-polygon fact
## rather than a stored slot: an entity carries a map position, and this index
## answers which province that position falls in. That is what lets armies stop
## being per-province integers without the political rules changing at all.
##
## Built from the loader's validated map dictionary and read-only afterwards, so it
## is a plain RefCounted with no scene dependencies -- unit-testable headlessly like
## CampaignState.

const CampaignLoaderRef = preload("res://scripts/campaign/CampaignLoader.gd")

const NO_PROVINCE := -1

var _polygons: Dictionary = {}    # id -> PackedVector2Array
var _adjacency: Dictionary = {}   # id -> Array of neighbouring ids
var _centres: Dictionary = {}     # id -> Vector2, from the shared centre formula
var _order: Array[int] = []       # ids in map order, so every lookup is deterministic


func _init(map: Dictionary = {}) -> void:
	for province in map.get("provinces", []):
		var id := int(province.get("id", NO_PROVINCE))
		if id == NO_PROVINCE or _polygons.has(id):
			continue
		var poly := PackedVector2Array()
		for vertex in province.get("polygon", []):
			poly.append(Vector2(float(vertex[0]), float(vertex[1])))
		_polygons[id] = poly
		_adjacency[id] = Array(province.get("adj", []))
		# One formula, shared with the loader rather than repeated here, and computed
		# once per province: the same vertex average the loader takes a province's label
		# point from when the map does not author one.
		_centres[id] = CampaignLoaderRef.polygon_centre(poly)
		_order.append(id)


## Province ids in map order.
func ids() -> Array[int]:
	return _order.duplicate()


func has_province(id: int) -> bool:
	return _polygons.has(id)


func polygon(id: int) -> PackedVector2Array:
	return _polygons.get(id, PackedVector2Array())


## Returns the ids reachable from `id` per the map's adjacency list, which may be
## directed; symmetry is not implied.
func neighbours(id: int) -> Array:
	return Array(_adjacency.get(id, [])).duplicate()


func are_neighbours(a: int, b: int) -> bool:
	return Array(_adjacency.get(a, [])).has(b)


## The province containing `point`, or NO_PROVINCE when it falls outside every
## polygon. Overlaps resolve to the first province in map order, so the answer is
## reproducible rather than dependent on dictionary iteration order.
func province_at(point: Vector2) -> int:
	for id in _order:
		if Geometry2D.is_point_in_polygon(point, _polygons[id]):
			return id
	return NO_PROVINCE


## A province's map anchor: the default position for anything placed "in" it before it
## carries a position of its own, and the point marches measure between. This is
## CampaignLoader.polygon_centre -- the average of the polygon's vertices, not its area
## centroid -- so a concave province's anchor can fall outside its own outline.
func centre(id: int) -> Vector2:
	return _centres.get(id, Vector2.ZERO)
