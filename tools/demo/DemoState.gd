class_name DemoState
## Serialization for the demo state-dump path (see demos/README.md, "Verifying a demo by
## state (AI verification)"). Turns authoritative game state into a compact, readable
## JSON-ready Dictionary at a chosen tick, so an AI reviewer (or a test) can assert on exact
## values — a unit's state, morale, position — instead of interpreting a rendered frame. It
## is the machine-readable companion to the PNG frame capture (DemoFrames).
##
## The name/summary helpers up top are deterministic functions of their arguments — no node
## lookups, no engine globals — so they are directly unit-testable like DemoFrames /
## CameraKeyframes. The snapshot builders at the bottom (unit_record/build_snapshot) do read
## live Unit nodes, but stay deterministic readers shared by both dump paths: the
## scripted-input recorder (DemoInputRecorder) and the replay-playback sink (DemoStateSink).

const WorldScaleRef = preload("res://scripts/WorldScale.gd")

## Unit.State int -> readable name. Mirrors `enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }`
## on Unit.gd. Kept as an explicit table (not a reflected enum) so the dump names stay stable
## even if the enum gains members, and an out-of-range int reads as "UNKNOWN(<n>)" rather than
## silently dropping.
const STATE_NAMES := {
	0: "IDLE",
	1: "MOVING",
	2: "FIGHTING",
	3: "ROUTING",
	4: "DEAD",
}

## Unit.formation_mode int -> readable name. Mirrors the FORMATION_* consts on Unit.gd
## (NORMAL 0, TIGHT 1, LOOSE 2, SQUARE 3, SHIELD_WALL 4, TESTUDO 5).
const FORMATION_NAMES := {
	0: "NORMAL",
	1: "TIGHT",
	2: "LOOSE",
	3: "SQUARE",
	4: "SHIELD_WALL",
	5: "TESTUDO",
	6: "SCHILTRON",
}

## Unit.current_maneuver() int -> readable name. Mirrors `enum Maneuver { IDLE, MARCHING,
## FIGHTING, CONVERSIO, QUARTER_TURN, WHEELING, FILE_DOUBLE_DEEPEN, FILE_DOUBLE_WIDEN,
## NUDGE_SIDESTEP, NUDGE_BACKSTEP, NUDGE_FORWARD_STEP, CYCLE_CHARGE, COUNTERMARCH }` on Unit.gd.
const MANEUVER_NAMES := {
	0: "IDLE",
	1: "MARCHING",
	2: "FIGHTING",
	3: "CONVERSIO",
	4: "QUARTER_TURN",
	5: "WHEELING",
	6: "FILE_DOUBLE_DEEPEN",
	7: "FILE_DOUBLE_WIDEN",
	8: "NUDGE_SIDESTEP",
	9: "NUDGE_BACKSTEP",
	10: "NUDGE_FORWARD_STEP",
	11: "CYCLE_CHARGE",
	12: "COUNTERMARCH",
}

## Unit.countermarch_variant() int -> readable name. Mirrors `enum CountermarchVariant {
## MACEDONIAN, LACONIAN, CHORAL }` on Unit.gd.
const COUNTERMARCH_VARIANT_NAMES := {
	0: "MACEDONIAN",
	1: "LACONIAN",
	2: "CHORAL",
}

## The node groups that together hold every combat unit still on the field. A unit lives in
## exactly one at a time: "units" while fightable, "routers" while ROUTING (Unit._rout()
## moves it over; _rally() moves it back). A snapshot must walk BOTH — walking "units" alone
## makes a unit vanish from the transcript mid-rout, hiding exactly the arc (state ROUTING,
## morale recovering, position fleeing) the dump exists to expose. Same union
## Battle._team_in_play() scans when deciding whether a team is still in play.
const COMBAT_GROUPS := ["units", "routers"]


## Map an int to a name via a table, falling back to "UNKNOWN(<n>)" for an unmapped value so a
## new enum member surfaces as a visible, greppable token instead of a missing field.
static func name_from(table: Dictionary, value: int, fallback_prefix: String) -> String:
	return table.get(value, "%s(%d)" % [fallback_prefix, value])


static func state_name(value: int) -> String:
	return name_from(STATE_NAMES, value, "STATE")


static func formation_name(value: int) -> String:
	return name_from(FORMATION_NAMES, value, "FORMATION")


static func maneuver_name(value: int) -> String:
	return name_from(MANEUVER_NAMES, value, "MANEUVER")


static func countermarch_variant_name(value: int) -> String:
	return name_from(COUNTERMARCH_VARIANT_NAMES, value, "COUNTERMARCH_VARIANT")


## An order_mode int -> its readable name using Battle.ORDER_MODE_NAMES (passed in so this
## stays node-free and testable). Falls back to "MODE(<n>)" for an unmapped value.
static func order_mode_name(order_mode_names: Dictionary, value: int) -> String:
	return name_from(order_mode_names, value, "MODE")


## Order two unit records by uid, for sort_custom.
static func _uid_less(a: Dictionary, b: Dictionary) -> bool:
	return a["uid"] < b["uid"]


## Sort unit records by uid, in place, returning the array. Group enumeration order shifts
## when a unit changes groups — a router leaves "units" for "routers", and a rallied unit
## re-enters "units" at the END of the group — so raw group order reshuffles the transcript
## between ticks. A fixed uid order keeps tick-to-tick records aligned for diffing.
static func sort_records_by_uid(records: Array) -> Array:
	records.sort_custom(_uid_less)
	return records


## Round a float to `places` decimals for compact, readable JSON — raw sim floats carry a long
## fractional tail that adds noise without helping a reviewer assert on a value.
static func round_to(value: float, places: int = 2) -> float:
	var factor: float = pow(10.0, places)
	return round(value * factor) / factor


## A rounded [x, y] pair for a Vector2, for JSON. Keeps positions/facings readable.
static func vec2_pair(v: Vector2, places: int = 2) -> Array:
	return [round_to(v.x, places), round_to(v.y, places)]


## Summarize a regiment's per-soldier bodies without dumping the full 44-byte/soldier arrays.
## Given the world-space soldier positions and the prone timers (index-aligned; prone > 0 means
## down), returns {count, centroid:[x,y], bbox:[w,h], prone_count}. An empty body list yields a
## zeroed summary (centroid [0,0], bbox [0,0], counts 0) so a routed/empty unit still serializes.
## Pure: reads only its two array arguments.
static func soldier_summary(positions: PackedVector2Array, prone: PackedFloat32Array) -> Dictionary:
	var count: int = positions.size()
	if count == 0:
		return {"count": 0, "centroid": [0.0, 0.0], "bbox": [0.0, 0.0], "prone_count": 0}
	var sum: Vector2 = Vector2.ZERO
	var min_p: Vector2 = positions[0]
	var max_p: Vector2 = positions[0]
	for p in positions:
		sum += p
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	var centroid: Vector2 = sum / float(count)
	var prone_count: int = 0
	var prone_n: int = prone.size()
	for i in range(count):
		if i < prone_n and prone[i] > 0.0:
			prone_count += 1
	return {
		"count": count,
		"centroid": vec2_pair(centroid),
		"bbox": [round_to(max_p.x - min_p.x), round_to(max_p.y - min_p.y)],
		"prone_count": prone_count,
	}


## Metric mirrors for the dev-facing dump: every user-facing number already displays in
## metric (DistanceLegend), and these carry the same convention onto the state dump so a
## reviewer reads metres/m-per-s without dividing by the world scale by hand. Additive --
## the wu fields stay exactly as they were, so existing tooling and tests keep reading
## them. Positions round to 3 places (millimetres); conversions reuse DistanceLegend's
## own pure statics rather than re-deriving them.
static func vec2_pair_m(v: Vector2, wu_per_m: float) -> Array:
	return [round_to(DistanceLegend.metres_for_world(v.x, wu_per_m), 3),
			round_to(DistanceLegend.metres_for_world(v.y, wu_per_m), 3)]


## Speed in m/s for a world-units/sec value, rounded for the dump. `speed_scale` mirrors
## the loadout conversion (Battle.SPEED_SCALE) so the figure reads back in the same m/s
## the loadout declared.
static func mps(world_speed: float, wu_per_m: float, speed_scale: float = 1.0) -> float:
	return round_to(DistanceLegend.mps_for_world_speed(world_speed, wu_per_m, speed_scale), 3)


## The metric companion of soldier_summary(): centroid and bbox in metres, derived from
## the SAME positions so the two summaries can never disagree. Count fields aren't
## repeated -- they're unitless and live in the wu summary.
static func soldier_summary_m(positions: PackedVector2Array, wu_per_m: float) -> Dictionary:
	var count: int = positions.size()
	if count == 0:
		return {"centroid_m": [0.0, 0.0], "bbox_m": [0.0, 0.0]}
	var sum: Vector2 = Vector2.ZERO
	var min_p: Vector2 = positions[0]
	var max_p: Vector2 = positions[0]
	for p in positions:
		sum += p
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	return {
		"centroid_m": vec2_pair_m(sum / float(count), wu_per_m),
		"bbox_m": [round_to(DistanceLegend.metres_for_world(max_p.x - min_p.x, wu_per_m), 3),
				round_to(DistanceLegend.metres_for_world(max_p.y - min_p.y, wu_per_m), 3)],
	}


# --- snapshot builders (shared by DemoInputRecorder and DemoStateSink) ------

## Build the snapshot Dictionary for `tick`: battle-level tick plus a per-unit record. Walks
## the "units" + "routers" union (COMBAT_GROUPS) so a ROUTING unit — which has left "units"
## for "routers" and may yet rally — still appears in every snapshot with its state, morale,
## and position; its record is distinguished by `state: "ROUTING"`. Records are sorted by uid
## so the order stays stable while units change groups mid-rout/rally. `order_mode_names` and
## `speed_scale` come from the live Battle node (its ORDER_MODE_NAMES / SPEED_SCALE); `full`
## also embeds the raw per-soldier arrays for deep debugging.
static func build_snapshot(tree: SceneTree, tick: int, order_mode_names: Dictionary,
		speed_scale: float, full: bool) -> Dictionary:
	var units_out: Array = []
	for group in COMBAT_GROUPS:
		for u in tree.get_nodes_in_group(group):
			units_out.append(unit_record(u, order_mode_names, speed_scale, full))
	return {"tick": tick, "units": sort_records_by_uid(units_out)}


## One unit's readable record. Reads Unit fields directly and maps the enum ints to names
## (State/formation here, order_mode via the caller-supplied Battle.ORDER_MODE_NAMES).
## target_enemy is dumped as its uid (or null) so a snapshot references units by the same
## stable id, not a node path.
static func unit_record(u: Node, order_mode_names: Dictionary, speed_scale: float,
		full: bool) -> Dictionary:
	var target_uid = u.target_enemy.uid \
			if u.target_enemy != null and is_instance_valid(u.target_enemy) else null
	var rec: Dictionary = {
		"uid": u.uid,
		"name": u.unit_name,
		"team": u.team,
		"position": vec2_pair(u.position),
		# Metric mirror of position, per the units convention: dev-facing numbers read in
		# metres like every user-facing surface already does. The wu field above stays.
		"position_m": vec2_pair_m(u.position, WorldScaleRef.WU_PER_M),
		"facing": vec2_pair(u.facing),
		"morale": round_to(u.morale, 1),
		"state": state_name(u.state),
		"formation": formation_name(u.formation_mode),
		# Durable frontage (phase 5): the file count a FRONTAGE order last wrote (or the
		# type-derived default when none has). Like formation/order_mode/rank_relief, this is
		# mode-layer state a completed order writes and that then persists as queryable Unit
		# state -- UnitFormation.frontage is the same pure lookup the sim itself uses.
		"frontage": UnitFormation.frontage(u),
		"soldiers": u.soldiers,
		"current_speed": round_to(u._current_speed, 1),
		"current_speed_mps": mps(u._current_speed, WorldScaleRef.WU_PER_M, speed_scale),
		"order_mode": order_mode_name(order_mode_names, u.order_mode),
		# Intra-unit rank-relief mode (phase 3): whether rear ranks rotate forward to
		# relieve their own fighting line. A durable mode like formation, so a stance
		# order's write is verifiable straight off the transcript.
		"rank_relief": u.rank_relief,
		"target_enemy_uid": target_uid,
		"engaged": u.is_engaged(),
		# A single readable label for the in-progress drill/maneuver, consolidating
		# current_order/order_phase/order_mode into one field a verifier can read directly --
		# e.g. a conversio and a centre-pivot both otherwise read as current_order: "MOVE"/
		# order_phase: "TURN" or current_order: "QUARTER_TURN" respectively, so this spares a
		# reader from reconstructing the distinction by hand. See Unit.current_maneuver().
		"maneuver": maneuver_name(u.current_maneuver()),
		# Which exelismos variant a "maneuver": "COUNTERMARCH" is running (null otherwise) --
		# maneuver alone can't distinguish Macedonian/Laconian/Choral. See
		# Unit.countermarch_variant().
		"countermarch_variant": countermarch_variant_name(u.countermarch_variant()) \
				if u.countermarch_variant() >= 0 else null,
		# The formation's simulation tier (docs/large-scale-simulation-design.md): CLOSE runs
		# the full per-soldier arrays, FAR is the aggregate record with no individual bodies.
		# Serialized as the readable name via FormationTier's own stable table.
		"tier": FormationTier.tier_name(u.tier),
		# Phase 1 of the unified orders-queue design (docs/orders-queue-design.md): the head
		# of the orders queue -- the single, transcript-visible source of truth for "what is
		# this unit doing right now," including its active phase for a phased order (e.g. a
		# move-to-rear about-face vs its march). null when the unit is idle (no current order).
		"current_order": Order.type_name(u.current_order.type) if u.current_order != null else null,
		# effective_phase_name(), not a plain phase_name(phase) read: a rear-move/lateral-
		# pivot composite's TURN/MARCH/RETURN_TURN now lives in which child of the order
		# tree is active (docs/atomic-order-decomposition-design.md), not in `phase`
		# itself, so this bridges back to the same reported vocabulary the transcript has
		# always used.
		"order_phase": u.current_order.effective_phase_name() if u.current_order != null else null,
		# The current order's pending terminal condition, e.g. "Hold: until
		# enemy_in_range" from the design doc becomes order_guard: "ENEMY_IN_RANGE" here --
		# null when the order carries no guard (or there is no current order at all), so a
		# reader can tell "unconditional order" apart from "guard not yet satisfied."
		"order_guard": Order.guard_name(u.current_order.guard) \
				if u.current_order != null and u.current_order.guard != Order.Guard.NONE else null,
		# Phase 5: the not-yet-current queued orders behind current_order, for full
		# plan legibility (the design doc's "optionally the queue tail"). Each entry is just
		# the order's type name -- current_order/order_phase/order_guard already cover the
		# one that's actually executing, so the tail only needs to answer "and then what."
		# Empty (not null) when nothing is queued, so a reader doesn't have to special-case
		# "no current order" (current_order null) vs "current order, nothing queued behind
		# it" (queue_tail []).
		"queue_tail": queue_tail(u),
	}
	# A far-tier formation has no individual bodies, so its record carries NO per-soldier
	# payload at all -- not even a zeroed summary. The explicit `tier` field above is what
	# lets a reader tell "no soldiers to summarize" (FAR) apart from "per-soldier detail not
	# requested" (a close-tier dump without SPARTA_DEMO_STATE_FULL, which still gets the
	# compact soldier_summary but no soldiers_full arrays).
	if u.tier != FormationTier.FAR:
		rec["soldier_summary"] = soldier_summary(u._sim_soldier_pos, u._sim_prone)
		rec["soldier_summary_m"] = soldier_summary_m(u._sim_soldier_pos, WorldScaleRef.WU_PER_M)
		if full:
			rec["soldiers_full"] = soldier_arrays(u)
			rec["motion_ref"] = motion_ref(u)
	return rec


## Type names of the queued orders BEHIND u.current_order, in queue order (u.orders[0] is
## current_order itself, already reported separately -- see sort_records_by_uid's sibling
## note on why records stay stable: orders[1:] is a plain array slice, no group reshuffling
## to guard against here). Mirrors Unit.queued_move_points' "everything after the head"
## shape but reports every order kind, not just MOVE legs.
static func queue_tail(u: Node) -> Array:
	var tail: Array = []
	for i in range(1, u.orders.size()):
		tail.append(Order.type_name(u.orders[i].type))
	return tail


## The raw per-soldier arrays for one unit, for --full deep debugging. Positions, facings,
## and ordered slots are world-space Vector2s flattened to [x, y] pairs; hp/prone/stamina
## are index-aligned floats. `slots` is the unit's CANONICAL slot grid
## (Unit.soldier_world_slots) at the same tick -- the ordered shape the bodies chase --
## dumped from the sim's own slot math so an offline analyzer comparing ordered vs actual
## geometry (DemoDefects) never re-derives it and can't drift from the game.
static func soldier_arrays(u: Node) -> Dictionary:
	var positions: Array = []
	for p in u._sim_soldier_pos:
		positions.append(vec2_pair(p))
	var facings: Array = []
	for fdir in u._sim_soldier_facing:
		facings.append(vec2_pair(fdir))
	var slots: Array = []
	for s in u.soldier_world_slots(u.soldiers):
		slots.append(vec2_pair(s))
	return {
		"pos": positions,
		"facing": facings,
		"slots": slots,
		"hp": rounded_floats(u._sim_soldier_hp),
		"prone": rounded_floats(u._sim_prone),
		"stamina": rounded_floats(u._sim_soldier_stamina),
	}


## Per-unit motion/geometry constants a defect analyzer derives its thresholds from --
## dumped alongside the arrays so analysis reads the sim's own tuning instead of
## hardcoding a copy that would silently drift when the game retunes (the same
## no-duplicated-ownership rule the units convention states for source files).
static func motion_ref(u: Node) -> Dictionary:
	return {
		"formation_spacing": round_to(u.FORMATION_SPACING * u.spacing_scale, 4),
		"walk_speed": round_to(u.walk_speed, 2),
		"jog_speed": round_to(u.jog_speed, 2),
		"move_speed": round_to(u.move_speed, 2),
		"pivot_radius": round_to(u._pivot_radius(), 2),
		"turn_rate": round_to(u.TURN_RATE, 4),
	}


## A PackedFloat32Array -> a plain Array of rounded floats, for JSON.
static func rounded_floats(arr: PackedFloat32Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(round_to(v, 2))
	return out
