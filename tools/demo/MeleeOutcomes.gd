class_name MeleeOutcomes
## Per-run melee outcome metrics, read from one run's compact state snapshots
## (state_*.json from SPARTA_DEMO_STATE). tools/demo/melee_outcome_compare.gd extracts one
## of these per perturbed run and compares the base and head distributions.
##
## Ticks are snapshot ticks, so their resolution is the dump cadence the caller chose.
##
## A run is COMPLETE when its stream reaches the clip's end tick, or ends on a
## `battle_over` snapshot (the sim is frozen there, so every later tick reads as that final
## state). Every metric then distinguishes three cases:
##   - a number: the event happened, at that tick (or with that value);
##   - NEVER ("never"): the run was observed to its end and the event did not happen;
##   - null: not observed. The stream was cut off before the event could be ruled out (a
##     timeout, or a replay clip whose sink has no battle_over marker), or the question
##     does not apply (the unit left play first). The comparison drops nulls.
## A run with no end tick given is taken as complete.
##
## Metrics:
##   first_contact          first tick any unit is in enemy contact
##   team_<t>_men           team t's men on the field at the end of the run (a unit removed
##                          from play, cut down or escaped off the map, counts zero);
##                          null for an incomplete run
##   uid<u>_first_contact   first tick unit u is in enemy contact
##   uid<u>_removed         first tick unit u is absent or has no men left, after being
##                          seen, whether it escaped or died
##   uid<u>_break           first tick unit u is ROUTING; null when it left play unbroken
##   uid<u>_contact_break   (only when u broke) ticks from the break to the first tick it is
##                          out of contact; null when it left play while still in contact
##   uid<u>_travel_<n>      (only when u broke) metres its men's centroid moved from the
##                          break tick to the first snapshot at least n ticks later; null
##                          when it left play before then (censored, see removed_by_<n>)
##   uid<u>_removed_by_<n>  (only when u broke) 1 when it left play within n ticks of its
##                          break, 0 when it was still on the field at break + n
##
## TODO(#1832): tell a unit that escaped off the map from one cut down.

## How many ticks after a break each travel metric is read at, by default.
const DEFAULT_TRAVEL_OFFSETS := [60, 150, 300]
## The value of an event a complete run shows never happened.
const NEVER := "never"


## The metrics of one run. `snapshots` are parsed state dumps in any order;
## `travel_offsets` are the tick offsets for the travel metrics; `end_tick` is the last
## tick the run was meant to reach (-1: unknown, taken as complete).
static func extract(snapshots: Array, travel_offsets: Array = DEFAULT_TRAVEL_OFFSETS,
		end_tick: int = -1) -> Dictionary:
	var snaps: Array = snapshots.duplicate()
	snaps.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["tick"]) < int(y["tick"]))
	if snaps.is_empty():
		return {"first_contact": null}
	var decided: bool = bool(snaps[-1].get("battle_over", false))
	var complete: bool = decided or end_tick < 0 or int(snaps[-1]["tick"]) >= end_tick
	var unseen = NEVER if complete else null
	var out: Dictionary = {"first_contact": unseen}
	var teams: Dictionary = {}
	var uids: Dictionary = {}
	for snap in snaps:
		for rec in snap["units"]:
			teams[int(rec["team"])] = true
			uids[int(rec["uid"])] = int(rec["team"])
			if typeof(out["first_contact"]) != TYPE_INT and bool(rec.get("in_enemy_contact", false)):
				out["first_contact"] = int(snap["tick"])
	var last_units: Dictionary = _by_uid(snaps[-1])
	for team in teams:
		var men: int = 0
		for uid in last_units:
			if int(last_units[uid]["team"]) == team:
				men += int(last_units[uid]["soldiers"])
		out["team_%d_men" % team] = men if complete else null
	for uid in uids:
		_unit_metrics(snaps, uid, unseen, decided, travel_offsets, out)
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


static func _unit_metrics(snaps: Array, uid: int, unseen, decided: bool, travel_offsets: Array,
		out: Dictionary) -> void:
	var key: String = "uid%d_" % uid
	var first_seen: int = -1
	var removed_idx: int = -1
	var break_idx: int = -1
	out[key + "first_contact"] = unseen
	for i in range(snaps.size()):
		var rec = _alive(snaps[i], uid)
		if rec == null:
			if first_seen >= 0:
				removed_idx = i
				break
			continue
		if first_seen < 0:
			first_seen = i
		if typeof(out[key + "first_contact"]) != TYPE_INT and bool(rec.get("in_enemy_contact", false)):
			out[key + "first_contact"] = int(snaps[i]["tick"])
		if break_idx < 0 and str(rec.get("state", "")) == "ROUTING":
			break_idx = i
	out[key + "removed"] = int(snaps[removed_idx]["tick"]) if removed_idx >= 0 else unseen
	if break_idx < 0:
		# Left play unbroken: whether it would have broken is not observed.
		out[key + "break"] = null if removed_idx >= 0 else unseen
		return
	var break_tick: int = int(snaps[break_idx]["tick"])
	out[key + "break"] = break_tick
	var end_idx: int = removed_idx if removed_idx >= 0 else snaps.size()
	out[key + "contact_break"] = null if removed_idx >= 0 else unseen
	for i in range(break_idx, end_idx):
		if not bool(_alive(snaps[i], uid).get("in_enemy_contact", false)):
			out[key + "contact_break"] = int(snaps[i]["tick"]) - break_tick
			break
	var origin: Vector2 = _centroid(_alive(snaps[break_idx], uid))
	for offset in travel_offsets:
		var target: int = break_tick + int(offset)
		out[key + "travel_%d" % int(offset)] = _travel(snaps, uid, break_idx, end_idx, target,
				origin, decided)
		var gone: bool = removed_idx >= 0 and int(snaps[removed_idx]["tick"]) <= target
		var seen_past: bool = decided or int(snaps[-1]["tick"]) >= target
		out[key + "removed_by_%d" % int(offset)] = 1 if gone else (0 if seen_past else null)


## Metres the unit's centroid sits from `origin` at the first snapshot at or after
## `target`. A decided battle stops at its final snapshot. null when the unit left play
## before `target` (censored) or the stream was cut off before it.
static func _travel(snaps: Array, uid: int, break_idx: int, end_idx: int, target: int,
		origin: Vector2, decided: bool):
	var last: Vector2 = origin
	for i in range(break_idx, end_idx):
		last = _centroid(_alive(snaps[i], uid))
		if int(snaps[i]["tick"]) >= target:
			return snapped(last.distance_to(origin), 0.001)
	if end_idx == snaps.size() and decided:
		return snapped(last.distance_to(origin), 0.001)
	return null
