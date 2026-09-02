extends RefCounted
## Per-campaign map projection: geographic latitude/longitude to campaign map-plane
## coordinates and back (docs/campaign-layer-design.md, "Map representation").
##
## Campaign entity positions are stored in map-plane units; this is the mapping
## between that plane and real ground. It is what gives a campaign a ground scale --
## so a march reports kilometres instead of pixels -- and it is the one place
## real-geography source data has to land, so an ingestion step converts once here
## rather than reinterpreting the plane everywhere. Nothing stores a lat-long today:
## only the scale half (distance_m) has a caller, and the geographic half defines the
## mapping the ingestion phase will author against. A theater-scale campaign spans a
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

## Per-campaign defaults, both overridable from the map data. 800 m to the unit puts
## the shipped maps at theater scale: the Gallic War's polygons span 1020 by 520 plane
## units, so about 816 km by 416 km. The origin is the plane's own (0, 0) -- the map's
## NORTH-WEST corner, since x grows east and y grows south -- so everything a campaign
## draws lies south-east of it. The shipped polygons are stylised rather than traced
## from real ground, so the default origin only keeps the mapping well defined; a
## campaign built from real source data declares its own origin and scale.
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


## The campaign's projection origin as Vector2(lat, lon), from the map data's optional
## "origin" key (CampaignLoader validates it and carries it through) so each campaign
## can sit on its own ground. Falls back for a map dict built without the loader.
static func origin_of(map: Dictionary) -> Vector2:
	var origin: Array = map.get("origin", [])
	if origin.size() < 2:
		return Vector2(DEFAULT_ORIGIN_LAT, DEFAULT_ORIGIN_LON)
	return Vector2(float(origin[0]), float(origin[1]))


## Metres of ground per plane unit for this campaign, from the map data's optional
## "metres_per_unit" key. Same loader-validated source as origin_of.
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
