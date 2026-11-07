extends GutTest
## A router whose slot grid is folded off its heading anchors on the men ahead of its centre
## along that heading (Unit.position_anchor_on_heading), each measured against his own slot. A
## rout keeps the grid's fold, so after a flight turn that snapped the grid's front ranks are
## the ones toward the enemy the router broke from: anchoring on them anchored the router on
## its trailing men, which a pursuer can hold back.

const DT := 1.0 / 60.0
# The fold a snapped flight turn left on the router-contact-edge-1801 squadron below
# (measured 2026-11-06 on main 1d0d7705): -2.759 rad, about 158 degrees, so the grid's front
# points nearly back the way the router came.
const SNAP_FOLD := -2.759
# A fold well under the quarter-turn default (ROUTER_HEADING_ANCHOR_FOLD), whose grid front
# still points ahead of the men.
const SMALL_FOLD := 0.3
# The router-reentry-settle-1913 squadron's fold as it routs (measured 2026-11-06 on main
# 1d0d7705): exactly a quarter-turn, so the grid's front ranks are a flank, standing 6.9 wu ahead
# of its centroid there, not trailing it.
const QUARTER_FOLD := -PI * 0.5
# Just past the default: the 0.01 rad margin that keeps a quarter-turn out, and as much again.
const PAST_QUARTER_FOLD := Unit.ROUTER_HEADING_ANCHOR_FOLD + 0.01
# How far a pursuer holds the grid's front ranks back off their slots, and how far the men ahead
# are pushed sideways: any non-zero distance shows the anchor reading one set and not the other.
const HOLD_BACK := 30.0
const PUSH := 10.0
# contact_anchor_offset is a float32 sum of the anchor's bodies less a sum of as many slots,
# divided by the count. The block stands within BLOCK_REACH wu of the origin on each axis
# (checked below), so each sum of up to 40 terms stays under 40 * 128 = 5120 wu, where one add
# rounds by at most half an ulp, 2^-12 wu, counted here as a whole ulp, 2^-11 wu (an
# overcount): (count - 1) * 2^-11 wu per sum. Each pushed body
# rounds by at most half an ulp under 128 wu more, 2^-18 wu. Divided by the count that is under
# 2 * 2^-11 + 2^-18 wu, about 0.00098 wu.
const BLOCK_REACH := 128.0
const OFFSET_TOL := 2.0 / 2048.0 + 1.0 / 262144.0

# The router-contact-edge-1801 clip's squadron and infantry block on that clip's seed: a
# 16-mount Cavalry squadron at morale 0.5, charged from the east by a 40-man Infantry block,
# routs at tick 325 still in contact and flees north. Its first flight turn snaps, so the grid
# keeps its front toward the infantry. On main 1d0d7705 (measured 2026-11-06) it anchored on 8
# men 116.5 wu behind its centroid along the flight from tick 326, and on men behind its
# centroid for 124 of the 125 ticks it anchored at all.
const EDGE_SEED := 18011
const EDGE_ROUTER := {"team": 0, "type": "Cavalry", "x": 520, "y": 980, "count": 16, "morale": 0.5}
const EDGE_PURSUER := {"team": 1, "type": "Infantry", "x": 730, "y": 980, "count": 40,
		"frontage": 10, "facing": [-1, 0]}
const EDGE_ROUT_BY_TICK := 400
# The squadron last anchors as one in contact 124 ticks after its rout on main and 134 with
# the fix, so 200 ticks watches every anchored tick on both trees.
const EDGE_WATCH_TICKS := 200
# The squadron anchors as one in contact on 125 of those ticks on main and 135 with the fix
# (130 to 136 on the clip's perturbed seed runs), measured 2026-11-07 on 1d0d7705 and 580995c5.
# Requiring half of the smaller count still shows it anchored through most of its contact, so
# the trailing check below has ticks to judge.
const EDGE_MIN_ANCHORED_TICKS := 62

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


## A 40-man block facing north with its grid folded `fold` off its heading, its men on their
## slots, routed (or in `state`) and in anchor contact.
func _folded_unit(fold: float, state: Unit.State = Unit.State.ROUTING) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.facing = Vector2.UP
	u.position = Vector2.ZERO
	u._formation_angle = fold
	u.seed_sim_soldiers()
	u.state = state
	u._router_anchor_contact = true
	u._in_enemy_contact = true
	return u


## How far ahead of the whole block's centroid, along the heading, the bodies at `indices` stand.
func _lead(u: Unit, indices: PackedInt32Array) -> float:
	var all_c := Vector2.ZERO
	for p in u._sim_soldier_pos:
		all_c += p
	all_c /= float(u._sim_soldier_pos.size())
	var sel := Vector2.ZERO
	for i in indices:
		sel += u._sim_soldier_pos[i]
	sel /= float(indices.size())
	return (sel - all_c).dot(u.facing)


func test_a_folded_router_anchors_on_the_men_ahead_along_its_heading() -> void:
	var u := _folded_unit(SNAP_FOLD)
	var n: int = u._sim_soldier_pos.size()
	assert_lt(u.grid_front_forward().dot(u.facing), 0.0, "setup: the grid's front points back")
	assert_lt(_lead(u, u.near_front_soldier_indices(n)), 0.0,
			"setup: the grid's front ranks stand behind the centroid")
	var indices: PackedInt32Array = u.position_anchor_indices(n)
	assert_eq(indices.size(), mini(n, u.formation_files(n) * Unit.ANCHOR_RANKS),
			"it anchors on ANCHOR_RANKS-worth of men")
	assert_gt(_lead(u, indices), 0.0, "who stand ahead of the block's centroid (got %.1f wu)"
			% _lead(u, indices))
	assert_true(u.position_anchor_on_heading(), "a router folded this far anchors on its heading")
	assert_eq(indices, u.heading_anchor_soldier_indices(n), "the men farthest ahead along the heading")


func test_a_folded_router_held_back_at_its_trailing_ranks_is_not_dragged_back() -> void:
	var u := _folded_unit(SNAP_FOLD)
	var n: int = u._sim_soldier_pos.size()
	# A pursuer holds the grid's front ranks, the trailing ones, back off their slots.
	for i in u.near_front_soldier_indices(n):
		u._sim_soldier_pos[i] -= u.facing * HOLD_BACK
	var before: Vector2 = u.position
	SoldierBodies.couple(u, DT)
	# The men ahead stand exactly on their own slots, so their drift sums to exactly zero.
	assert_eq(u.position, before, "the anchor reads the men ahead, still on their own slots")


func test_the_men_ahead_pushed_off_their_slots_still_move_the_anchor() -> void:
	var u := _folded_unit(SNAP_FOLD)
	var n: int = u._sim_soldier_pos.size()
	for i in u.position_anchor_indices(n):
		u._sim_soldier_pos[i] += Vector2.RIGHT * PUSH
	var before: Vector2 = u.position
	SoldierBodies.couple(u, DT)
	var moved: Vector2 = u.position - before
	assert_gt(moved.x, 0.0, "the anchor follows its own men off their slots")
	assert_eq(moved.y, 0.0, "and only the way they were pushed")


func test_the_reentry_measure_reads_the_same_men() -> void:
	# _refresh_enemy_contact measures re-entry from where the anchor it would switch to settles
	# the router (contact_anchor_offset), so it has to read the same men couple() anchors on.
	var u := _folded_unit(SNAP_FOLD)
	var n: int = u._sim_soldier_pos.size()
	for p in u._sim_soldier_pos:
		assert_lt(maxf(absf(p.x), absf(p.y)), BLOCK_REACH, "setup: the block stands near the origin")
	for i in u.near_front_soldier_indices(n):
		u._sim_soldier_pos[i] -= u.facing * HOLD_BACK
	assert_eq(u.contact_anchor_offset(), Vector2.ZERO,
			"held-back trailing ranks do not move the settling point")
	for i in u.position_anchor_indices(n):
		u._sim_soldier_pos[i] += Vector2.RIGHT * PUSH
	var offset: Vector2 = u.contact_anchor_offset()
	assert_almost_eq(offset.x, PUSH, OFFSET_TOL, "the men ahead pushed sideways move it with them")
	assert_eq(offset.y, 0.0, "and only sideways")


func test_a_router_nearly_square_to_its_heading_keeps_its_grid_front() -> void:
	var u := _folded_unit(SMALL_FOLD)
	var n: int = u._sim_soldier_pos.size()
	assert_false(u.position_anchor_on_heading(), "a fold under the threshold keeps the grid's front")
	assert_eq(u.position_anchor_indices(n), u.near_front_soldier_indices(n))


func test_a_router_turned_exactly_a_quarter_turn_keeps_its_grid_front() -> void:
	var u := _folded_unit(QUARTER_FOLD)
	var n: int = u._sim_soldier_pos.size()
	assert_gt(_lead(u, u.near_front_soldier_indices(n)), 0.0,
			"setup: the grid's front ranks, a flank, do not stand behind the centroid")
	assert_false(u.position_anchor_on_heading(), "its front ranks do not trail, so it keeps them")
	assert_eq(u.position_anchor_indices(n), u.near_front_soldier_indices(n))


func test_a_router_turned_just_past_a_quarter_turn_anchors_on_its_heading() -> void:
	var u := _folded_unit(PAST_QUARTER_FOLD)
	var n: int = u._sim_soldier_pos.size()
	assert_true(u.position_anchor_on_heading(), "past a quarter-turn the front ranks trail")
	assert_eq(u.position_anchor_indices(n), u.heading_anchor_soldier_indices(n))


func test_a_fold_a_whole_turn_round_reads_as_its_wrapped_angle() -> void:
	var u := _folded_unit(TAU + SMALL_FOLD)
	assert_false(u.position_anchor_on_heading(), "the fold is wrapped before it is compared")


func test_the_threshold_is_configurable() -> void:
	var u := _folded_unit(SNAP_FOLD)
	u.router_heading_anchor_fold = PI
	var n: int = u._sim_soldier_pos.size()
	assert_false(u.position_anchor_on_heading(), "no fold exceeds a half-turn threshold")
	assert_eq(u.position_anchor_indices(n), u.near_front_soldier_indices(n))


func test_a_folded_block_that_is_not_routing_keeps_its_grid_front() -> void:
	var u := _folded_unit(SNAP_FOLD, Unit.State.FIGHTING)
	var n: int = u._sim_soldier_pos.size()
	assert_false(u.position_anchor_on_heading(), "only a router anchors on its heading")
	assert_eq(u.position_anchor_indices(n), u.near_front_soldier_indices(n))


func test_a_folded_router_in_square_keeps_the_contact_selection() -> void:
	var u := _folded_unit(SNAP_FOLD)
	u.formation_mode = Unit.FORMATION_SQUARE
	var n: int = u._sim_soldier_pos.size()
	assert_false(u.position_anchor_on_heading(), "a Square has no heading side to anchor on")
	assert_eq(u.position_anchor_indices(n), u.contact_soldier_indices(n))


func test_a_turning_folded_router_keeps_the_contact_selection() -> void:
	var u := _folded_unit(SNAP_FOLD)
	u._engage_turn_target = Vector2.RIGHT
	var n: int = u._sim_soldier_pos.size()
	assert_true(u._position_anchor_unstable(), "setup: a re-face in progress")
	assert_false(u.position_anchor_on_heading(), "an unstable block keeps the wider selection")
	assert_eq(u.position_anchor_indices(n), u.contact_soldier_indices(n))


func test_no_bodies_select_no_heading_anchor() -> void:
	var u := _folded_unit(SNAP_FOLD)
	assert_eq(u.heading_anchor_soldier_indices(0), PackedInt32Array())


## Start `scenario` on the default map with `seed_value`; return its units by uid.
func _start(scenario: Array, seed_value: int) -> Dictionary:
	Replay.forced_seed = seed_value
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = scenario
	add_child(_battle)
	await get_tree().physics_frame
	var by_uid := {}
	for u in get_tree().get_nodes_in_group("units"):
		by_uid[(u as Unit).uid] = u
	return by_uid


func test_a_router_whose_flight_turn_snapped_anchors_ahead_of_its_centre() -> void:
	var units: Dictionary = await _start([EDGE_ROUTER, EDGE_PURSUER], EDGE_SEED)
	var router: Unit = units.get(0)
	assert_not_null(router, "setup: the squadron deployed")
	if router == null:
		return
	var safety: int = (EDGE_ROUT_BY_TICK + EDGE_WATCH_TICKS) * 4
	while (router.state != Unit.State.ROUTING and _battle.current_tick() < EDGE_ROUT_BY_TICK
			and safety > 0):
		safety -= 1
		await get_tree().physics_frame
	assert_eq(router.state, Unit.State.ROUTING,
			"setup: the squadron routs by tick %d" % EDGE_ROUT_BY_TICK)
	if router.state != Unit.State.ROUTING:
		return
	var rout_tick: int = _battle.current_tick()
	var anchored_ticks: int = 0
	var trailing_ticks: int = 0
	var folded: bool = false
	var worst_lead: float = INF
	while _battle.current_tick() < rout_tick + EDGE_WATCH_TICKS and safety > 0:
		safety -= 1
		await get_tree().physics_frame
		if not is_instance_valid(router) or router.state != Unit.State.ROUTING:
			break
		folded = folded or router.grid_front_forward().dot(router.facing) < 0.0
		var indices: PackedInt32Array = router.position_anchor_indices(router._sim_soldier_pos.size())
		if indices.is_empty():
			continue
		anchored_ticks += 1
		var lead: float = _lead(router, indices)
		worst_lead = minf(worst_lead, lead)
		if lead < 0.0:
			trailing_ticks += 1
	assert_true(folded, "setup: the flight turn left the grid's front pointing back")
	assert_gte(anchored_ticks, EDGE_MIN_ANCHORED_TICKS,
			"setup: the router anchors on some of its men after the rout")
	assert_eq(trailing_ticks, 0,
			"it never anchors on men behind its centre (%d of %d ticks, worst %.1f wu)"
			% [trailing_ticks, anchored_ticks, worst_lead])
