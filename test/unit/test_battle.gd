extends GutTest
## Battle order dispatch: the waypoint-append path of
## _apply_order_cmd. A Battle is exercised directly via the script — not spawned
## into the scene — with units registered by uid, so the append/replace logic is
## covered without standing up a full battle. (_apply_order_cmd reads only the
## _by_uid map and the static formation_centroid, never the @onready scene nodes.)

const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins groups, sets the footprint
	u.uid = uid
	u.position = pos
	# reform_before_move is a per-unit field now, read straight off the unit rather
	# than a cmd-level "reform" flag or Settings.reform_before_move -- default it off so a
	# bare _apply_order_cmd() call in a test not otherwise concerned with the reform hold
	# still marches immediately, matching this suite's long-standing convention (a raw cmd
	# dict here never carried a "reform" key, which used to default to false the same way).
	u.reform_before_move = false
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
	# Straight ahead of the unit's default (DOWN) facing -- a large lateral destination
	# would instead arm a lateral-pivot maneuver (see test_lateral_pivot_maneuver.gd),
	# which this test isn't about.
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 50.0, "target": -1})
	assert_eq(u.move_target, Vector2(0, 50), "a plain move sets the destination")
	assert_true(u.has_move_target, "and marks the unit as moving")
	assert_true(u.queued_move_points().is_empty(), "a fresh order discards any queued route")


func test_rear_move_arms_the_about_face_and_parks_the_march() -> void:
	# A move to a destination behind a seeded unit about-faces (conversio) in place and
	# parks the march, rather than setting a move target that would slide it backwards.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	u.seed_sim_soldiers()   # conversio needs seeded soldier bodies
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})   # straight behind
	assert_true(u.is_order_turning(), "the about-face is armed on the order")
	assert_eq(u.current_order.type, Order.Type.MOVE)
	assert_eq(u.current_order.effective_phase_name(), "TURN")
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
	b.enqueue_order([1], Vector2(0, -200), -1)   # rear move: applies live, tags the cmd
	assert_true(u.is_order_turning(), "the about-face armed on the live apply")
	var order_after_live: Order = u.current_order
	var turn_after_live: Vector2 = u.active_leaf().turn_target
	_drain_pending(b)   # the tick drain must be a no-op for this already-applied order
	assert_eq(u.current_order, order_after_live,
		"the drain did not re-apply the order and replace the in-flight composite")
	assert_eq(u.active_leaf().turn_target, turn_after_live,
		"the running about-face keeps its goal (no restart)")
	assert_false(u.has_move_target, "no march was started by a phantom second apply")
	assert_eq(u.current_order.effective_phase_name(), "TURN", "the parked rear march survives the drain")
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
	b1._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})

	var live := _unit(2, Vector2.ZERO)
	live.facing = Vector2.DOWN
	live.seed_sim_soldiers()
	var b2 := _battle([live])
	b2.enqueue_order([2], Vector2(0, -200), -1)
	_drain_pending(b2)

	assert_eq(live.active_leaf().turn_target, single.active_leaf().turn_target,
		"enqueue+drain arms the same about-face as a single apply")
	assert_eq(live.has_move_target, single.has_move_target, "same march-started flag")
	assert_eq(live.current_order.effective_phase_name(), single.current_order.effective_phase_name(),
		"same composite phase")
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
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 200.0, "target": -1})   # straight ahead
	assert_false(u.is_order_turning(), "a forward move does not about-face")
	assert_true(u.current_order.children.is_empty(), "the move order stayed a plain leaf, unphased")
	assert_true(u.has_move_target, "it marches normally")
	assert_eq(u.move_target, Vector2(0, 200), "toward the ordered destination")


func test_rear_move_falls_back_to_a_plain_march_when_bodies_unseeded() -> void:
	# Before soldier bodies seed, begin_about_face refuses; a rear move must still march
	# (via the normal path) rather than stalling with a parked destination nobody commits.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.DOWN
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})
	assert_false(u.is_order_turning(), "no about-face armed without seeded bodies")
	assert_true(u.current_order.children.is_empty(), "and nothing is parked in a turn phase")
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
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})   # rear move
	assert_eq(u.current_order.type, Order.Type.MOVE, "the fresh order replaced the drill")
	assert_eq(u.current_order.effective_phase_name(), "TURN", "and runs its own about-face composite")
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
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": -200.0, "target": -1})   # rear move
	assert_false(u.is_wheeling(), "the fresh order dropped the wheel where it stood")
	assert_eq(u.current_order.type, Order.Type.MOVE, "and replaced it on the queue")
	assert_eq(u.current_order.effective_phase_name(), "TURN", "arming the rear move's own about-face")
	assert_false(u.has_move_target, "with the march parked until the turn completes")
	assert_eq(u.current_order.target_pos, Vector2(0, -200), "toward the ordered destination")


func test_append_queues_a_waypoint_behind_the_current_target() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	# Straight ahead of the unit's default (DOWN) facing -- a large lateral first leg
	# would instead arm a lateral-pivot maneuver, which this test isn't about.
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 200.0, "target": -1})
	b._apply_order_cmd(
		{"units": [1], "x": 0.0, "y": 400.0, "target": BattleScript.ORDER_APPEND_WAYPOINT}
	)
	assert_eq(u.move_target, Vector2(0, 200), "append leaves the current destination intact")
	assert_eq(u.queued_move_points().size(), 1, "append queues exactly one MOVE leg")
	assert_eq(u.queued_move_points()[0], Vector2(0, 400), "the queued leg is the appended point")


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


func test_append_with_run_gait_does_not_mark_the_leg_as_in_haste() -> void:
	# SelectionManager._gait_from_click_count forces gait == RUN on every waypoint append
	# (Shift+right-click), regardless of click count, to keep travel speed continuous with
	# the leg before it -- not to signal urgency. The appended leg must not be "in haste"
	# just because of that forced gait, or a disciplined unit would silently skip its formed
	# centre-pivot on an ordinary waypoint-chained march. Append to an IDLE unit, like
	# test_append_to_idle_unit_starts_it_marching, so the appended leg becomes current_order
	# immediately and _is_move_order_in_haste() is actually checking it, not an earlier order.
	var u := _unit(1, Vector2.ZERO)
	u.has_move_target = false
	var b := _battle([u])
	b._apply_order_cmd({
		"units": [1], "x": 150.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "gait": Unit.GAIT_RUN,
	})
	assert_eq(u.current_order.gait, Unit.GAIT_RUN, "sanity: the leg carries the forced RUN gait")
	assert_false(u._is_move_order_in_haste(),
		"an append-forced RUN gait does not make the appended leg 'in haste'")


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


# --- unit-settings-only orders (walk_advance / reform_before_move) --------------

func test_unit_settings_order_writes_walk_advance_and_reform_in_place() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = false
	u.reform_before_move = true
	u.move_target = Vector2(200, 0)
	u.has_move_target = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"walk_advance_toggle": BattleScript.UnitSettingToggle.ON,
		"reform_toggle": BattleScript.UnitSettingToggle.OFF})
	assert_true(u.walk_advance, "the ON toggle writes walk_advance")
	assert_false(u.reform_before_move, "the OFF toggle writes reform_before_move")
	assert_true(u.has_move_target, "movement state is untouched")
	assert_eq(u.move_target, Vector2(200, 0), "the march continues to the same point")


func test_unit_settings_order_leave_toggle_keeps_the_current_value() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = true
	u.reform_before_move = false
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"walk_advance_toggle": BattleScript.UnitSettingToggle.LEAVE,
		"reform_toggle": BattleScript.UnitSettingToggle.LEAVE})
	assert_true(u.walk_advance, "LEAVE keeps walk_advance as it was")
	assert_false(u.reform_before_move, "LEAVE keeps reform_before_move as it was")


func test_ai_directive_shaped_move_reads_the_units_own_reform_before_move() -> void:
	# UnitLeader._move_directive_cmd (a subcommander HOLD_LINE/COVER_FLANK directive) builds
	# a minimal cmd -- {"units", "x", "y", "target": -1} -- with no "mode"/"reform" key at
	# all, unlike a player order (enqueue_order/enqueue_form_up). Before this migration,
	# order.reform read cmd.get("reform", false), which always defaulted false for this
	# AI-shaped cmd regardless of Settings.reform_before_move -- an AI directive move never
	# got the reform hold. Now order.reform reads the unit's OWN reform_before_move field
	# directly, so an AI-controlled unit gets the same reform hold a player-ordered unit
	# with the same setting would. Deliberate, tested consequence of the per-unit migration,
	# not an oversight -- see the PR description for the design rationale.
	var on := _unit(1, Vector2.ZERO)
	on.reform_before_move = true
	var b_on := _battle([on])
	b_on._apply_order_cmd({"units": [1], "x": 0.0, "y": 200.0, "target": -1})   # AI-directive shape
	assert_true(on.current_order.reform,
		"an AI-directive move on a unit with reform_before_move=true now arms the reform hold")

	var off := _unit(2, Vector2.ZERO)
	off.reform_before_move = false
	var b_off := _battle([off])
	b_off._apply_order_cmd({"units": [2], "x": 0.0, "y": 200.0, "target": -1})
	assert_false(off.current_order.reform,
		"and a unit with reform_before_move=false (e.g. Cavalry's own type default) still skips it")


func test_unit_settings_order_can_toggle_just_one_field() -> void:
	# A mixed selection's untouched setting isn't forced to a single value: only the
	# named field's toggle needs to be non-LEAVE.
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = false
	u.reform_before_move = false
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"walk_advance_toggle": BattleScript.UnitSettingToggle.ON})
	assert_true(u.walk_advance, "walk_advance is written")
	assert_false(u.reform_before_move, "reform_before_move (omitted -> LEAVE) is untouched")


func test_unit_settings_order_can_write_the_opposite_pair_of_toggles() -> void:
	# The companion of test_unit_settings_order_writes_walk_advance_and_reform_in_place:
	# that test only exercises walk_advance ON / reform_before_move OFF, so this one covers
	# the other two branches (walk_advance OFF / reform_before_move ON).
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = true
	u.reform_before_move = false
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"walk_advance_toggle": BattleScript.UnitSettingToggle.OFF,
		"reform_toggle": BattleScript.UnitSettingToggle.ON})
	assert_false(u.walk_advance, "the OFF toggle writes walk_advance off")
	assert_true(u.reform_before_move, "the ON toggle writes reform_before_move on")


func test_unit_settings_order_skips_an_unresolvable_uid() -> void:
	# A uid that doesn't resolve to a live unit (e.g. the unit died between the order being
	# queued and drained) is skipped rather than erroring -- same contract as every other
	# per-unit order branch (stance-only, formation-only, ...).
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = false
	var b := _battle([u])
	b._apply_order_cmd({"units": [1, 999], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"walk_advance_toggle": BattleScript.UnitSettingToggle.ON})
	assert_true(u.walk_advance, "the resolvable unit in the same order still gets written")


func test_unit_settings_order_writes_file_major_reform_in_place() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.file_major_reform = false
	u.move_target = Vector2(200, 0)
	u.has_move_target = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"file_major_reform_toggle": BattleScript.UnitSettingToggle.ON})
	assert_true(u.file_major_reform, "the ON toggle writes file_major_reform")
	assert_true(u.has_move_target, "movement state is untouched")
	assert_eq(u.move_target, Vector2(200, 0), "the march continues to the same point")


func test_unit_settings_order_writes_file_major_reform_off() -> void:
	# The companion of the ON case above: covers the OFF branch of the same toggle.
	var u := _unit(1, Vector2.ZERO)
	u.file_major_reform = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"file_major_reform_toggle": BattleScript.UnitSettingToggle.OFF})
	assert_false(u.file_major_reform, "the OFF toggle writes file_major_reform off")


func test_unit_settings_order_leave_toggle_keeps_file_major_reform_as_it_was() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.file_major_reform = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY,
		"file_major_reform_toggle": BattleScript.UnitSettingToggle.LEAVE})
	assert_true(u.file_major_reform, "LEAVE keeps file_major_reform as it was")
	# An omitted key defaults to LEAVE the same way walk_advance_toggle/reform_toggle do.
	var u2 := _unit(2, Vector2.ZERO)
	u2.file_major_reform = false
	var b2 := _battle([u2])
	b2._apply_order_cmd({"units": [2], "x": 0.0, "y": 0.0,
		"target": BattleScript.ORDER_UNIT_SETTINGS_ONLY})
	assert_false(u2.file_major_reform, "an omitted file_major_reform_toggle key also defaults to LEAVE")


func test_enqueue_unit_settings_records_and_applies_once() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = false
	var b := _battle([u])
	b.enqueue_unit_settings([1], BattleScript.UnitSettingToggle.ON)
	assert_true(u.walk_advance, "applied live")
	var cmd: Dictionary = b._pending_orders[-1]
	assert_eq(int(cmd["target"]), BattleScript.ORDER_UNIT_SETTINGS_ONLY, "queued for recording")
	assert_true(bool(cmd.get("applied_live", false)),
		"and tagged so the tick drain records without a second apply")


func test_enqueue_unit_settings_with_both_toggles_leave_is_a_no_op() -> void:
	# Nothing to write -- SelectionManager only calls this with at least one real toggle,
	# but a bare all-LEAVE call (every default) shouldn't queue an empty order.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_unit_settings([1])
	assert_true(b._pending_orders.is_empty(), "an all-LEAVE call queues no order")


func test_enqueue_unit_settings_writes_file_major_reform_toggle() -> void:
	# The third toggle (file_major_reform), on its own -- proving a call that only sets
	# THIS toggle (walk_advance_toggle/reform_toggle left at their LEAVE defaults) is not
	# swallowed by the all-LEAVE no-op check above.
	var u := _unit(1, Vector2.ZERO)
	u.file_major_reform = true
	var b := _battle([u])
	b.enqueue_unit_settings([1], BattleScript.UnitSettingToggle.LEAVE,
			BattleScript.UnitSettingToggle.LEAVE, BattleScript.UnitSettingToggle.OFF)
	assert_false(u.file_major_reform, "applied live")
	var cmd: Dictionary = b._pending_orders[-1]
	assert_eq(int(cmd["target"]), BattleScript.ORDER_UNIT_SETTINGS_ONLY, "queued for recording")
	assert_eq(int(cmd["file_major_reform_toggle"]), BattleScript.UnitSettingToggle.OFF,
		"the toggle itself rides the queued command")


func test_enqueue_unit_settings_is_disabled_during_playback() -> void:
	# Live-play-only, like every other order-issuing enqueue_* function: a replay's
	# recorded commands drive playback, so a synthesized toggle during Watch Replay must
	# not queue a second, unrecorded command.
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = false
	var b := _battle([u])
	var prev_mode: int = Replay.mode
	Replay.mode = Replay.Mode.PLAYBACK
	b.enqueue_unit_settings([1], BattleScript.UnitSettingToggle.ON)
	Replay.mode = prev_mode
	assert_false(u.walk_advance, "no write during playback")
	assert_true(b._pending_orders.is_empty(), "no command queued during playback")


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


func test_focused_relief_swaps_only_the_first_and_piles_the_rest_onto_its_fight() -> void:
	# Regression guard for the pre-existing FOCUSED behaviour (the default, and every
	# relief order recorded before distributed relief existed): with several fresh
	# units ordered onto the SAME tired friendly and no group_attack override (so it
	# defaults to FOCUSED), only the first swaps with the tired unit; every other
	# ordered unit just attacks the same foe the primary took over, rather than each
	# getting its own tired partner.
	var fresh1 := _unit(1, Vector2.ZERO)
	fresh1.team = 0
	var fresh2 := _unit(3, Vector2(10, 0))
	fresh2.team = 0
	var tired := _unit(2, Vector2(100, 0))
	tired.team = 0
	tired.state = UnitScript.State.FIGHTING
	var foe := _unit(4, Vector2(150, 0))
	foe.team = 1
	tired.target_enemy = foe
	var b := _battle([fresh1, fresh2, tired, foe])
	b._apply_order_cmd({"units": [1, 3], "x": 0.0, "y": 0.0, "target": 2})
	assert_eq(fresh1.current_order.type, Order.Type.RELIEF,
			"the primary reliever gets the RELIEF order")
	assert_eq(fresh1.current_order.friendly_target, tired,
			"and its swap link points at the tired unit")
	assert_eq(fresh1.target_enemy, foe, "and takes over the tired unit's foe")
	assert_eq(fresh2.current_order.type, Order.Type.ATTACK,
			"the second reliever is a plain attacker, not a second swap")
	assert_eq(fresh2.target_enemy, foe, "piling onto the same fight the primary took over")
	assert_eq(tired.current_order.type, Order.Type.MOVE,
			"the tired unit gets exactly one retreat order")


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


# --- reform-before-move / walk_advance: read from the unit, not the cmd --------
# Both are persistent per-unit fields now, not global settings baked into each order's cmd
# dict -- _apply_order_cmd reads Unit.reform_before_move/Unit.walk_advance directly, and a
# stale "reform"/"walk_advance" key left on a cmd dict (an old replay, a hand-built test
# cmd) is simply ignored.

func test_reform_before_move_true_starts_reform_timer_not_move_target() -> void:
	# u.reform_before_move = true → destination stored on the REFORM leaf's target_pos,
	# timer started, has_move_target stays false. Straight ahead of the unit's default
	# (DOWN) facing -- a large lateral destination is a lateral pivot, which this test
	# isn't about (that maneuver forces reform off, since it never reforms -- see
	# test_lateral_pivot_maneuver.gd).
	var u := _unit(1, Vector2.ZERO)
	u.reform_before_move = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 50.0, "target": -1})
	assert_false(u.has_move_target,
		"reform_before_move doesn't set has_move_target until the timer expires")
	assert_gt(u.active_leaf().reform_timer, 0.0, "the reform timer starts counting")
	assert_eq(u.active_leaf().target_pos, Vector2(0, 50), "the destination is stored for later commit")


func test_reform_before_move_false_sets_move_target_directly() -> void:
	# u.reform_before_move = false (the _unit() helper's own default) → has_move_target
	# set immediately. Straight ahead of the unit's default (DOWN) facing, so it isn't a
	# lateral pivot (that maneuver forces reform off unconditionally, which this test
	# isn't about).
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 50.0, "target": -1})
	assert_true(u.has_move_target, "reform_before_move:false sets has_move_target immediately")
	assert_eq(u.move_target, Vector2(0, 50))
	assert_false(u._reform_holding(), "no reform hold is started")


func test_move_order_ignores_a_stale_reform_key_on_the_cmd_dict() -> void:
	# A "reform" key on the cmd dict (an old replay recorded before this migration, or a
	# hand-built test cmd) no longer has any effect -- only the unit's OWN reform_before_move field
	# governs. Set the field to false and pass a cmd carrying "reform": true: the order
	# still commits immediately, proving the cmd key is dead.
	var u := _unit(1, Vector2.ZERO)
	u.reform_before_move = false
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 50.0, "target": -1, "reform": true})
	assert_true(u.has_move_target,
		"a stale cmd-level 'reform' key is ignored -- the unit's own field (false) governs")
	assert_false(u._reform_holding())


func test_move_order_ignores_a_stale_walk_advance_key_on_the_cmd_dict() -> void:
	# Same regression as above, for walk_advance: Battle._apply_order_cmd used to overwrite
	# u.walk_advance from cmd.get("walk_advance", false) on every fresh order. Now it's read
	# straight off the unit and never re-injected -- a stale "walk_advance" cmd key changes
	# nothing.
	var u := _unit(1, Vector2.ZERO)
	u.walk_advance = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 50.0, "target": -1, "walk_advance": false})
	assert_true(u.walk_advance,
		"a stale cmd-level 'walk_advance' key is ignored -- the unit's own field (true) survives")
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 100.0, "target": -1, "walk_advance": true})
	assert_true(u.walk_advance, "and a second order with the opposite stale key still doesn't touch it")


func test_fresh_order_cancels_in_progress_reform() -> void:
	# A second plain order clears the pending reform from the first. Each order reads
	# u.reform_before_move at ITS OWN apply time, so toggling the field between the two
	# orders simulates a mid-battle player toggle.
	var u := _unit(1, Vector2.ZERO)
	u.reform_before_move = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 50.0, "target": -1})
	assert_gt(u.active_leaf().reform_timer, 0.0, "first reform order starts the timer")
	u.reform_before_move = false
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 200.0, "target": -1})
	assert_false(u._reform_holding(), "a fresh order cancels the pending reform")
	assert_true(u.has_move_target, "and the new destination is committed immediately")
	assert_eq(u.move_target, Vector2(0, 200))


func test_current_speed_survives_the_reform_hold_while_cruising() -> void:
	# Companion to the order-response-freeze regression in test_unit.gd: a unit that's
	# already cruising and gets re-ordered with reform_before_move on is frozen twice in
	# a row -- first by order_response_delay, then (once that expires) by the
	# reform-before-move hold itself (a REFORM leaf's own reform_timer). _move_to() doesn't
	# run during either freeze, so Unit._physics_process's end-of-frame idle-clear must not
	# mistake the reform hold for genuine idleness and zero the speed once the
	# order-response timer alone has drained.
	var u := _unit(1, Vector2.ZERO)
	u.reform_before_move = true
	u._current_speed = u.walk_speed   # as if it was already cruising...
	u._approach_velocity = Vector2(0, u.walk_speed)   # ...toward +y, the same way the
	# re-order continues (a genuinely cruising unit always carries both; the hold's
	# momentum exemption is directional -- see Unit.REORDER_MOMENTUM_DOT_MIN).
	var b := _battle([u])
	# Straight ahead of the unit's default (DOWN) facing, so it isn't a lateral pivot
	# (that maneuver forces reform off unconditionally, which this test isn't about).
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 500.0, "target": -1})
	assert_gt(u.active_leaf().reform_timer, 0.0, "the reform order starts the reform-hold timer")
	# Drain only the order-response timer (not the longer reform hold) so the unit is
	# still frozen by the reform hold alone on the final tick.
	while u._order_response_timer > 0.0:
		u._physics_process(0.016)
	assert_true(u._reform_holding(), "the reform hold is still running (0.8s > 0.5s response delay)")
	assert_almost_eq(u._current_speed, u.walk_speed, 0.001,
		"speed survives the reform hold too, not just the order-response freeze")


func test_enqueue_order_no_longer_embeds_a_reform_or_walk_advance_key() -> void:
	# enqueue_order used to stamp the live Settings.reform_before_move/Settings.walk_advance
	# into the command; both are per-unit fields now, so the recorded cmd carries
	# neither key at all -- Battle._apply_order_cmd reads the unit's own fields instead.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_order([1], Vector2(50, 0), -1)
	assert_false(b._pending_orders[-1].has("reform"),
		"the recorded command no longer carries a 'reform' key")
	assert_false(b._pending_orders[-1].has("walk_advance"),
		"the recorded command no longer carries a 'walk_advance' key")


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


func test_enqueue_frontage_anchored_holds_the_named_flank() -> void:
	# A RIGHT-anchored widen holds the +X edge (standing offset + half-width) fixed,
	# landing the whole width change on the left flank -- the drag-resize gesture's
	# far-flank anchoring, riding the same recorded command as the centred resize.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 60
	var start: int = UnitFormation.frontage(u)
	var spacing: float = UnitScript.FORMATION_SPACING * u.spacing_scale
	var right_edge: float = u.frontage_anchor_offset + float(start - 1) * 0.5 * spacing
	var b := _battle([u])
	b.enqueue_frontage([1], 2, UnitFormation.Anchor.RIGHT)
	assert_eq(UnitFormation.frontage(u), start + 2, "the anchored widen still resizes")
	assert_almost_eq(u.frontage_anchor_offset + float(start + 1) * 0.5 * spacing,
			right_edge, 0.001, "the anchored right edge stays put")
	assert_almost_eq(float(b._pending_orders[-1]["anchor_offset"]), u.frontage_anchor_offset,
			0.001, "the absolute composed offset rides the recorded command")


func test_enqueue_frontage_anchored_composes_with_a_standing_offset() -> void:
	# Repeated anchored resizes ADD each step's shift to the standing offset --
	# anchor_shift computes one step from a centred block, so treating it as absolute
	# would let the held flank drift (the enqueue_file_double contract, shared here).
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 60
	var b := _battle([u])
	b.enqueue_frontage([1], 2, UnitFormation.Anchor.LEFT)
	var off_one: float = u.frontage_anchor_offset
	assert_ne(off_one, 0.0, "an anchored widen carries a shift")
	b.enqueue_frontage([1], 2, UnitFormation.Anchor.LEFT)
	var spacing: float = UnitScript.FORMATION_SPACING * u.spacing_scale
	assert_almost_eq(u.frontage_anchor_offset, off_one + spacing, 0.001,
			"the second step adds its own shift on top of the first")


func test_enqueue_frontage_centre_recentres_the_block() -> void:
	# The default (keyboard) resize is centre-anchored and RE-CENTRES the block,
	# discarding any standing anchor shift -- the pre-existing contract, now pinned.
	var u := _unit(1, Vector2.ZERO)
	u.max_soldiers = 60
	u.set_frontage(UnitFormation.frontage(u), 13.5)
	var b := _battle([u])
	b.enqueue_frontage([1], 1)
	assert_eq(u.frontage_anchor_offset, 0.0,
			"a centre-anchored resize clears the standing shift")


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
	# A form-up reforms before stepping off by default (the field's own default), unlike
	# this file's other tests -- the _unit() helper's own false default is a test-suite
	# convenience, not the game's real default.
	u.reform_before_move = true
	var b := _battle([u])
	b.enqueue_form_up([1], Vector2(500, 500), 0.0, 20)   # face 0 = facing right
	assert_eq(u.active_leaf().target_pos, Vector2(500, 500),
		"the form-up target is queued pending the reform hold")
	assert_false(u.has_move_target, "unit waits in reform hold before stepping off")
	assert_almost_eq(u.deploy_facing.angle(), 0.0, 0.001, "the deploy facing is parked from the order")
	assert_eq(UnitFormation.frontage(u), 20, "the dragged width becomes the frontage")
	assert_true(b._pending_orders[-1].has("face"), "the order records its deploy facing")


func test_enqueue_form_up_with_a_group_id_ties_two_units_orders_to_one_parent() -> void:
	# docs/atomic-order-decomposition-design.md: two units deployed under the same
	# form_up_group id (SelectionManager._issue_form_up's own monotonic counter) both end
	# up as children of the SAME shared Order.Type.FORM_UP tag, built once and reused --
	# not two independent groups, and not installed as either unit's own current_order.
	var u1 := _unit(1, Vector2(0, 100))
	var u2 := _unit(2, Vector2(0, 200))
	var b := _battle([u1, u2])
	b.enqueue_form_up([1], Vector2(500, 500), 0.0, 20, 0, false, 7)
	b.enqueue_form_up([2], Vector2(500, 600), 0.0, 20, 0, false, 7)
	assert_not_null(u1.current_order.parent)
	assert_eq(u1.current_order.parent, u2.current_order.parent, "same group id -> same shared parent")
	assert_eq(u1.current_order.parent.type, Order.Type.FORM_UP)
	assert_eq(u1.current_order.parent.children, [u1.current_order, u2.current_order])
	assert_null(u1.current_order.parent.parent, "the group tag is never installed as a current_order")


func test_enqueue_form_up_without_a_group_id_leaves_the_order_ungrouped() -> void:
	var u := _unit(1, Vector2(0, 100))
	var b := _battle([u])
	b.enqueue_form_up([1], Vector2(500, 500), 0.0, 20)   # form_up_group defaults to -1
	assert_null(u.current_order.parent, "no group id -> no group parent, exactly as before")


func test_enqueue_form_up_different_group_ids_get_distinct_parents() -> void:
	var u1 := _unit(1, Vector2(0, 100))
	var u2 := _unit(2, Vector2(0, 200))
	var b := _battle([u1, u2])
	b.enqueue_form_up([1], Vector2(500, 500), 0.0, 20, 0, false, 3)
	b.enqueue_form_up([2], Vector2(500, 600), 0.0, 20, 0, false, 4)
	assert_ne(u1.current_order.parent, u2.current_order.parent,
			"two separate drag-line commands never share a group tag")


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
	u.reform_before_move = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 100.0, "y": 0.0, "target": -1})
	assert_eq(u.facing, Vector2.DOWN,
		"the unit pivots in place during the reform hold (in _think), not at order time")


# --- Side-step maneuver (the small-lateral-shift classification) --------------

func test_small_lateral_move_holds_facing_as_a_sidestep() -> void:
	# A unit facing +x ordered a short shift along +/-y should side-step: it keeps
	# its facing and the move branch records the held heading in ordered_facing.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 20.0, "target": -1})
	assert_eq(u.ordered_facing, Vector2.RIGHT, "a small lateral move holds the current facing")
	assert_true(u.has_move_target, "and still marches toward the destination")


func test_forward_move_does_not_set_a_sidestep_facing() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})
	assert_eq(u.ordered_facing, Vector2.ZERO,
		"marching straight ahead turns to face travel (no held facing)")


func test_a_fresh_order_clears_a_prior_sidestep_hold() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 20.0, "target": -1})   # side-step
	assert_eq(u.ordered_facing, Vector2.RIGHT, "side-step holds facing")
	b._apply_order_cmd({"units": [1], "x": 500.0, "y": 0.0, "target": -1})  # long forward march
	assert_eq(u.ordered_facing, Vector2.ZERO, "the next non-lateral order drops the hold")


func test_form_up_order_holds_its_deploy_facing_not_the_units_current_one() -> void:
	# A form-up commands its own deploy facing -- distinct from a side-step (which holds the
	# unit's CURRENT facing). It still sets ordered_facing (so _move_to's "maneuvering" branch
	# holds a fixed facing for the whole march instead of centre-pivoting toward travel
	# direction -- the block would otherwise reorient toward wherever it's walking, then snap
	# back to the commanded facing on arrival). The distinguishing signal is deploy_facing
	# itself: ordered_facing equals it, not the unit's own (unrelated) current facing.
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b.enqueue_form_up([1], Vector2(0, 20), 1.0, 20)   # short lateral form-up
	assert_ne(u.deploy_facing, Vector2.ZERO, "form-up parks its commanded facing")
	assert_eq(u.ordered_facing, u.deploy_facing,
			"...and holds THAT facing for the march, not the unit's pre-order facing")
	assert_ne(u.ordered_facing, Vector2.RIGHT, "the held facing is the deploy facing, not a side-step's own current facing")


# --- per-type backward-walk speed ----------------------------------------

func test_default_loadout_carries_a_back_fraction_per_type() -> void:
	# Every entry in the default loadout states its own backward-walk fraction,
	# not one shared value -- the whole point of the per-type stat.
	var b := BattleScript.new()
	autofree(b)
	var loadout: Array = b._default_loadout()
	assert_eq(loadout.size(), 5, "sanity: line composition is spearmen/infantry/archers/cav/cav")
	for d in loadout:
		assert_true(d.has("back_fraction"),
			"%s's loadout entry states its own back_fraction" % d["name"])


func test_units_spawn_with_their_type_back_speed_fraction() -> void:
	# A live-spawned unit's back_speed_fraction comes from its type's loadout entry,
	# mirroring how walk_speed/jog_speed are already set at spawn (Battle._spawn_unit).
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame   # one tick to let _spawn_line run

	var loadout: Array = battle._default_loadout()
	var expected_by_name: Dictionary = {}
	for d in loadout:
		expected_by_name[d["name"]] = d["back_fraction"]

	var seen_by_name: Dictionary = {}
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null or unit.team != 0:
			continue
		var type_name: String = unit.unit_name.split(" ")[0]
		if not seen_by_name.has(type_name):
			seen_by_name[type_name] = unit.back_speed_fraction

	for type_name in expected_by_name:
		assert_almost_eq(seen_by_name.get(type_name, -1.0), expected_by_name[type_name], 0.0001,
			"%s spawns with its own loadout back_fraction" % type_name)
	assert_lt(seen_by_name["Spearmen"], seen_by_name["Archers"],
		"heavier kit (Spearmen) backs up proportionally slower than lighter kit (Archers)")


func test_bare_unit_without_loadout_keeps_default_back_speed_fraction() -> void:
	# A hand-rolled Unit (no loadout dict at all, as in most other GUT tests) must keep
	# Unit.gd's own back_speed_fraction default -- Battle._spawn_unit only overrides it
	# when the loadout dict actually carries a "back_fraction" key.
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	assert_almost_eq(u.back_speed_fraction, 0.5, 0.0001,
		"a bare unit with no loadout falls back to the Unit.gd default")


# --- per-type walk_advance / reform_before_move spawn defaults ---------

func test_units_spawn_with_their_type_walk_advance_and_reform_before_move_defaults() -> void:
	# A live-spawned unit's walk_advance/reform_before_move come from its type's loadout
	# entry (walk_advance_default/reform_before_move_default), mirroring how
	# back_speed_fraction is already set at spawn. Spearmen default walk_advance ON
	# (holding the phalanx presentation matters more than closing speed); Cavalry defaults
	# reform_before_move OFF (immediate responsiveness beats settling ranks); every other
	# type/field combination keeps the old global settings' own defaults (false / true).
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame   # one tick to let _spawn_line run

	var seen_walk_advance: Dictionary = {}
	var seen_reform: Dictionary = {}
	var seen_file_major: Dictionary = {}
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit == null or unit.team != 0:
			continue
		var type_name: String = unit.unit_name.split(" ")[0]
		if not seen_walk_advance.has(type_name):
			seen_walk_advance[type_name] = unit.walk_advance
			seen_reform[type_name] = unit.reform_before_move
			seen_file_major[type_name] = unit.file_major_reform

	assert_true(seen_walk_advance.get("Spearmen", false),
		"Spearmen spawn with walk_advance on (holding the phalanx presentation)")
	assert_false(seen_walk_advance.get("Infantry", true),
		"Infantry keeps the old global default (walk_advance off)")
	assert_false(seen_walk_advance.get("Archers", true),
		"Archers keeps the old global default (walk_advance off)")
	assert_false(seen_walk_advance.get("Cavalry", true),
		"Cavalry keeps the old global default (walk_advance off)")

	assert_false(seen_reform.get("Cavalry", true),
		"Cavalry spawns with reform_before_move off (immediate responsiveness over settling ranks)")
	assert_true(seen_reform.get("Spearmen", false),
		"Spearmen keeps the old global default (reform_before_move on)")
	assert_true(seen_reform.get("Infantry", false),
		"Infantry keeps the old global default (reform_before_move on)")
	assert_true(seen_reform.get("Archers", false),
		"Archers keeps the old global default (reform_before_move on)")

	# file_major_reform has no per-type override today -- every type spawns with it on.
	assert_true(seen_file_major.get("Spearmen", false), "Spearmen default file_major_reform on")
	assert_true(seen_file_major.get("Infantry", false), "Infantry default file_major_reform on")
	assert_true(seen_file_major.get("Archers", false), "Archers default file_major_reform on")
	assert_true(seen_file_major.get("Cavalry", false), "Cavalry default file_major_reform on")


func test_bare_unit_without_loadout_keeps_default_walk_advance_and_reform_before_move() -> void:
	# A hand-rolled Unit (no loadout dict at all) keeps Unit.gd's own field defaults --
	# Battle._spawn_unit only overrides them when the loadout dict carries the
	# "walk_advance_default"/"reform_before_move_default" keys.
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	assert_false(u.walk_advance, "a bare unit with no loadout falls back to the Unit.gd default")
	assert_true(u.reform_before_move, "a bare unit with no loadout falls back to the Unit.gd default")
