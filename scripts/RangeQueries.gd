class_name RangeQueries
extends RefCounted
## Regiment-level spatial queries and event-driven range query manager.
## Provides range queries with enter/exit diff detection for targeting and detection.

const CELL_SIZE: float = 150.0

class QueryEntry extends RefCounted:
	var id: int = 0
	var subscriber: Unit = null
	var center: Vector2 = Vector2.ZERO
	var radius: float = 0.0
	var team_filter: int = -1
	var include_routing: bool = true
	var current_matches: Array[Unit] = []
	var on_diff_callback: Callable = Callable()

static var _next_id: int = 1
static var _queries: Dictionary = {}

static func register_query(u: Unit, radius: float, include_routing: bool = true, callback: Callable = Callable()) -> int:
	var q := QueryEntry.new()
	q.id = _next_id
	_next_id += 1
	q.subscriber = u
	q.center = u.position
	q.radius = radius
	q.team_filter = -1
	q.include_routing = include_routing
	q.on_diff_callback = callback
	_queries[q.id] = q
	return q.id

static func unregister_query(qid: int) -> void:
	_queries.erase(qid)

static func clear() -> void:
	_queries.clear()
	_next_id = 1

static func query_range(center: Vector2, radius: float, querier_team: int, include_routing: bool, all_units: Array) -> Array[Unit]:
	var results: Array[Unit] = []
	var r_sq := radius * radius
	for node in all_units:
		var u := node as Unit
		if u == null or u.state == Unit.State.DEAD or u.team == querier_team:
			continue
		if not include_routing and u.state == Unit.State.ROUTING:
			continue
		if center.distance_squared_to(u.position) <= r_sq:
			results.push_back(u)
	return results

static func tick(all_units: Array) -> void:
	for qid in _queries:
		var q: QueryEntry = _queries[qid]
		if q.subscriber != null and is_instance_valid(q.subscriber):
			q.center = q.subscriber.position
		var team: int = q.subscriber.team if q.subscriber != null else 0
		var new_matches := query_range(q.center, q.radius, team, q.include_routing, all_units)
		new_matches.sort_custom(func(a: Unit, b: Unit) -> bool:
			return q.center.distance_squared_to(a.position) < q.center.distance_squared_to(b.position)
		)
		var added: Array[Unit] = []
		var removed: Array[Unit] = []
		for u in new_matches:
			if not q.current_matches.has(u):
				added.push_back(u)
		for u in q.current_matches:
			if not new_matches.has(u):
				removed.push_back(u)
		q.current_matches = new_matches
		if (not added.is_empty() or not removed.is_empty()) and q.on_diff_callback.is_valid():
			q.on_diff_callback.call(added, removed)
