class_name RangeQueries
extends RefCounted
## Event-driven range queries service with enter/exit diff events and anti-dogpile scoring.

class ActiveQuery extends RefCounted:
	var id: int
	var owner_unit: Unit
	var radius: float
	var filter_team: int
	var current_matches: Array = []
	var previous_matches: Array = []

static var _next_query_id: int = 1
static var _active_queries: Dictionary = {}
static var _attacker_assignments: Dictionary = {}

static func create_query(u: Unit, radius: float, filter_team: int = -1) -> int:
	var q := ActiveQuery.new()
	q.id = _next_query_id
	_next_query_id += 1
	q.owner_unit = u
	q.radius = radius
	q.filter_team = filter_team
	_active_queries[q.id] = q
	return q.id

static func unregister_query(query_id: int) -> void:
	_active_queries.erase(query_id)

static func clear_all() -> void:
	_active_queries.clear()
	_attacker_assignments.clear()
	_next_query_id = 1

static func update_all(units: Array) -> Dictionary:
	var diffs: Dictionary = {}
	for q_id in _active_queries.keys():
		var q: ActiveQuery = _active_queries[q_id]
		if not is_instance_valid(q.owner_unit) or q.owner_unit.state == Unit.State.DEAD:
			_active_queries.erase(q_id)
			continue
		var r_sq := q.radius * q.radius
		var new_matches: Array = []
		for u in units:
			var target := u as Unit
			if target == null or target == q.owner_unit or target.state == Unit.State.DEAD:
				continue
			if q.filter_team != -1 and target.team != q.filter_team:
				continue
			if q.owner_unit.position.distance_squared_to(target.position) <= r_sq:
				new_matches.append(target)
		var added: Array = []
		var removed: Array = []
		for m in new_matches:
			if not q.previous_matches.has(m):
				added.append(m)
		for m in q.previous_matches:
			if not new_matches.has(m):
				removed.append(m)
		q.previous_matches = new_matches
		q.current_matches = new_matches
		if not added.is_empty() or not removed.is_empty():
			diffs[q.id] = {"added": added, "removed": removed, "matches": new_matches}
	return diffs

static func record_assignment(attacker: Unit, target: Unit) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	if not _attacker_assignments.has(target):
		_attacker_assignments[target] = []
	var arr: Array = _attacker_assignments[target]
	if not arr.has(attacker):
		arr.append(attacker)

static func get_assignment_count(target: Unit) -> int:
	if not is_instance_valid(target) or not _attacker_assignments.has(target):
		return 0
	var arr: Array = _attacker_assignments[target]
	var count := 0
	for a in arr:
		if is_instance_valid(a) and (a as Unit).state != Unit.State.DEAD:
			count += 1
	return count

static func score_target_anti_dogpile(attacker: Unit, target: Unit, max_attackers: int = 2) -> float:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return -INF
	var count := get_assignment_count(target)
	if count >= max_attackers:
		return -1000.0 - count * 100.0
	var dist_m := attacker.position.distance_to(target.position) / WorldScale.WU_PER_M
	var score := 100.0 - dist_m
	if target.state == Unit.State.ROUTING:
		score += 20.0
	return score
