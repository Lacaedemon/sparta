class_name MeleeOutcomes
## Per-run melee outcome metrics, read from one run's compact state snapshots
## (state_*.json from SPARTA_DEMO_STATE). tools/demo/melee_outcome_compare.gd extracts one
## of these per perturbed run and compares the base and head distributions.
##
## Ticks are snapshot ticks, so their resolution is the dump cadence the caller chose. An
## event that never happened in the run is null. A run whose stream ends on a
## `battle_over` snapshot was decided there: the sim is frozen, so every later tick reads
## as that final state. A stream that ends without the marker was cut off, and anything
## that would need a later tick is null.
##
## Metrics:
##   first_contact          first tick any unit is in enemy contact
##   team_<t>_men           team t's men on the field at the end of the run (a unit removed
##                          from play, cut down or escaped off the map, counts zero)
##   uid<u>_first_contact   first tick unit u is in enemy contact
##   uid<u>_break           first tick unit u is ROUTING
##   uid<u>_contact_break   ticks from u's break to the first tick it is out of contact
##                          (only when u broke; null when it never got clear)
##   uid<u>_travel_<n>      metres its men's centroid moved from the break tick to the
##                          first snapshot at least n ticks later (only when u broke); a
##                          unit cut down stops at its last living centroid

## How many ticks after a break each travel metric is read at, by default.
const DEFAULT_TRAVEL_OFFSETS := [60, 150, 300]


## The metrics of one run. `snapshots` are parsed state dumps in any order;
## `travel_offsets` are the tick offsets for the travel metrics.
static func extract(snapshots: Array, travel_offsets: Array = DEFAULT_TRAVEL_OFFSETS) -> Dictionary:
	var snaps: Array = snapshots.duplicate()
	snaps.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["tick"]) < int(y["tick"]))
	var out: Dictionary = {"first_contact": null}
	if snaps.is_empty():
		return out
	var decided: bool = bool(snaps[-1].get("battle_over", false))
	var teams: Dictionary = {}
	var uids: Dictionary = {}
	for snap in snaps:
		for rec in snap["units"]:
			teams[int(rec["team"])] = true
			uids[int(rec["uid"])] = int(rec["team"])
			if out["first_contact"] == null and bool(rec.get("in_enemy_contact", false)):
				out["first_contact"] = int(snap["tick"])
	var last_units: Dictionary = _by_uid(snaps[-1])
	for team in teams:
		var men: int = 0
		for uid in last_units:
			if int(last_units[uid]["team"]) == team:
				men += int(last_units[uid]["soldiers"])
		out["team_%d_men" % team] = men
	for uid in uids:
		_unit_metrics(snaps, uid, decided, travel_offsets, out)
	return out


static func _by_uid(snap: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for rec in snap["units"]:
		out[int(rec["uid"])] = rec
	return out


## The unit's record in `snap`, or null when it is absent or has no men left.
static func _alive(snap: Dictionary, uid: int):
	for rec in snap["units"]:
		if int(rec["uid"]) == uid:
			return rec if int(rec["soldiers"]) > 0 else null
	return null


static func _centroid(rec: Dictionary) -> Vector2:
	var c: Array = rec.get("soldier_summary_m", {}).get("centroid_m", [0.0, 0.0])
	return Vector2(float(c[0]), float(c[1]))


static func _unit_metrics(snaps: Array, uid: int, decided: bool, travel_offsets: Array,
		out: Dictionary) -> void:
	var key: String = "uid%d_" % uid
	out[key + "first_contact"] = null
	out[key + "break"] = null
	var break_idx: int = -1
	for i in range(snaps.size()):
		var rec = _alive(snaps[i], uid)
		if rec == null:
			continue
		if out[key + "first_contact"] == null and bool(rec.get("in_enemy_contact", false)):
			out[key + "first_contact"] = int(snaps[i]["tick"])
		if break_idx < 0 and str(rec.get("state", "")) == "ROUTING":
			break_idx = i
	if break_idx < 0:
		return
	var break_tick: int = int(snaps[break_idx]["tick"])
	out[key + "break"] = break_tick
	out[key + "contact_break"] = null
	for i in range(break_idx, snaps.size()):
		var rec = _alive(snaps[i], uid)
		if rec == null:
			break
		if not bool(rec.get("in_enemy_contact", false)):
			out[key + "contact_break"] = int(snaps[i]["tick"]) - break_tick
			break
	var origin: Vector2 = _centroid(_alive(snaps[break_idx], uid))
	for offset in travel_offsets:
		out[key + "travel_%d" % int(offset)] = _travel(snaps, uid, break_idx, break_tick + int(offset),
				origin, decided)


## Metres the unit's centroid sits from `origin` at the first snapshot at or after
## `target`. A unit cut down before then stops at its last living centroid; a decided battle
## stops at its final snapshot; a stream cut off before `target` gives null.
static func _travel(snaps: Array, uid: int, break_idx: int, target: int, origin: Vector2,
		decided: bool):
	var last: Vector2 = origin
	for i in range(break_idx, snaps.size()):
		var rec = _alive(snaps[i], uid)
		if rec == null:
			return snapped(last.distance_to(origin), 0.001)
		last = _centroid(rec)
		if int(snaps[i]["tick"]) >= target:
			return snapped(last.distance_to(origin), 0.001)
	if decided:
		return snapped(last.distance_to(origin), 0.001)
	return null
