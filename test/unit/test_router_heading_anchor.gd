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
# The fold the last-unit-rally block's flight turn left on its grid on that clip's seed run 3
# (measured 2026-11-11 on main e78d81be): 1.3152 rad, about 75 degrees, so the snap left the grid
# under a quarter-turn and its front ranks along a flank, which then fell behind its centre.
const BAND_FOLD := 1.3152
# Where the block stands for the lead tests, both ahead of the origin along its heading and
# behind it: far enough off the origin that a lead compared without scaling the two sums by their
# counts, or without the whole block's sum, reads the block's own offset (400 wu against a lead of
# a few wu) rather than how far its front ranks stand ahead of its centre, whichever way it lies.
const ORIGIN_OFF := 400.0
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

# A block facing east, 6 degrees north of it, attacked head-on (router-flank-anchor-1938's
# staging): it routs at tick 214 in contact, and its snapped flight turn leaves its grid
# 1.4696 to 1.4853 rad off its heading on the clip's seed runs 0 to 4, under a quarter-turn, so
# its front ranks become the flank the pursuers press. On main e78d81be (measured 2026-11-11)
# it anchored on men behind its centre on 137 to 190 of its 169 to 205 anchored ticks there.
const BAND_SEED := 19380
const BAND_ROUTER := {"team": 0, "type": "Infantry", "x": 900, "y": 900, "count": 80,
		"morale": 6.0, "formation": 1, "facing": [0.9945, -0.1045]}
const BAND_PURSUER := {"team": 1, "type": "Infantry", "x": 1019.3, "y": 887.5, "count": 120,
		"formation": 1, "facing": [-0.9945, 0.1045]}
const BAND_ROUT_BY_TICK := 300
# The block last anchors as one in contact 150 to 204 ticks after its rout on the clip's seed runs
# 0 to 4 on main and with the fix (on seed run 2 with the fix it comes back into contact long
# after), so 250 ticks watches its whole first stretch in contact on both trees.
const BAND_WATCH_TICKS := 250
# Half of the fewest anchored ticks on either tree across the seed runs (151, with the fix).
const BAND_MIN_ANCHORED_TICKS := 75
# The block's anchor should switch onto its heading once its flank trails, and stay there while
# it is anchored. Without the trail latch's margins it switched 1 to 3 times while anchored on
# the clip's seed runs 0 to 4 (measured 2026-11-11 on c41c9a8c), back and forth near the break.
const BAND_MAX_SWITCHES := 1

var _battle: Node = null


func after_each() -> void:
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	Replay.forced_seed = -1
	await get_tree().physics_frame


## A 40-man block facing north at `origin` with its grid folded `fold` off its heading, its men
## on their slots, routed (or in `state`) and in anchor contact.
func _folded_unit(fold: float, state: Unit.State = Unit.State.ROUTING,
		origin: Vector2 = Vector2.ZERO) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)
	u.facing = Vector2.UP
	u.position = origin
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


func test_a_router_under_a_quarter_turn_keeps_its_grid_front_while_it_leads() -> void:
	for origin in [Vector2.UP * ORIGIN_OFF, Vector2.DOWN * ORIGIN_OFF]:
		var u := _folded_unit(BAND_FOLD, Unit.State.ROUTING, origin)
		var n: int = u._sim_soldier_pos.size()
		assert_gt(_lead(u, u.near_front_soldier_indices(n)), 0.0,
				"setup: on their slots the grid's front ranks stand ahead of the centroid")
		u._update_router_front_trailing()
		assert_false(u.grid_front_trails(), "its front ranks lead it (at %s)" % origin)
		assert_false(u.position_anchor_on_heading(), "so it keeps them as its anchor")
		assert_eq(u.position_anchor_indices(n), u.near_front_soldier_indices(n))


func test_a_router_under_a_quarter_turn_whose_front_ranks_trail_anchors_on_its_heading() -> void:
	for origin in [Vector2.UP * ORIGIN_OFF, Vector2.DOWN * ORIGIN_OFF]:
		var u := _folded_unit(BAND_FOLD, Unit.State.ROUTING, origin)
		var n: int = u._sim_soldier_pos.size()
		# A pursuer holds the grid's front ranks, now a flank, back behind the block's centre.
		for i in u.near_front_soldier_indices(n):
			u._sim_soldier_pos[i] -= u.facing * HOLD_BACK
		assert_lt(_lead(u, u.near_front_soldier_indices(n)), -u.router_front_trail_enter,
				"setup: the held flank stands more than the enter margin behind the centroid")
		assert_lte(absf(u.grid_fold()), Unit.ROUTER_HEADING_ANCHOR_FOLD,
				"setup: the grid is turned no more than the fold threshold")
		u._update_router_front_trailing()
		assert_true(u.grid_front_trails(), "its front ranks trail it (at %s)" % origin)
		assert_true(u.position_anchor_on_heading(), "so it anchors on the men ahead along its heading")
		var indices: PackedInt32Array = u.position_anchor_indices(n)
		assert_eq(indices, u.heading_anchor_soldier_indices(n), "the men farthest ahead")
		assert_gt(_lead(u, indices), 0.0, "who stand ahead of the block's centroid")


func test_the_demo_record_reads_the_heading_anchor_rule() -> void:
	var u := _folded_unit(BAND_FOLD)
	assert_false(bool(DemoState.unit_record(u, {}, 1.0, false)["anchor_on_heading"]),
			"a block whose front ranks lead reads false")
	for i in u.near_front_soldier_indices(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] -= u.facing * HOLD_BACK
	u._update_router_front_trailing()
	assert_true(bool(DemoState.unit_record(u, {}, 1.0, false)["anchor_on_heading"]),
			"and true once they trail")


func test_the_trail_enter_margin_is_configurable() -> void:
	var u := _folded_unit(BAND_FOLD)
	var n: int = u._sim_soldier_pos.size()
	for i in u.near_front_soldier_indices(n):
		u._sim_soldier_pos[i] -= u.facing * HOLD_BACK
	var lead: float = _lead(u, u.near_front_soldier_indices(n))
	# Moving half the block HOLD_BACK back moves its front's lead by less than HOLD_BACK.
	assert_lt(-lead, HOLD_BACK, "setup: it trails by less than HOLD_BACK")
	u.router_front_trail_enter = HOLD_BACK
	u._update_router_front_trailing()
	assert_false(u.grid_front_trails(), "a trail inside the enter margin does not count")
	assert_false(u.position_anchor_on_heading(), "so it keeps its grid's front ranks")
	assert_eq(u.position_anchor_indices(n), u.near_front_soldier_indices(n))
	u.router_front_trail_enter = -lead * 0.5
	u._update_router_front_trailing()
	assert_true(u.grid_front_trails(), "the same trail past a lowered enter margin counts")


## Move the grid's front-rank men of `u` (the selection grid_front_trails reads) along its heading
## from where `home` has them, so their mean leads the whole block's centroid by `target` wu, and
## return the lead that results. Moving those k of n men by d moves the lead by d * (1 - k / n).
func _set_front_lead(u: Unit, home: PackedVector2Array, target: float) -> float:
	u._sim_soldier_pos = home.duplicate()
	var n: int = home.size()
	var front: PackedInt32Array = u.near_front_soldier_indices(n)
	var shift: float = (target - _lead(u, front)) / (1.0 - float(front.size()) / float(n))
	for i in front:
		u._sim_soldier_pos[i] += u.facing * shift
	return _lead(u, u.near_front_soldier_indices(n))


func test_the_trail_latch_holds_through_a_small_oscillation_about_zero_lead() -> void:
	var u := _folded_unit(BAND_FOLD)
	var home: PackedVector2Array = u._sim_soldier_pos.duplicate()
	var enter: float = u.router_front_trail_enter
	var leave: float = u.router_front_trail_leave
	assert_gt(enter, 0.0, "setup: a positive enter margin")
	assert_gt(leave, 0.0, "setup: a positive leave margin")
	# Each step: the lead to set, and whether the ranks should count as trailing after it.
	var steps: Array = [
		[-0.5 * enter, false],   # behind the centre, but inside the enter margin: not yet
		[0.5 * leave, false],
		[-0.5 * enter, false],
		[-1.5 * enter, true],    # past the enter margin: it trails
		[0.5 * leave, true],     # ahead again, but inside the leave margin: still trails
		[-0.5 * enter, true],
		[0.5 * leave, true],
		[1.5 * leave, false],    # past the leave margin: it leads again
		[-0.5 * enter, false],
	]
	for step in steps:
		var got: float = _set_front_lead(u, home, step[0])
		assert_almost_eq(got, step[0], 0.25 * minf(enter, leave),
				"setup: the front ranks lead by %.2f wu (got %.2f)" % [step[0], got])
		u._update_router_front_trailing()
		assert_eq(u.grid_front_trails(), step[1],
				"at a lead of %.2f wu the ranks count as trailing: %s" % [got, step[1]])
		assert_eq(u.position_anchor_on_heading(), step[1], "and the anchor follows the latch")


func test_the_trail_leave_margin_is_configurable() -> void:
	var u := _folded_unit(BAND_FOLD)
	var home: PackedVector2Array = u._sim_soldier_pos.duplicate()
	_set_front_lead(u, home, -2.0 * u.router_front_trail_enter)
	u._update_router_front_trailing()
	assert_true(u.grid_front_trails(), "setup: it trails")
	var lead: float = _set_front_lead(u, home, 2.0 * u.router_front_trail_leave)
	u.router_front_trail_leave = lead * 2.0
	u._update_router_front_trailing()
	assert_true(u.grid_front_trails(), "a lead inside a raised leave margin keeps it trailing")
	u.router_front_trail_leave = lead * 0.5
	u._update_router_front_trailing()
	assert_false(u.grid_front_trails(), "and past a lowered one it leads again")


func test_only_a_router_reads_the_trail_latch() -> void:
	var u := _folded_unit(BAND_FOLD)
	u._router_front_trailing = true
	assert_true(u.grid_front_trails(), "setup: latched")
	u.state = Unit.State.IDLE
	assert_false(u.grid_front_trails(), "only a router's front ranks can count as trailing")


func test_a_new_rout_clears_the_trail_latch() -> void:
	var u := _folded_unit(BAND_FOLD, Unit.State.FIGHTING)
	u._router_front_trailing = true
	u._rout()
	assert_eq(u.state, Unit.State.ROUTING, "setup: it routs")
	assert_false(u._router_front_trailing, "a fresh rout starts with its front ranks leading")


func test_a_router_with_no_bodies_has_no_trailing_front() -> void:
	var u: Unit = Unit.new()
	add_child_autofree(u)
	u.state = Unit.State.ROUTING
	assert_eq(u._sim_soldier_pos.size(), 0, "setup: no bodies")
	u.router_front_trail_enter = 0.0
	u._update_router_front_trailing()
	assert_false(u.grid_front_trails(), "no bodies stand behind anything")


func test_a_fold_a_whole_turn_round_reads_as_its_wrapped_angle() -> void:
	var u := _folded_unit(TAU + SMALL_FOLD)
	assert_false(u.position_anchor_on_heading(), "the fold is wrapped before it is compared")


func test_the_threshold_is_configurable() -> void:
	# A small fold whose front ranks lead, so only the threshold can move it onto its heading.
	var u := _folded_unit(SMALL_FOLD)
	var n: int = u._sim_soldier_pos.size()
	u._update_router_front_trailing()
	assert_false(u.grid_front_trails(), "setup: its front ranks lead it")
	assert_false(u.position_anchor_on_heading(), "setup: under the default it keeps them")
	u.router_heading_anchor_fold = SMALL_FOLD * 0.5
	assert_true(u.position_anchor_on_heading(), "a fold past a lowered threshold anchors on its heading")
	assert_eq(u.position_anchor_indices(n), u.heading_anchor_soldier_indices(n))


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
	var w: Dictionary = await _watch_anchor(router, EDGE_WATCH_TICKS, safety, 0.0)
	assert_gt(w["max_fold"], PI * 0.5, "setup: the flight turn left the grid's front pointing back")
	assert_gte(w["anchored"], EDGE_MIN_ANCHORED_TICKS,
			"setup: the router anchors on some of its men after the rout")
	assert_eq(w["trailing"], 0,
			"it never anchors on men behind its centre (%d of %d ticks, worst %.1f wu)"
			% [w["trailing"], w["anchored"], w["worst"]])


func test_a_router_whose_snap_left_its_front_on_a_flank_anchors_ahead_of_its_centre() -> void:
	var units: Dictionary = await _start([BAND_ROUTER, BAND_PURSUER], BAND_SEED)
	var router: Unit = units.get(0)
	assert_not_null(router, "setup: the block deployed")
	if router == null:
		return
	var safety: int = (BAND_ROUT_BY_TICK + BAND_WATCH_TICKS) * 4
	while (router.state != Unit.State.ROUTING and _battle.current_tick() < BAND_ROUT_BY_TICK
			and safety > 0):
		safety -= 1
		await get_tree().physics_frame
	assert_eq(router.state, Unit.State.ROUTING,
			"setup: the block routs by tick %d" % BAND_ROUT_BY_TICK)
	if router.state != Unit.State.ROUTING:
		return
	var w: Dictionary = await _watch_anchor(router, BAND_WATCH_TICKS, safety,
			router.router_front_trail_enter)
	assert_gt(w["max_fold"], Unit.FACING_SNAP_ABSORB_THRESHOLD,
			"setup: the flight turn snapped and folded the grid")
	assert_lte(w["max_fold"], Unit.ROUTER_HEADING_ANCHOR_FOLD,
			"setup: no further than the fold threshold, so the fold alone does not decide")
	assert_gt(w["front_trailed"], 0,
			"setup: its grid's front ranks fell behind its centre on some anchored tick")
	assert_gte(w["anchored"], BAND_MIN_ANCHORED_TICKS,
			"setup: the router anchors on some of its men after the rout")
	assert_eq(w["trailing"], 0,
			"it never anchors on men more than the enter margin behind its centre "
			+ "(%d of %d ticks, worst %.1f wu)" % [w["trailing"], w["anchored"], w["worst"]])
	assert_lte(w["switches"], BAND_MAX_SWITCHES,
			"its anchor switches onto its heading once and stays (%d switches)" % w["switches"])


## Watch `router` for `watch` ticks of its rout (or until it stops routing), counting the ticks it
## anchors on any men and those on which they stand more than `tolerance` behind its centroid
## along its heading, with the worst lead, the largest wrapped fold seen, the anchored ticks on
## which its grid's front ranks trail its centre (grid_front_trails), and how often
## position_anchor_on_heading changed between anchored ticks.
func _watch_anchor(router: Unit, watch: int, safety: int, tolerance: float) -> Dictionary:
	var rout_tick: int = _battle.current_tick()
	var out := {"anchored": 0, "trailing": 0, "worst": INF, "max_fold": 0.0, "front_trailed": 0,
			"switches": 0}
	var last_on_heading = null
	while _battle.current_tick() < rout_tick + watch and safety > 0:
		safety -= 1
		await get_tree().physics_frame
		if not is_instance_valid(router) or router.state != Unit.State.ROUTING:
			break
		out["max_fold"] = maxf(out["max_fold"], absf(wrapf(router.grid_fold(), -PI, PI)))
		var indices: PackedInt32Array = router.position_anchor_indices(router._sim_soldier_pos.size())
		if indices.is_empty():
			continue
		out["anchored"] += 1
		if router.grid_front_trails():
			out["front_trailed"] += 1
		var on_heading: bool = router.position_anchor_on_heading()
		if last_on_heading != null and on_heading != last_on_heading:
			out["switches"] += 1
		last_on_heading = on_heading
		var lead: float = _lead(router, indices)
		out["worst"] = minf(out["worst"], lead)
		if lead < -tolerance:
			out["trailing"] += 1
	return out
