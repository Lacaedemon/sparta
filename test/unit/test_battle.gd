extends GutTest
## Battle order dispatch: the waypoint-append path of
## _apply_order_cmd. A Battle is exercised directly via the script — not spawned
## into the scene — with units registered by uid, so the append/replace logic is
## covered without standing up a full battle. (_apply_order_cmd reads only the
## _by_uid map and the static formation_centroid, never the @onready scene nodes.)

const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")

var _orig_reform: bool

func before_each() -> void:
	_orig_reform = Settings.reform_before_move

func after_each() -> void:
	Settings.reform_before_move = _orig_reform


func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins groups, sets the footprint
	u.uid = uid
	u.position = pos
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


func test_plain_move_sets_target_and_clears_waypoints() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.set_current_order(Order.new_move(Vector2(900, 900)))
	u.append_order(Order.new_move(Vector2(999, 999)))   # a stale queued route leg
	u.has_move_target = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})
	assert_eq(u.move_target, Vector2(50, 0), "a plain move sets the destination")
	assert_true(u.has_move_target, "and marks the unit as moving")
	assert_true(u.queued_move_points().is_empty(), "a fresh order discards any queued route")


func test_rear_move_arms_the_about_face_and_parks_the_march() -> void:
	# A move to a destination behind a seeded unit about-faces (conversio) in place and
	# parks the march, rather than setting a move target that would slide it backwards.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()   # conversio needs seeded soldier bodies
	var b := _battle([u])
	Settings.reform_before_move = false
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})   # straight behind
	assert_true(u.is_order_turning(), "the about-face is armed on the order")
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.phase, Order.Phase.TURN)
	assert_false(u.has_move_target, "the march is parked, not started, during the turn")
	assert_eq(u.current_order.target_pos, Vector2(0, -200),
		"the ordered rear destination is parked on the order for after the about-face")


## Axis-aligned bounding box of a unit's live soldier bodies, as [width, height].
## The conversio signature: this box stays fixed (positions frozen) through the whole
## turn -- only facings reverse -- so a rotating box means the block centre-pivoted.
func _soldier_bbox(u: Unit) -> Vector2:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in u._sim_soldier_pos:
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)
	return max_p - min_p


## Mimic Battle._physics_process's live-order drain: for each pending order, apply it
## only if it wasn't already applied live (tagged by _apply_order_live). This is the
## exactly-once contract; the test drives it directly since the harness doesn't run
## the physics tick. Clears the queue like the real drain.
##
## Keep the "applied_live" key and the skip condition in lockstep with Battle.gd's drain
## (the `if not o.get("applied_live", false): _apply_order_cmd(o)` branch) and its
## _apply_order_live tag. If the key or gate changes there, change it here too, or these
## tests silently stop exercising the real path.
func _drain_pending(b) -> void:
	for o in b._pending_orders:
		if not o.get("applied_live", false):
			b._apply_order_cmd(o)
	b._pending_orders.clear()


func test_enqueue_order_applies_exactly_once_across_the_tick_drain() -> void:
	# enqueue_order applies live AND queues for the tick drain. The drain must NOT
	# re-apply an order already applied live, or a non-idempotent order (a rear-move
	# about-face, an arrow nudge) is corrupted on the second apply. The end state after
	# enqueue + drain must equal the state after a single apply.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	var b := _battle([u])
	Settings.reform_before_move = false
	b.enqueue_order([1], Vector2(0, -200), -1)   # rear move: applies live, tags the cmd
	assert_true(u.is_order_turning(), "the about-face armed on the live apply")
	var order_after_live: Order = u.current_order
	var turn_after_live: Vector2 = order_after_live.turn_target
	_drain_pending(b)   # the tick drain must be a no-op for this already-applied order
	assert_eq(u.current_order, order_after_live,
		"the drain did not re-apply the order and replace the in-flight composite")
	assert_eq(u.current_order.turn_target, turn_after_live,
		"the running about-face keeps its goal (no restart)")
	assert_false(u.has_move_target, "no march was started by a phantom second apply")
	assert_eq(u.current_order.phase, Order.Phase.TURN, "the parked rear march survives the drain")
	assert_eq(u.current_order.target_pos, Vector2(0, -200), "toward the ordered rear destination")


func test_order_once_vs_twice_yields_identical_unit_state() -> void:
	# The order-idempotency acceptance property: an order's observable effect is identical
	# whether or not the live immediate-apply fires. Confirm a single apply (the replay
	# path) and an enqueue + exactly-once drain (the live path) reach the same unit state,
	# so the two paths never diverge.
	var single := _unit(1, Vector2.ZERO)
	single.facing = Vector2.DOWN
	single.seed_sim_soldiers()
	var b1 := _battle([single])
	Settings.reform_before_move = false
	b1._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})

	var live := _unit(2, Vector2.ZERO)
	live.facing = Vector2.DOWN
	live.seed_sim_soldiers()
	var b2 := _battle([live])
	b2.enqueue_order([2], Vector2(0, -200), -1)
	_drain_pending(b2)

	assert_eq(live.current_order.turn_target, single.current_order.turn_target,
		"enqueue+drain arms the same about-face as a single apply")
	assert_eq(live.has_move_target, single.has_move_target, "same march-started flag")
	assert_eq(live.current_order.phase, single.current_order.phase, "same composite phase")
	assert_eq(live.current_order.target_pos, single.current_order.target_pos,
		"same parked destination")


func test_rear_move_holds_footprint_while_facings_reverse() -> void:
	# End to end: issue the rear move through the real live+drain path, then step _think
	# through the whole turn. The conversio must hold every soldier's position -- the
	# bounding box stays pinned -- while facings flip, then the block marches. A centre
	# pivot (the double-apply bug) instead rotates the box through its diagonal.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	var b := _battle([u])
	Settings.reform_before_move = false
	var start_bbox := _soldier_bbox(u)
	var start_facing := u._sim_soldier_facing[0]
	b.enqueue_order([1], Vector2(0, -200), -1)
	_drain_pending(b)   # exactly-once: the drain does not abort the conversio

	# Step through the turn. Until the march commits the box must stay pinned and the unit
	# must not translate -- the men turn where they stand.
	var march_started := false
	for _i in range(240):
		u._think(0.016)
		if u.has_move_target:
			march_started = true
			break
		var bbox := _soldier_bbox(u)
		assert_almost_eq(bbox.x, start_bbox.x, 1.0,
			"soldier-block width stays pinned through the about-face (no centre pivot)")
		assert_almost_eq(bbox.y, start_bbox.y, 1.0,
			"soldier-block height stays pinned through the about-face (no centre pivot)")
		assert_eq(u.position, Vector2.ZERO, "the block does not translate during the turn")
	assert_true(march_started, "the parked march commits once the about-face completes")

	# The facing reversed (the men turned around), and the footprint is unchanged.
	var end_facing := u.facing
	assert_almost_eq(end_facing.x, -start_facing.x, 0.01, "unit facing reversed in x")
	assert_almost_eq(end_facing.y, -start_facing.y, 0.01, "unit facing reversed in y")
	var end_bbox := _soldier_bbox(u)
	assert_almost_eq(end_bbox.x, start_bbox.x, 1.0, "final footprint width matches the start")
	assert_almost_eq(end_bbox.y, start_bbox.y, 1.0, "final footprint height matches the start")


func test_nudge_applied_once_targets_its_full_distance() -> void:
	# A nudge sets move_target = position + offset, a relative target. Exactly-once
	# application must leave that target a full NUDGE_DISTANCE from the start (guarding
	# the relative-target path against any future re-application that would recompute
	# it from a moved position and shrink the step).
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN   # so LEFT nudge steps in world +x (perp to facing)
	var b := _battle([u])
	Settings.reform_before_move = false
	b.enqueue_nudge([1], BattleScript.NudgeDir.LEFT)
	_drain_pending(b)
	assert_true(u.has_move_target, "the nudge sets a move target")
	var travel: float = u.position.distance_to(u.move_target)
	assert_almost_eq(travel, BattleScript.NUDGE_DISTANCE, 0.01,
		"the nudge target is a full NUDGE_DISTANCE from the start")


func test_enqueue_formation_applies_once_through_the_drain() -> void:
	# A formation change is idempotent, but it still routes through the same live-apply
	# + tagged-drain path; exercise it so a formation order sets the mode and the drain
	# doesn't need to touch it again.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_formation([1], UnitScript.FORMATION_LOOSE)
	assert_eq(u.formation_mode, UnitScript.FORMATION_LOOSE, "the live apply set the formation")
	_drain_pending(b)   # tagged -> the drain is a no-op for it
	assert_eq(u.formation_mode, UnitScript.FORMATION_LOOSE, "and it stays set after the drain")
	assert_true(b._pending_orders.is_empty(), "the drain cleared the queue")


func test_forward_move_does_not_arm_an_about_face() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	var b := _battle([u])
	Settings.reform_before_move = false
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 200.0, "target": -1})   # straight ahead
	assert_false(u.is_order_turning(), "a forward move does not about-face")
	assert_eq(u.current_order.phase, Order.Phase.NONE, "the move order is unphased")
	assert_true(u.has_move_target, "it marches normally")
	assert_eq(u.move_target, Vector2(0, 200), "toward the ordered destination")


func test_rear_move_falls_back_to_a_plain_march_when_bodies_unseeded() -> void:
	# Before soldier bodies seed, begin_about_face refuses; a rear move must still march
	# (via the normal path) rather than stalling with a parked destination nobody commits.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	var b := _battle([u])
	Settings.reform_before_move = false
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})
	assert_false(u.is_order_turning(), "no about-face armed without seeded bodies")
	assert_eq(u.current_order.phase, Order.Phase.NONE, "and nothing is parked in a turn phase")
	assert_true(u.has_move_target, "the unit still marches (fallback to a plain move)")
	assert_eq(u.move_target, Vector2(0, -200), "toward the ordered destination")


func test_rear_move_during_an_in_progress_about_face_preempts_the_drill() -> void:
	# A standing V-key about-face is already turning when a rear-move order arrives. A
	# fresh order replaces the queue: the drill's partial turn settles (no body surge) and
	# the rear move arms its OWN about-face composite -- exactly what a replay of this
	# recorded order produces, where the unrecorded drill never ran. (Under the old
	# parallel flags the live apply instead fell back to a plain march, a live-vs-replay
	# divergence in this corner.)
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.conversio()                                   # the standing about-face is now turning
	assert_true(u.is_order_turning(), "the standing about-face is in progress")
	var b := _battle([u])
	Settings.reform_before_move = false
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})   # rear move
	assert_eq(u.current_order.type, Order.Type.MOVE, "the fresh order replaced the drill")
	assert_eq(u.current_order.phase, Order.Phase.TURN, "and runs its own about-face composite")
	assert_false(u.has_move_target, "with the march parked until the turn completes")
	assert_eq(u.current_order.target_pos, Vector2(0, -200), "toward the ordered destination")


func test_rear_move_during_an_in_progress_wheel_preempts_the_swing() -> void:
	# A wheel (circumductio) is already swinging when a rear-move order arrives. The fresh
	# order replaces the queue, dropping the wheel where it stands (a partial swing is a
	# valid formation state), and arms its own about-face composite -- matching what a
	# replay of this order stream produces on both the live and playback paths.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()
	u.wheel(1)                                      # the wheel is now swinging
	assert_true(u.is_wheeling(), "the wheel is in progress")
	var b := _battle([u])
	Settings.reform_before_move = false
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})   # rear move
	assert_false(u.is_wheeling(), "the fresh order dropped the wheel where it stood")
	assert_eq(u.current_order.type, Order.Type.MOVE, "and replaced it on the queue")
	assert_eq(u.current_order.phase, Order.Phase.TURN, "arming the rear move's own about-face")
	assert_false(u.has_move_target, "with the march parked until the turn completes")
	assert_eq(u.current_order.target_pos, Vector2(0, -200), "toward the ordered destination")


func test_append_queues_a_waypoint_behind_the_current_target() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 200.0, "y": 0.0, "target": -1})
	b._apply_order_cmd(
		{"units": [1], "x": 400.0, "y": 0.0, "target": BattleScript.ORDER_APPEND_WAYPOINT}
	)
	assert_eq(u.move_target, Vector2(200, 0), "append leaves the current destination intact")
	assert_eq(u.queued_move_points().size(), 1, "append queues exactly one MOVE leg")
	assert_eq(u.queued_move_points()[0], Vector2(400, 0), "the queued leg is the appended point")


func test_append_to_idle_unit_starts_it_marching() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.has_move_target = false
	var b := _battle([u])
	b._apply_order_cmd(
		{"units": [1], "x": 150.0, "y": 0.0, "target": BattleScript.ORDER_APPEND_WAYPOINT}
	)
	assert_true(u.has_move_target, "appending to an idle unit starts it moving")
	assert_eq(u.move_target, Vector2(150, 0), "the first appended point becomes the target")
	assert_eq(u.current_order.type, Order.Type.MOVE, "the appended leg became the current order")
	assert_true(u.queued_move_points().is_empty(), "nothing is left queued behind it")


func test_append_via_enqueue_is_not_double_applied() -> void:
	# An append is the one order enqueue_order does NOT apply live: it leaves the cmd
	# untagged so the tick drain applies it once (applying it live too would queue the
	# leg twice). Simulate a live append on a unit already marching, then drain exactly
	# as the tick does -- the untagged append applies, and only once.
	var u := _unit(1, Vector2.ZERO)
	u.set_current_order(Order.new_move(Vector2(200, 0)))
	u.move_target = Vector2(200, 0)
	u.has_move_target = true   # already en route
	var b := _battle([u])
	b.enqueue_order([1], Vector2(400, 0), BattleScript.ORDER_APPEND_WAYPOINT)
	_drain_pending(b)
	assert_eq(u.queued_move_points().size(), 1, "an appended leg is queued exactly once, not doubled")
	assert_eq(u.queued_move_points()[0], Vector2(400, 0), "and holds the appended point")


func test_append_behind_a_busy_order_commits_when_promoted() -> void:
	# A leg appended while another order runs does NOT clobber the in-flight work: it
	# queues behind, and its march commits when the finished order retires and the leg
	# is promoted (retire_current_order -> _start_promoted_move).
	var u := _unit(1, Vector2.ZERO)
	var foe := _unit(9, Vector2(300, 0))
	foe.team = 1
	u.set_current_order(Order.new_attack(9))
	u.target_enemy = foe
	u.has_move_target = false
	var b := _battle([u, foe])
	b._apply_order_cmd(
		{"units": [1], "x": 400.0, "y": 0.0, "target": BattleScript.ORDER_APPEND_WAYPOINT}
	)
	assert_false(u.has_move_target, "the append leaves the fight's movement state alone")
	assert_eq(u.current_order.type, Order.Type.ATTACK, "and the attack stays current")
	# The fight resolves; the queued leg promotes and commits its march.
	u.target_enemy = null
	u._update_current_order()
	assert_eq(u.current_order.type, Order.Type.MOVE, "the queued leg is promoted")
	assert_true(u.has_move_target, "and commits its march")
	assert_eq(u.move_target, Vector2(400, 0), "toward the appended point")


# --- pending-append preview while paused -----------------------

func test_pending_append_is_previewed_without_being_applied() -> void:
	# An append isn't applied until the next physics tick (so it isn't doubled).
	# While paused that tick never runs, so the overlay previews it from
	# _pending_orders instead — without mutating the unit's queue.
	var u := _unit(1, Vector2.ZERO)
	u.has_move_target = false
	var b := _battle([u])
	b.enqueue_order([1], Vector2(300, 0), BattleScript.ORDER_APPEND_WAYPOINT)
	assert_false(u.has_move_target, "the append is not applied yet (no tick ran)")
	assert_true(u.queued_move_points().is_empty(), "and nothing is queued on the unit yet")
	var preview: Array = b.pending_append_points_for(u)
	assert_eq(preview.size(), 1, "the pending append is previewed")
	assert_eq(preview[0], Vector2(300, 0), "at the appended point (single unit: no offset)")


func test_pending_append_preview_uses_formation_offset() -> void:
	# A multi-unit append keeps each unit's offset from the group centroid; the
	# preview reproduces that exactly (positions are frozen while paused, so it
	# matches what the tick will apply).
	var a := _unit(1, Vector2(0, 0))
	var c := _unit(2, Vector2(100, 0))
	var b := _battle([a, c])
	b.enqueue_order([1, 2], Vector2(300, 0), BattleScript.ORDER_APPEND_WAYPOINT)
	# Centroid of (0,0) and (100,0) is (50,0); offsets are -50 and +50.
	assert_eq(b.pending_append_points_for(a)[0], Vector2(250, 0),
		"unit a previews at dest + its offset from the centroid")
	assert_eq(b.pending_append_points_for(c)[0], Vector2(350, 0),
		"unit c previews at dest + its offset from the centroid")


func test_pending_plain_move_is_not_previewed_as_append() -> void:
	# A plain move is applied immediately (shown via move_target) but its cmd still
	# sits in _pending_orders. pending_append_points_for filters on
	# target == ORDER_APPEND_WAYPOINT, so the plain move is excluded by target, not
	# by queue absence — it must not surface as a pending preview.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_order([1], Vector2(200, 0), -1)   # plain move
	assert_true(b.pending_append_points_for(u).is_empty(),
		"a plain move is not previewed as a pending append")


# --- order-mode framework --------------------------------------

func test_order_mode_is_stamped_on_a_fresh_order() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.HOLD})
	assert_eq(u.order_mode, BattleScript.OrderMode.HOLD,
		"a fresh order stamps its stance on the unit")


func test_order_mode_defaults_to_normal_when_absent() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.order_mode = BattleScript.OrderMode.HOLD   # a prior stance
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})   # no "mode"
	assert_eq(u.order_mode, BattleScript.OrderMode.NORMAL,
		"a mode-less / plain order resets the stance to NORMAL")


func test_enqueue_order_carries_the_mode() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_order([1], Vector2(50, 0), -1, BattleScript.OrderMode.SKIRMISH)
	assert_eq(int(b._pending_orders[-1]["mode"]), BattleScript.OrderMode.SKIRMISH,
		"the armed mode is recorded on the pending order")


func test_append_preserves_the_existing_stance() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.move_target = Vector2(200, 0)
	u.has_move_target = true
	u.order_mode = BattleScript.OrderMode.HOLD
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 400.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.order_mode, BattleScript.OrderMode.HOLD,
		"a waypoint append leaves the unit's stance unchanged")


# --- stance-change-only orders (phase 3) ------------------------------

func test_stance_order_writes_the_stance_in_place() -> void:
	# A standalone stance change writes the durable order_mode without touching movement.
	var u := _unit(1, Vector2.ZERO)
	u.move_target = Vector2(200, 0)
	u.has_move_target = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.HOLD})
	assert_eq(u.order_mode, BattleScript.OrderMode.HOLD, "the stance is written")
	assert_true(u.has_move_target, "movement state is untouched")
	assert_eq(u.move_target, Vector2(200, 0), "the march continues to the same point")


func test_stance_order_toggles_rank_relief() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": -1,
		"frontage": BattleScript.RankRelief.OFF})
	assert_false(u.rank_relief, "the rank-relief mode is written off")
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": -1,
		"frontage": BattleScript.RankRelief.ON})
	assert_true(u.rank_relief, "and written back on")


func test_stance_order_to_cycle_charge_restarts_in_the_charging_phase() -> void:
	# Matches a fresh move/attack order: entering cycle-charge drives in rather than
	# resuming a stale pull-back.
	var u := _unit(1, Vector2.ZERO)
	u._cycle_recharging = true   # stale pull-back phase from an earlier stint
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.CYCLE_CHARGE})
	assert_eq(u.order_mode, BattleScript.OrderMode.CYCLE_CHARGE)
	assert_false(u._cycle_recharging, "the loop restarts in its charging phase")


func test_stance_order_away_from_support_drops_the_ward() -> void:
	# A ward is meaningless without the SUPPORT stance, so switching stance in place
	# drops the guard duty like a fresh plain order would.
	var supporter := _unit(1, Vector2.ZERO)
	var ward := _unit(2, Vector2(100, 0))
	supporter.support_target = ward
	supporter.order_mode = BattleScript.OrderMode.SUPPORT
	var b := _battle([supporter, ward])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.HOLD})
	assert_null(supporter.support_target, "the stance switch drops the ward")
	assert_eq(supporter.order_mode, BattleScript.OrderMode.HOLD)


func test_stance_order_skips_a_dead_unit() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.state = UnitScript.State.DEAD
	u.rank_relief = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": -1,
		"frontage": BattleScript.RankRelief.OFF})
	assert_true(u.rank_relief, "a dead unit's modes are left alone")


func test_stance_order_with_negative_mode_leaves_the_stance() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.order_mode = BattleScript.OrderMode.SKIRMISH
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": -1,
		"frontage": BattleScript.RankRelief.OFF})
	assert_eq(u.order_mode, BattleScript.OrderMode.SKIRMISH,
		"a rank-relief-only stance order leaves the stance untouched")


func test_stance_order_leave_toggle_keeps_the_rank_relief_setting() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.rank_relief = false   # a prior stance order turned it off
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.HOLD,
		"frontage": BattleScript.RankRelief.LEAVE})
	assert_false(u.rank_relief, "a stance-only write leaves the rank-relief mode as it was")


func test_stance_order_occupies_the_queue_only_when_idle() -> void:
	# Same idle-only queue write as the formation branch: an idle unit's transcript shows
	# the STANCE order; a busy unit keeps its live order running.
	var idle := _unit(1, Vector2.ZERO)
	var busy := _unit(2, Vector2(100, 0))
	busy.set_current_order(Order.new_move(Vector2(300, 0)))
	busy.move_target = Vector2(300, 0)
	busy.has_move_target = true
	var b := _battle([idle, busy])
	b._apply_order_cmd({"units": [1, 2], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_STANCE_ONLY, "mode": BattleScript.OrderMode.HOLD})
	assert_eq(idle.current_order.type, Order.Type.STANCE,
		"an idle unit's queue reports the stance change")
	assert_eq(idle.current_order.stance, BattleScript.OrderMode.HOLD, "with its target stance")
	assert_eq(busy.current_order.type, Order.Type.MOVE,
		"a busy unit's live order is not replaced")
	assert_eq(busy.order_mode, BattleScript.OrderMode.HOLD,
		"but the durable stance is written all the same")


func test_enqueue_stance_records_and_applies_once() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_stance([1], BattleScript.OrderMode.CYCLE_CHARGE, BattleScript.RankRelief.OFF)
	assert_eq(u.order_mode, BattleScript.OrderMode.CYCLE_CHARGE, "applied live")
	assert_false(u.rank_relief, "both writes land")
	var cmd: Dictionary = b._pending_orders[-1]
	assert_eq(int(cmd["target"]), BattleScript.ORDER_STANCE_ONLY, "queued for recording")
	assert_true(bool(cmd.get("applied_live", false)),
		"and tagged so the tick drain records without a second apply")


# --- support / defend ------------------------------------------------

func test_support_order_sets_the_ward_not_a_relief() -> void:
	var supporter := _unit(1, Vector2.ZERO)
	supporter.team = 0
	var ward := _unit(2, Vector2(100, 0))
	ward.team = 0
	ward.state = UnitScript.State.FIGHTING   # would be a line-relief target without SUPPORT
	var b := _battle([supporter, ward])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0, "target": 2,
		"mode": BattleScript.OrderMode.SUPPORT})
	assert_eq(supporter.support_target, ward, "a SUPPORT order guards the targeted friendly")
	assert_eq(supporter.order_mode, BattleScript.OrderMode.SUPPORT, "and stamps the SUPPORT stance")
	assert_eq(supporter.current_order.type, Order.Type.SUPPORT,
		"it does not start a line relief on the ward")
	assert_false(supporter._separation_exempt(ward), "so no relief pass-through exemption arms")


func test_plain_order_clears_a_prior_support_ward() -> void:
	var supporter := _unit(1, Vector2.ZERO)
	var ward := _unit(2, Vector2(100, 0))
	supporter.support_target = ward
	supporter.order_mode = BattleScript.OrderMode.SUPPORT
	var b := _battle([supporter, ward])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})   # plain move
	assert_null(supporter.support_target, "a fresh plain order drops the guard duty")
	assert_eq(supporter.order_mode, BattleScript.OrderMode.NORMAL, "and resets the stance")


func test_relief_order_skips_response_delay() -> void:
	# The primary reliever must advance immediately — a delay lets the tired unit
	# retreat into an uncovered gap. _apply_order_cmd skips start_order_response()
	# for the unit that calls UnitRelief.begin(), so its timer stays at 0.0.
	var fresh := _unit(1, Vector2.ZERO)
	fresh.team = 0
	fresh.order_response_delay = 0.5
	var tired := _unit(2, Vector2(100, 0))
	tired.team = 0
	tired.state = UnitScript.State.FIGHTING
	var b := _battle([fresh, tired])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0, "target": 2})
	assert_eq(fresh._order_response_timer, 0.0,
			"the primary reliever is not delayed — it advances into the gap immediately")


func test_append_preserves_a_support_ward() -> void:
	# An append continues the current order, so — like the stance — it leaves a
	# unit's support ward intact rather than clearing it.
	var supporter := _unit(1, Vector2.ZERO)
	var ward := _unit(2, Vector2(100, 0))
	supporter.support_target = ward
	supporter.order_mode = BattleScript.OrderMode.SUPPORT
	supporter.move_target = Vector2(200, 0)
	supporter.has_move_target = true
	var b := _battle([supporter, ward])
	b._apply_order_cmd({"units": [1], "x": 400.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(supporter.support_target, ward, "a waypoint append leaves the support ward intact")


# --- terrain / pathfinding integration ---------------------------------

## Mirrors Battle._ready() terrain registration — keep in sync if Battle changes.
func _registered_pathfield() -> PathField:
	var pf := PathField.new(BattleScript.FIELD)
	for patch in BattleScript.TERRAIN:
		if patch.get("kind", "block") == "slow":
			assert(patch.has("speed"), "slow terrain patch missing required 'speed' key")
			pf.set_speed_rect(patch["rect"], float(patch["speed"]))
		else:
			pf.block_rect(patch["rect"])
	return pf


func _patch_by_type(type: String) -> Dictionary:
	var matches := BattleScript.TERRAIN.filter(func(p): return p["type"] == type)
	assert(matches.size() > 0, "TERRAIN has no patch of type '%s'" % type)
	return matches[0]


func test_hill_blocks_pathfinding() -> void:
	var pf := _registered_pathfield()
	var hill: Dictionary = _patch_by_type("hill")
	var center: Vector2 = hill["rect"].position + hill["rect"].size * 0.5
	assert_true(pf.is_blocked(center), "the hill terrain patch blocks movement at its centre")


func test_hill_route_avoids_patch() -> void:
	var pf := _registered_pathfield()
	var hill: Dictionary = _patch_by_type("hill")
	var cx: float = hill["rect"].position.x + hill["rect"].size.x * 0.5
	var above := Vector2(cx, hill["rect"].position.y - 100)
	var below := Vector2(cx, hill["rect"].end.y + 100)
	var route := pf.find_path(above, below)
	assert_true(route.size() > 0,
			"A* finds a route around the hill (field is wide enough to detour)")
	for p in route:
		assert_false(hill["rect"].has_point(p), "no A* waypoint passes through the hill rect")


func test_forest_is_not_blocked() -> void:
	# Forest is a slow zone, not impassable: units can enter it.
	var pf := _registered_pathfield()
	var forest: Dictionary = _patch_by_type("forest")
	var center: Vector2 = forest["rect"].position + forest["rect"].size * 0.5
	assert_false(pf.is_blocked(center), "the forest patch is passable (slow, not blocked)")


# --- reform-before-move ------------------------------------------------

func test_reform_cmd_starts_reform_timer_not_move_target() -> void:
	# "reform": true → destination stored in _reform_target, timer started, has_move_target stays false.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1, "reform": true})
	assert_false(u.has_move_target,
		"a reform order doesn't set has_move_target until the timer expires")
	assert_gt(u._reform_timer, 0.0, "the reform timer starts counting")
	assert_eq(u._reform_target, Vector2(50, 0), "the destination is stored for later commit")


func test_no_reform_cmd_sets_move_target_directly() -> void:
	# "reform": false (or absent) → old behaviour: has_move_target set immediately.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1, "reform": false})
	assert_true(u.has_move_target, "reform:false sets has_move_target immediately")
	assert_eq(u.move_target, Vector2(50, 0))
	assert_eq(u._reform_timer, 0.0, "no reform timer is started")


func test_reform_cmd_absent_sets_move_target_directly() -> void:
	# Old replay logs without the "reform" key default to false (no reform).
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})
	assert_true(u.has_move_target, "missing reform key behaves as reform:false")
	assert_eq(u._reform_timer, 0.0)


func test_fresh_order_cancels_in_progress_reform() -> void:
	# A second plain order clears the pending reform from the first.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1, "reform": true})
	assert_gt(u._reform_timer, 0.0, "first reform order starts the timer")
	b._apply_order_cmd({"units": [1], "x": 200.0, "y": 0.0, "target": -1, "reform": false})
	assert_eq(u._reform_timer, 0.0, "a fresh order cancels the pending reform")
	assert_true(u.has_move_target, "and the new destination is committed immediately")
	assert_eq(u.move_target, Vector2(200, 0))


func test_current_speed_survives_the_reform_hold_while_cruising() -> void:
	# Companion to the order-response-freeze regression in test_unit.gd: a unit that's
	# already cruising and gets re-ordered with reform_before_move on is frozen twice in
	# a row -- first by order_response_delay, then (once that expires) by the
	# reform-before-move hold itself (_reform_timer, started here via "reform": true).
	# _move_to() doesn't run during either freeze, so Unit._physics_process's end-of-frame
	# idle-clear must not mistake the reform hold for genuine idleness and zero the speed
	# once the order-response timer alone has drained.
	var u := _unit(1, Vector2.ZERO)
	u._current_speed = u.walk_speed   # as if it was already cruising
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 500.0, "y": 0.0, "target": -1, "reform": true})
	assert_gt(u._reform_timer, 0.0, "the reform order starts the reform-hold timer")
	# Drain only the order-response timer (not the longer reform hold) so the unit is
	# still frozen by _reform_timer alone on the final tick.
	while u._order_response_timer > 0.0:
		u._physics_process(0.016)
	assert_gt(u._reform_timer, 0.0, "the reform hold is still running (0.8s > 0.5s response delay)")
	assert_almost_eq(u._current_speed, u.walk_speed, 0.001,
		"speed survives the reform hold too, not just the order-response freeze")


func test_enqueue_order_embeds_reform_setting() -> void:
	# enqueue_order stamps the live Settings.reform_before_move into the command.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	var orig: bool = Settings.reform_before_move
	Settings.reform_before_move = true
	b.enqueue_order([1], Vector2(50, 0), -1)
	assert_true(bool(b._pending_orders[-1].get("reform", false)),
		"with reform_before_move on, the command carries reform:true")
	Settings.reform_before_move = false
	b.enqueue_order([1], Vector2(50, 0), -1)
	assert_false(bool(b._pending_orders[-1].get("reform", false)),
		"with reform_before_move off, the command carries reform:false")
	Settings.reform_before_move = orig


func test_forest_slows_movement() -> void:
	var pf := _registered_pathfield()
	var forest: Dictionary = _patch_by_type("forest")
	var center: Vector2 = forest["rect"].position + forest["rect"].size * 0.5
	assert_almost_eq(pf.speed_at(center), float(forest["speed"]), 0.001,
			"the forest speed zone returns the configured speed scale")


# --- world scale / weapon reach --------------------------------------

func test_world_scale_keeps_the_sword_baseline_at_the_old_reach() -> void:
	# The infantry sword's 1.3 m reach maps to exactly the prior flat 26-unit
	# attack_range, so the melee baseline is unchanged; only longer/shorter weapons
	# diverge from it. Pins WORLD_UNITS_PER_METER against silent drift.
	assert_almost_eq(1.3 * BattleScript.WORLD_UNITS_PER_METER, 26.0, 0.001,
			"the 1.3 m sword reach equals the 26-unit melee baseline")
	assert_gt(2.4 * BattleScript.WORLD_UNITS_PER_METER, 1.3 * BattleScript.WORLD_UNITS_PER_METER,
			"the spear out-reaches the sword")


func test_charge_reference_matches_the_cavalry_gallop() -> void:
	# The cavalry loadout's 8.5 m/s gallop, in world units, equals the charge
	# reference speed, so a full-speed head-on charge peaks at the intended bonus.
	# Pins the coupling between Battle's cavalry speed and Unit's charge knob.
	assert_almost_eq(8.5 * BattleScript.WORLD_UNITS_PER_METER, UnitScript.CHARGE_REFERENCE_SPEED,
			0.001, "cavalry gallop (8.5 m/s) in world units == the charge reference speed")
	assert_gt(8.5 * BattleScript.WORLD_UNITS_PER_METER, 3.0 * BattleScript.WORLD_UNITS_PER_METER,
			"cavalry gallop outpaces the quickest foot (archers, 3.0 m/s)")


# --- frontage resize ------------------------------------

func test_enqueue_frontage_sets_an_absolute_target_from_the_current_width() -> void:
	# A 60-soldier unit's auto frontage is _files(60); widening by 3 records and
	# applies that as an absolute file count (not a delta), so re-application is safe.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 60
	var start: int = UnitFormation.frontage(u)
	var b := _battle([u])
	b.enqueue_frontage([1], 3)
	assert_eq(UnitFormation.frontage(u), start + 3, "widen steps the line out by three files")
	assert_eq(int(b._pending_orders[-1]["frontage"]), start + 3,
		"the absolute target width is recorded on the pending order")
	assert_eq(int(b._pending_orders[-1]["target"]), BattleScript.ORDER_FRONTAGE_ONLY,
		"tagged as a frontage-only command")


func test_frontage_apply_is_idempotent_under_reapplication() -> void:
	# Orders apply exactly once now, but a frontage command carries an ABSOLUTE target
	# so it stays safe to apply more than once (a delta would double). Apply the same
	# command a second time directly and confirm the width is unchanged -- the property
	# that lets the absolute encoding survive any accidental re-application.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 80
	var start: int = UnitFormation.frontage(u)
	var b := _battle([u])
	b.enqueue_frontage([1], 4)   # applies live (once)
	for o in b._pending_orders:
		b._apply_order_cmd(o)     # apply the identical command again: must be a no-op
	assert_eq(UnitFormation.frontage(u), start + 4,
		"re-applying the absolute-frontage command leaves the width unchanged (idempotent)")


func test_enqueue_frontage_clamps_at_the_extremes() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 40
	var b := _battle([u])
	b.enqueue_frontage([1], -999)
	assert_eq(UnitFormation.frontage(u), 1, "narrowing can't go below a single file")
	b.enqueue_frontage([1], 999)
	assert_eq(UnitFormation.frontage(u), 40, "widening can't exceed max_soldiers")


func test_enqueue_frontage_steps_each_unit_from_its_own_width() -> void:
	# A mixed selection: each unit resolves its own current frontage, so the same
	# delta keeps their relative widths (one command emitted per unit).
	var a := _unit(1, Vector2.ZERO)
	a.max_soldiers = 40
	var c := _unit(2, Vector2(200, 0))
	c.max_soldiers = 160
	var fa: int = UnitFormation.frontage(a)
	var fc: int = UnitFormation.frontage(c)
	var b := _battle([a, c])
	b.enqueue_frontage([1, 2], 2)
	assert_eq(UnitFormation.frontage(a), fa + 2, "unit a widens from its own width")
	assert_eq(UnitFormation.frontage(c), fc + 2, "unit c widens from its own width")


# --- file-doubling (duplicatio / explicatio) ------------

func test_explicatio_doubles_the_frontage() -> void:
	# EXPLICATIO (direction > 0): each file splits, doubling the frontage. Full strength,
	# so widened_files isn't capped by the live count.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 120
	var b := _battle([u])
	var start: int = UnitFormation.frontage(u)
	b.enqueue_file_double([1], 1)
	assert_eq(UnitFormation.frontage(u), start * 2, "explicatio doubles the files")
	assert_eq(int(b._pending_orders[-1]["frontage"]), start * 2,
		"the reshaped absolute width is recorded")
	assert_eq(int(b._pending_orders[-1]["target"]), BattleScript.ORDER_FRONTAGE_ONLY,
		"reuses the frontage-only command path (so it records and replays)")


func test_duplicatio_halves_the_frontage() -> void:
	# DUPLICATIO (direction < 0): alternate files tuck in behind, halving the frontage.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 120
	var b := _battle([u])
	var start: int = UnitFormation.frontage(u)
	b.enqueue_file_double([1], -1)
	assert_eq(UnitFormation.frontage(u), maxi(1, start / 2), "duplicatio halves the files")


func test_file_double_round_trips() -> void:
	# Explicatio then duplicatio returns a unit to its start width.
	var u := _unit(1, Vector2.ZERO)
	# 128 men leaves plenty of soldiers for the widened rank (frontage 15 -> 30 files,
	# well under 128), so explicatio isn't capped by the count and halve(double(f)) == f
	# exactly. (A small count where widened_files hits its single-rank cap wouldn't round-trip.)
	u.max_soldiers = 128
	var b := _battle([u])
	var start: int = UnitFormation.frontage(u)
	b.enqueue_file_double([1], 1)
	b.enqueue_file_double([1], -1)
	assert_eq(UnitFormation.frontage(u), start, "widen then narrow returns to the start width")


func test_explicatio_is_capped_at_a_single_rank() -> void:
	# widened_files caps at the live soldier count: a depleted unit can't widen past one rank.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 120
	u.soldiers = 10                # fewer men than double the auto frontage
	var b := _battle([u])
	b.enqueue_file_double([1], 1)
	assert_eq(UnitFormation.frontage(u), 10, "widening can't exceed the live soldier count")


func test_duplicatio_floors_at_one_file() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 120
	var b := _battle([u])
	u.set_frontage(1)
	b.enqueue_file_double([1], -1)
	assert_eq(UnitFormation.frontage(u), 1, "narrowing can't go below a single column")


func test_file_double_apply_is_idempotent_under_reapplication() -> void:
	# Like the frontage command, a file-double carries an ABSOLUTE reshaped width, so it
	# stays safe to apply more than once even though orders now apply exactly once. Apply
	# the same command a second time directly and confirm the width holds.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 120
	var b := _battle([u])
	var start: int = UnitFormation.frontage(u)
	b.enqueue_file_double([1], 1)   # applies live (once)
	for o in b._pending_orders:
		b._apply_order_cmd(o)        # apply the identical command again: must be a no-op
	assert_eq(UnitFormation.frontage(u), start * 2,
		"re-applying the absolute file-double command leaves the width unchanged (idempotent)")


# --- drag-to-form-up ------------------------------------

func test_enqueue_form_up_sets_destination_facing_and_width() -> void:
	var u := _unit(1, Vector2(0, 100))
	u.max_soldiers = 120
	var b := _battle([u])
	b.enqueue_form_up([1], Vector2(500, 500), 0.0, 20)   # face 0 = facing right
	assert_eq(u._reform_target, Vector2(500, 500), "the form-up target is queued pending the reform hold")
	assert_false(u.has_move_target, "unit waits in reform hold before stepping off")
	assert_almost_eq(u.deploy_facing.angle(), 0.0, 0.001, "the deploy facing is parked from the order")
	assert_eq(UnitFormation.frontage(u), 20, "the dragged width becomes the frontage")
	assert_true(b._pending_orders[-1].has("face"), "the order records its deploy facing")


func test_plain_move_clears_a_stale_deploy_facing() -> void:
	# A form-up parks a deploy facing; a superseding plain move must clear it so the
	# unit doesn't pivot to the old heading at the new destination.
	var u := _unit(1, Vector2(0, 100))
	var b := _battle([u])
	b.enqueue_form_up([1], Vector2(500, 500), 1.0, 20)
	assert_ne(u.deploy_facing, Vector2.ZERO, "form-up parks a deploy facing")
	b._apply_order_cmd({"units": [1], "x": 300.0, "y": 0.0, "target": -1})   # plain move
	assert_eq(u.deploy_facing, Vector2.ZERO, "a superseding plain move clears the stale facing")


func test_attack_order_clears_a_stale_deploy_facing() -> void:
	# A non-move order (here an attack) must also clear a deploy facing a prior
	# form-up parked, now that the clear lives in the shared fresh-order block.
	var u := _unit(1, Vector2(0, 100))
	var enemy := _unit(2, Vector2(0, 300))
	enemy.team = 1
	var b := _battle([u, enemy])
	b.enqueue_form_up([1], Vector2(500, 500), 1.0, 20)
	assert_ne(u.deploy_facing, Vector2.ZERO, "form-up parks a deploy facing")
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0, "target": 2})   # attack the enemy
	assert_eq(u.deploy_facing, Vector2.ZERO, "an attack order clears the stale facing")


# --- move orders do not snap facing at order time ----------------------------
# An orderly move centre-pivots gradually toward its heading in Unit (during the
# reform hold and as it marches); _apply_order_cmd must NOT flip the unit's facing
# when the order lands, or the gradual pivot (and the side-step's held facing) is lost.

func test_plain_move_does_not_snap_facing_at_order_time() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 100.0, "y": 0.0, "target": -1})
	assert_eq(u.facing, Vector2.DOWN,
		"facing is left for the orderly centre pivot in _move_to, not snapped at order time")


func test_reform_move_does_not_snap_facing_at_order_time() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 100.0, "y": 0.0, "target": -1, "reform": true})
	assert_eq(u.facing, Vector2.DOWN,
		"the unit pivots in place during the reform hold (in _think), not at order time")


# --- Side-step maneuver (the small-lateral-shift classification) --------------

func test_small_lateral_move_holds_facing_as_a_sidestep() -> void:
	# A unit facing +x ordered a short shift along +/-y should side-step: it keeps
	# its facing and the move branch records the held heading in ordered_facing.
	Settings.reform_before_move = false
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 20.0, "target": -1})
	assert_eq(u.ordered_facing, Vector2.RIGHT, "a small lateral move holds the current facing")
	assert_true(u.has_move_target, "and still marches toward the destination")


func test_forward_move_does_not_set_a_sidestep_facing() -> void:
	Settings.reform_before_move = false
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})
	assert_eq(u.ordered_facing, Vector2.ZERO,
		"marching straight ahead turns to face travel (no held facing)")


func test_a_fresh_order_clears_a_prior_sidestep_hold() -> void:
	Settings.reform_before_move = false
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 20.0, "target": -1})   # side-step
	assert_eq(u.ordered_facing, Vector2.RIGHT, "side-step holds facing")
	b._apply_order_cmd({"units": [1], "x": 500.0, "y": 0.0, "target": -1})  # long forward march
	assert_eq(u.ordered_facing, Vector2.ZERO, "the next non-lateral order drops the hold")


func test_form_up_order_never_side_steps() -> void:
	# A form-up commands its own deploy facing, so even a short shift must not be
	# reinterpreted as a side-step.
	Settings.reform_before_move = false
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b.enqueue_form_up([1], Vector2(0, 20), 1.0, 20)   # short lateral form-up
	assert_eq(u.ordered_facing, Vector2.ZERO, "form-up uses deploy_facing, not a side-step hold")
	assert_ne(u.deploy_facing, Vector2.ZERO, "...and parks its commanded facing instead")
