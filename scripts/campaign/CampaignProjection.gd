extends RefCounted
## Per-campaign map projection: geographic latitude/longitude to campaign map-plane
## coordinates and back (docs/campaign-layer-design.md, "Map representation").
##
## Campaign entity positions are authored and stored in lat-long, so real-geography
## source data needs no substrate conversion, and distance and area math run through
## a projection instead of being read off the plane. A theater-scale campaign spans a
## few hundred kilometres, where a local equidistant projection (equirectangular
## about the campaign's own origin) keeps distances accurate enough that a costlier
## projection buys nothing.
##
## The map plane is the space the province polygons are already drawn in: x grows
## east, y grows SOUTH (screen convention, so north is up), and one plane unit spans
## `metres_per_unit` metres. Every value here is a per-campaign parameter with a
## default, not a fixed property of the map.

## IUGG mean Earth radius, in metres: a physical constant, not a tunable.
const EARTH_RADIUS_M := 6371008.8

## Defaults sized to the shipped campaigns' 1600x1200 plane: 800 m to the unit makes
## that a 1280 km by 960 km theater, and the origin sits in central Gaul so the
## Gallic War's polygons land on plausible ground.
const DEFAULT_METRES_PER_UNIT := 800.0
const DEFAULT_ORIGIN_LAT := 46.5
const DEFAULT_ORIGIN_LON := 2.5

var origin_lat: float
var origin_lon: float
var metres_per_unit: float


func _init(
	p_origin_lat: float = DEFAULT_ORIGIN_LAT,
	p_origin_lon: float = DEFAULT_ORIGIN_LON,
	p_metres_per_unit: float = DEFAULT_METRES_PER_UNIT
) -> void:
	origin_lat = p_origin_lat
	origin_lon = p_origin_lon
	metres_per_unit = maxf(p_metres_per_unit, 0.001)


## The campaign's projection origin as Vector2(lat, lon), read from the map data's
## optional "origin" key so each campaign can sit on its own ground.
static func origin_of(map: Dictionary) -> Vector2:
	var origin: Array = map.get("origin", [])
	if origin.size() < 2:
		return Vector2(DEFAULT_ORIGIN_LAT, DEFAULT_ORIGIN_LON)
	return Vector2(float(origin[0]), float(origin[1]))


## Metres per plane unit for this campaign, from the map data's optional "scale" key.
static func metres_per_unit_of(map: Dictionary) -> float:
	return float(map.get("metres_per_unit", DEFAULT_METRES_PER_UNIT))


## Map-plane point for a geographic position.
func to_plane(lat: float, lon: float) -> Vector2:
	var east := EARTH_RADIUS_M * deg_to_rad(lon - origin_lon) * cos(deg_to_rad(origin_lat))
	var north := EARTH_RADIUS_M * deg_to_rad(lat - origin_lat)
	return Vector2(east, -north) / metres_per_unit


## Geographic position of a map-plane point, as Vector2(lat, lon). The inverse of
## to_plane, so a round trip returns the position it started from.
func to_geo(point: Vector2) -> Vector2:
	var east := point.x * metres_per_unit
	var north := -point.y * metres_per_unit
	var lat := origin_lat + rad_to_deg(north / EARTH_RADIUS_M)
	var cos_lat := cos(deg_to_rad(origin_lat))
	var lon := origin_lon
	if not is_zero_approx(cos_lat):
		lon += rad_to_deg(east / (EARTH_RADIUS_M * cos_lat))
	return Vector2(lat, lon)


## Ground distance in metres between two map-plane points -- what a march length or a
## forage radius is measured in, and what a player-facing distance label renders from.
func distance_m(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) * metres_per_unit


## Plane units spanning `metres` of ground: the inverse of distance_m, for placing a
## radius authored in metres onto the plane.
func units_for_metres(metres: float) -> float:
	return metres / metres_per_unit
