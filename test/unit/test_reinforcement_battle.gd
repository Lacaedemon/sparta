extends GutTest
## Reinforcement insertion (doubling by number), files axis, on a real in-tree Battle in
## drill mode: a reserve ordered onto a friendly host receives a REINFORCE order with the
## pass-through link armed, marches to the rendezvous behind the host, and commits -- its men
## file into the host's ranks, the host's frontage doubles, the interleave survives a slot
## query, and no two men share a slot. The guards each refuse.

const BattleScript = preload("res://scripts/Battle.gd")

## Ticks allowed for the approach and commit. The reserve starts about 110 wu short of the
## rendezvous at a walk (~26 wu/s), so ~250 ticks at 60 tps; the budget is generous because a
## held-heading march ramps up from rest and the commit waits for the heading to settle.
const COMMIT_BUDGET_TICKS: int = 900

## Ticks to watch the host's anchor after the commit: the CI transcript of the first cut
## showed the anchor 54 wu rearward within 20 ticks and still there 200 ticks later.
const ANCHOR_HOLD_CHECK_TICKS: int = 120

const HOST_POS := Vector2(600, 520)
const RESERVE_POS := Vector2(600, 340)

var _battle: Node = null


func after_each() -> void:
	get_tree().paused = false
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


## Two 40-man team-0 Infantry blocks facing down (+y): the host in front, the reserve
## behind it. No enemy -- drill_mode keeps Battle._check_victory from ending the battle.
func _spawn(reserve_type: String = "Infantry", host_count: int = 40, reserve_count: int = 40) -> Node:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": host_count, "x": HOST_POS.x, "y": HOST_POS.y},
		{"team": 0, "type": reserve_type, "count": reserve_count, "x": RESERVE_POS.x, "y": RESERVE_POS.y},
	]
	add_child(_battle)
	return _battle


func _unit_at(pos: Vector2) -> Unit:
	for node in _battle.get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.position.is_equal_approx(pos):
			return u
	return null


func _order_reinforce(reserve: Unit, host: Unit) -> void:
	_battle._apply_order_cmd({
		"units": [reserve.uid],
		"x": host.position.x, "y": host.position.y,
		"target": host.uid,
		"mode": BattleScript.OrderMode.NORMAL,
		"reinforce": BattleScript.ReinforceAxis.FILES,
	})


func test_order_arms_the_approach_and_leaves_the_host_alone() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	assert_not_null(host, "host spawned")
	assert_not_null(reserve, "reserve spawned")
	assert_eq(ReinforceGuard.refusal_reason(reserve, host), "", "a like-armed idle pair is allowed")
	reserve._order_response_timer = 1.0   # a delay still counting down from a prior order

	_order_reinforce(reserve, host)

	assert_eq(reserve.current_order.type, Order.Type.REINFORCE, "the reserve holds a REINFORCE order")
	assert_eq(reserve._order_response_timer, 0.0, "no response delay holds the approach")
	assert_eq(reserve.current_order.reinforce_axis, BattleScript.ReinforceAxis.FILES, "on the files axis")
	assert_eq(reserve.current_order.friendly_target, host, "the pass-through link names the host")
	assert_true(reserve._separation_exempt(host), "the pair is exempt from separation")
	assert_true(reserve.has_move_target, "the reserve is marching")
	var rendezvous: Vector2 = ReinforceApproach.rendezvous_point(host, reserve)
	assert_true(rendezvous.y < host.position.y, "the rendezvous lies behind a down-facing host")
	assert_eq(reserve.move_target, rendezvous, "aimed at the rendezvous")
	assert_eq(reserve.ordered_facing, host.facing, "with the host's heading held")
	assert_null(host.current_order, "the host's own order is untouched")
	assert_eq(reserve.current_maneuver(), Unit.Maneuver.REINFORCING, "reads as REINFORCING")
	var targets := TierTransition.live_reinforcement_targets(
			get_tree().get_nodes_in_group("units"))
	assert_false(TierTransition.can_demote(reserve, targets.has(reserve)),
			"the reserve keeps its close-tier bodies for the whole approach, as a reliever does")
	assert_false(TierTransition.can_demote(host, targets.has(host)),
			"the host also keeps its close-tier bodies for the approach")
	assert_true(reserve.order_summary().begins_with("Reinforcing"), "the HUD summary names the maneuver")


func test_commit_doubles_the_host_and_interleaves_the_files() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	var files_before: int = UnitFormation.frontage(host)
	var host_start: Vector2 = host.position
	_order_reinforce(reserve, host)

	var committed: bool = false
	for _tick in range(COMMIT_BUDGET_TICKS):
		await get_tree().physics_frame
		if not is_instance_valid(reserve) or reserve.state == Unit.State.DEAD:
			committed = true
			break
	assert_true(committed, "the reserve commits within the budget")
	assert_eq(host.soldiers, 80, "the host holds both regiments' men")
	assert_eq(host.max_soldiers, 80, "max_soldiers pooled as in a merge")
	assert_eq(_battle.get_tree().get_nodes_in_group("units").size(), 1, "only the host remains in play")
	assert_eq(host._sim_soldier_pos.size(), 80, "bodies carried across")
	assert_eq(host._sim_soldier_hp.size(), 80, "health pool carried across")
	assert_eq(host._sim_soldier_shield_hold_angle.size(), 80, "shield hold angles carried across")
	assert_eq(UnitFormation.frontage(host), 2 * files_before, "the frontage doubled")
	# Cohesion has recovered for at most a tick or two since the commit.
	assert_almost_eq(host.cohesion, host.reinforce_cohesion_floor, 0.01, "the strangers debuff applies")
	assert_true(host._last_reshape_widened, "the host stamped the commit as a widen")

	# The interleave survives a slot query (the re-deal trap), and every slot is unique.
	host.formation_slots(host.soldiers)
	assert_eq(host._sim_soldier_file.size(), 80, "file ids cover every man after a slot query")
	var seen: Dictionary = {}
	for i in range(80):
		var expected_parity: int = 0 if i < 40 else 1
		assert_eq(host._sim_soldier_file[i] % 2, expected_parity,
				"man %d stands on a%s file" % [i, "n even (host)" if i < 40 else "n odd (reserve)"])
		var key := Vector2i(host._sim_soldier_file[i], host._sim_soldier_rank[i])
		assert_false(seen.has(key), "slot %s is held by one man" % key)
		seen[key] = true
	assert_lt(host.position.distance_to(host_start), host.rank_pitch_wu(),
			"the files axis widens about the same centre; the host does not creep")

	# The newcomers walk in from the rendezvous behind the host, so for a while half the
	# block stands well off its slots. The anchor must not read that as drift and back the
	# whole regiment up to meet them: the front rank holds its ground through the arrival.
	for _tick in range(ANCHOR_HOLD_CHECK_TICKS):
		await get_tree().physics_frame
	assert_lt(host.position.distance_to(host_start), host.rank_pitch_wu(),
			"the anchor holds through the arrival; the front rank keeps its ground")


func test_guards_refuse_the_pair() -> void:
	_spawn("Spearmen")   # a different loadout
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	assert_ne(ReinforceGuard.refusal_reason(reserve, host), "", "differing loadouts are refused")
	_order_reinforce(reserve, host)
	assert_null(reserve.current_order, "a refused pair applies nothing: no order is installed")
	assert_false(reserve.has_move_target, "and no march starts")
	assert_ne(ReinforceGuard.refusal_reason(reserve, reserve), "", "a regiment cannot reinforce itself")


func test_guards_on_state_refuse_the_pair() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	host.state = Unit.State.ROUTING
	assert_ne(ReinforceGuard.refusal_reason(reserve, host), "", "a routing host is refused")
	host.state = Unit.State.IDLE
	reserve.state = Unit.State.FIGHTING
	assert_ne(ReinforceGuard.refusal_reason(reserve, host), "", "an engaged reserve is refused")
	reserve.state = Unit.State.IDLE
	host.set_formation(Unit.FORMATION_SQUARE)
	assert_ne(ReinforceGuard.refusal_reason(reserve, host), "", "a squared host is refused")
	host.set_formation(Unit.FORMATION_NORMAL)
	host.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	assert_ne(ReinforceGuard.refusal_reason(reserve, host), "", "a row-major host is refused")
	host.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	host.soldiers = 0
	assert_eq(ReinforceGuard.refusal_reason(reserve, host), "%s has no soldiers to contribute" % host.unit_name,
			"a zero-soldier host is refused")
	host.soldiers = host._sim_soldier_pos.size()
	reserve.soldiers = 0
	assert_eq(ReinforceGuard.refusal_reason(reserve, host), "%s has no soldiers to contribute" % reserve.unit_name,
			"a zero-soldier reserve is refused")
	reserve.soldiers = reserve._sim_soldier_pos.size()
	assert_eq(ReinforceGuard.refusal_reason(reserve, host), "", "restored, the pair is allowed again")


func test_a_host_that_leaves_the_line_halts_the_reserve() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	_order_reinforce(reserve, host)
	await get_tree().physics_frame
	# A routing host with no enemy in play rallies within the same tick, so leave the line
	# for good instead: the same `gone` reading a dead or freed host produces.
	host._remove_from_play()
	await get_tree().physics_frame
	assert_null(reserve.current_order.friendly_target if reserve.current_order != null else null,
			"the link drops once the host is gone")
	assert_false(reserve.has_move_target, "the reserve halts where it stands")
	await get_tree().physics_frame
	assert_null(reserve.current_order, "and the order retires")


func test_a_refused_order_leaves_a_marching_reserve_untouched() -> void:
	_spawn("Spearmen")   # a different loadout, so the pair is refused at the apply site
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	_battle._apply_order_cmd({
		"units": [reserve.uid], "x": 300.0, "y": RESERVE_POS.y, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL,
	})
	# A plain move starts marching only after the order-response delay.
	for _tick in range(COMMIT_BUDGET_TICKS):
		if reserve.has_move_target:
			break
		await get_tree().physics_frame
	assert_true(reserve.has_move_target, "the reserve is marching under a prior order")
	var prior: Order = reserve.current_order
	var prior_target: Vector2 = reserve.move_target
	_order_reinforce(reserve, host)
	assert_eq(reserve.current_order, prior, "a refused pair applies nothing: the prior order stands")
	assert_true(reserve.has_move_target, "and the prior march goes on")
	assert_eq(reserve.move_target, prior_target, "to its own destination")

	# The defensive re-check inside begin (for a pair that slips past Battle's guard)
	# halts the reserve outright: no link, no march, no leftover enemy to resume on.
	reserve.target_enemy = host   # any stale target from a previous order
	var slipped := Order.new_reinforce(host.uid, BattleScript.ReinforceAxis.FILES)
	reserve.set_current_order(slipped)
	UnitReinforce.begin(reserve, host, slipped)
	assert_null(slipped.friendly_target, "the slipped-through pair arms no link")
	assert_false(reserve.has_move_target, "the reserve halts where it stands")
	assert_null(reserve.target_enemy, "with no stale enemy left for targeting to resume on")
	await get_tree().physics_frame
	assert_null(reserve.current_order, "and the no-op order retires next tick")


func test_arming_the_approach_drops_a_persistent_stance_to_normal() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	reserve.order_mode = BattleScript.OrderMode.CHASE   # an auto-targeting stance
	var order := Order.new_reinforce(host.uid, BattleScript.ReinforceAxis.FILES)
	reserve.set_current_order(order)
	UnitReinforce.begin(reserve, host, order)
	assert_eq(reserve.order_mode, int(BattleScript.OrderMode.NORMAL),
			"the held-heading approach runs under NORMAL, so no stance can pull it off the rendezvous")
	assert_eq(reserve.order_mode, UnitReinforce.ORDER_MODE_NORMAL,
			"mirrored by the UnitReinforce.ORDER_MODE_NORMAL constant")
	assert_eq(order.friendly_target, host, "and the link is armed")


func test_install_file_assignment_keeps_a_held_flank_anchored() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var files: int = UnitFormation.frontage(host)
	host.formation_slots(host.soldiers)   # deal the file assignment
	var pitch: float = host.file_pitch_wu()
	host.frontage_anchor_offset = -2.0 * pitch   # a prior RIGHT-anchored widen holds the +X flank
	host.install_file_assignment(host._sim_soldier_file, host._sim_soldier_rank, files + 2)
	var expected: float = -2.0 * pitch + UnitFormation.anchor_shift(files, files + 2, pitch,
			UnitFormation.Anchor.RIGHT)
	assert_almost_eq(host.frontage_anchor_offset, expected, 0.001,
			"the standing offset gains the width delta, so the held flank stays put")
	host.frontage_anchor_offset = 0.0
	host.install_file_assignment(host._sim_soldier_file, host._sim_soldier_rank, files + 4)
	assert_almost_eq(host.frontage_anchor_offset, 0.0, 0.001, "a centred host stays centred")


func test_the_unwired_ranks_axis_and_far_or_touching_reserves_are_refused() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	var files_before: int = UnitFormation.frontage(host)
	assert_ne(ReinforceGuard.refusal_reason(reserve, host, BattleScript.ReinforceAxis.RANKS), "",
			"the ranks axis is refused rather than silently run as files")
	_battle._apply_order_cmd({
		"units": [reserve.uid], "x": host.position.x, "y": host.position.y,
		"target": host.uid, "mode": BattleScript.OrderMode.NORMAL,
		"reinforce": BattleScript.ReinforceAxis.RANKS,
	})
	assert_null(reserve.current_order, "a RANKS order applies nothing")
	assert_false(reserve.has_move_target, "and starts no march")
	assert_eq(UnitFormation.frontage(host), files_before, "the host is untouched")
	# A malformed command (an axis with no target, or a self target) is rejected before
	# the fresh-order reset, not applied as a plain move.
	_battle._apply_order_cmd({
		"units": [reserve.uid], "x": 300.0, "y": RESERVE_POS.y, "target": -1,
		"mode": BattleScript.OrderMode.NORMAL, "reinforce": BattleScript.ReinforceAxis.FILES,
	})
	assert_null(reserve.current_order, "an axis with no target applies nothing")
	assert_false(reserve.has_move_target, "and is not a move in disguise")
	# A host that is one of the command's own ordered units would be a merge for any other
	# friendly-target order; with an axis set it is malformed and applies nothing either.
	_battle._apply_order_cmd({
		"units": [reserve.uid, host.uid], "x": host.position.x, "y": host.position.y,
		"target": host.uid, "mode": BattleScript.OrderMode.NORMAL,
		"reinforce": BattleScript.ReinforceAxis.FILES,
	})
	assert_eq(_battle.get_tree().get_nodes_in_group("units").size(), 2, "nothing was merged")
	assert_eq(host.soldiers, 40, "the host is untouched")
	assert_null(reserve.current_order, "and the reserve holds no order")
	reserve._in_enemy_contact = true
	assert_ne(ReinforceGuard.refusal_reason(reserve, host), "",
			"a reserve whose bodies touch an enemy is refused even when not fighting")
	reserve._in_enemy_contact = false
	reserve.tier = FormationTier.FAR
	assert_ne(ReinforceGuard.refusal_reason(reserve, host), "",
			"a far-tier reserve has no bodies to file in with and is refused")
	reserve.tier = FormationTier.CLOSE
	assert_eq(ReinforceGuard.refusal_reason(reserve, host), "", "restored, the pair is allowed")


func test_rendezvous_geometry_reads_the_blocks_off_their_bodies_along_the_hosts_facing() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	var pitch: float = host.rank_pitch_wu()
	var ext: Vector2 = ReinforceApproach.extent_along(host, host.facing)
	assert_lt(ext.x, 0.0, "the rear edge lies behind the position")
	assert_gt(ext.y, 0.0, "the front edge lies ahead of it")
	assert_almost_eq(-ext.x, host.soldier_block_half_extents().y, pitch,
			"an unturned block's depth along its facing matches the slot frame's")
	# Turn the heading without turning the bodies: the block's lateral half-width is now
	# its depth along the new facing, which a local-frame .y read would miss.
	host.facing = Vector2(1.0, 0.0)
	var turned: Vector2 = ReinforceApproach.extent_along(host, host.facing)
	assert_almost_eq(turned.y, host.soldier_block_half_extents().x, pitch,
			"the extent follows the facing, not the slot frame")
	var rendezvous: Vector2 = ReinforceApproach.rendezvous_point(host, reserve)
	assert_almost_eq((rendezvous - host.position).normalized().x, -1.0, 0.001,
			"the rendezvous lies straight behind the host along its facing")
	assert_almost_eq((rendezvous - host.position).normalized().y, 0.0, 0.001,
			"with no lateral offset")
	# A quarter-turn in place leaves the grid folded (formation angle) while the men face
	# the new way: "behind the block" follows the grid's depth axis, not the raw heading.
	host._formation_angle = PI * 0.5
	var axis: Vector2 = ReinforceApproach.depth_axis(host)
	assert_almost_eq(axis.x, 0.0, 0.001, "the depth axis is the heading rotated by the fold")
	assert_almost_eq(axis.y, 1.0, 0.001, "(here: back to +y)")
	var folded: Vector2 = ReinforceApproach.rendezvous_point(host, reserve)
	assert_almost_eq((folded - host.position).normalized().y, -1.0, 0.001,
			"so the rendezvous lies behind the folded grid, not behind the heading")
	host._formation_angle = 0.0
	# True min and max bounds: an anchor offset beyond the bodies does not clamp to zero.
	host.position = HOST_POS - host.facing * 99.0
	var offset_rear: Vector2 = ReinforceApproach.extent_along(host, host.facing)
	assert_gt(offset_rear.x, 0.0, "an anchor behind all bodies yields a positive rear extent")
	assert_gt(offset_rear.y, offset_rear.x, "the front edge still lies beyond the rear")
	host.position = HOST_POS + host.facing * 99.0
	var offset_front: Vector2 = ReinforceApproach.extent_along(host, host.facing)
	assert_lt(offset_front.y, 0.0, "an anchor ahead of all bodies yields a negative front extent")
	assert_gt(offset_front.y, offset_front.x, "the front edge still lies beyond the rear")
	host.position = HOST_POS
	var saved_host_pos: PackedVector2Array = host._sim_soldier_pos
	host._sim_soldier_pos = PackedVector2Array()
	assert_eq(ReinforceApproach.extent_along(host, host.facing), Vector2.ZERO,
			"an empty body array yields zero extents")
	host._sim_soldier_pos = saved_host_pos


func test_commit_waits_for_the_longitudinal_gap_and_lateral_alignment() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	var pitch: float = host.rank_pitch_wu()
	_order_reinforce(reserve, host)
	await get_tree().physics_frame
	assert_eq(reserve.current_order.friendly_target, host, "the approach is under way")
	reserve.facing = host.facing
	var target: Vector2 = ReinforceApproach.rendezvous_point(host, reserve)

	_teleport(reserve, target + Vector2(3.0 * pitch, 0.0))   # right depth, three pitches wide
	assert_false(ReinforceApproach.at_rendezvous(reserve, host), "a lateral offset is not arrival")
	UnitReinforce.update(reserve)
	assert_eq(host.soldiers, 40, "and does not commit")

	_teleport(reserve, target + host.facing * 2.0 * pitch)   # two pitches into the host
	assert_false(ReinforceApproach.at_rendezvous(reserve, host), "an overshoot is not arrival")
	UnitReinforce.update(reserve)
	assert_eq(host.soldiers, 40, "and does not commit either")

	_teleport(reserve, target)
	assert_true(ReinforceApproach.at_rendezvous(reserve, host), "standing at the rendezvous is")
	UnitReinforce.update(reserve)
	assert_eq(host.soldiers, 80, "and the men file in")


## Move `u` and its bodies together, as a settled block that stands somewhere else.
func _teleport(u: Unit, to: Vector2) -> void:
	var shift: Vector2 = to - u.position
	u.position = to
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += shift


func test_a_surplus_reserve_deepens_the_host_and_the_anchor_steps_back_to_hold_the_front() -> void:
	_spawn("Infantry", 20, 40)   # twice the host's strength: the inserted files run deeper
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	var files: int = UnitFormation.frontage(host)
	var old_ranks: int = 0
	for c in UnitFormation.file_capacities(host.soldiers, files):
		old_ranks = maxi(old_ranks, c)
	var host_start: Vector2 = host.position
	_order_reinforce(reserve, host)
	var committed: bool = false
	for _tick in range(COMMIT_BUDGET_TICKS):
		await get_tree().physics_frame
		if not is_instance_valid(reserve) or reserve.state == Unit.State.DEAD:
			committed = true
			break
	assert_true(committed, "the surplus reserve commits within the budget")
	assert_eq(host.soldiers, 60, "the host holds both regiments' men")
	var new_ranks: int = 0
	for r in host._sim_soldier_rank:
		new_ranks = maxi(new_ranks, r + 1)
	assert_gt(new_ranks, old_ranks, "the interleave deepened the block (else this test proves nothing)")
	var shift: float = ReinforceLayout.rear_anchor_shift(old_ranks, new_ranks, host.rank_pitch_wu())
	var moved: float = (host.position - host_start).dot(host.facing)
	assert_almost_eq(moved, -shift, 0.5,
			"the anchor stepped back by half the added depth, so the front rank holds its ground")
	assert_almost_eq((host.position - host_start).dot(host.facing.orthogonal()), 0.0, 0.5,
			"and not sideways")


func test_a_partial_reserve_still_stamps_the_reshape() -> void:
	_spawn("Infantry", 40, 5)   # two inserted files; pooling to 45 men can widen on its own
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	var files_before: int = UnitFormation.frontage(host)
	var stamp_before: int = host._last_reshape_tick
	_order_reinforce(reserve, host)
	var committed: bool = false
	for _tick in range(COMMIT_BUDGET_TICKS):
		await get_tree().physics_frame
		if not is_instance_valid(reserve) or reserve.state == Unit.State.DEAD:
			committed = true
			break
	assert_true(committed, "the partial reserve commits within the budget")
	assert_eq(host.soldiers, 45, "the host holds both regiments' men")
	assert_gt(UnitFormation.frontage(host), files_before, "the frontage grew")
	assert_gt(host._last_reshape_tick, stamp_before,
			"and the widen was stamped against the pre-pool frontage, not skipped")
	assert_true(host._last_reshape_widened, "as a widen")


func test_a_host_that_stops_qualifying_mid_approach_halts_the_reserve() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	_order_reinforce(reserve, host)
	await get_tree().physics_frame
	assert_eq(reserve.current_order.friendly_target, host, "the approach is under way")
	host.set_formation(Unit.FORMATION_SQUARE)   # no files left to open
	await get_tree().physics_frame
	assert_null(reserve.current_order.friendly_target if reserve.current_order != null else null,
			"the live guards drop the link once the host stops qualifying")
	assert_false(reserve.has_move_target, "and the reserve halts")
	assert_eq(host.soldiers, 40, "nothing was interleaved into the square")


func test_host_with_distant_enemy_does_not_demote_and_commits() -> void:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	var enemy_pos := Vector2(HOST_POS.x + 2500.0, HOST_POS.y)
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": 40,
			"x": HOST_POS.x, "y": HOST_POS.y},
		{"team": 0, "type": "Infantry", "count": 40,
			"x": RESERVE_POS.x, "y": RESERVE_POS.y},
		{"team": 1, "type": "Infantry", "count": 40,
			"x": enemy_pos.x, "y": enemy_pos.y},
	]
	add_child(_battle)
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	assert_not_null(host, "host spawned")
	assert_not_null(reserve, "reserve spawned")

	_order_reinforce(reserve, host)
	await get_tree().physics_frame

	for _i in range(10):
		await get_tree().physics_frame
		assert_eq(host.tier, FormationTier.CLOSE,
			"host is protected from demotion during the live reinforcement approach")
		assert_eq(reserve.tier, FormationTier.CLOSE,
			"reserve is protected from demotion during the approach")

	var committed: bool = false
	for _tick in range(COMMIT_BUDGET_TICKS):
		await get_tree().physics_frame
		if not is_instance_valid(reserve) or reserve.state == Unit.State.DEAD:
			committed = true
			break
	assert_true(committed, "reinforcement commits even when enemies are beyond demote range")
	assert_eq(host.tier, FormationTier.CLOSE, "host remains in close tier during newcomer arrival")
	assert_eq(host.soldiers, 80, "host successfully doubled files with reserve")


func test_understrength_host_wide_frontage_override_bounds_files_and_preserves_interleave() -> void:
	_spawn("Infantry", 20, 1)
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	host.max_soldiers = 40
	host.frontage_override = 40
	_order_reinforce(reserve, host)
	var committed: bool = false
	for _tick in range(COMMIT_BUDGET_TICKS):
		await get_tree().physics_frame
		if not is_instance_valid(reserve) or reserve.state == Unit.State.DEAD:
			committed = true
			break
	assert_true(committed, "the single reserve soldier commits into the host")
	assert_eq(host.soldiers, 21, "host holds combined soldiers")
	assert_eq(host.max_soldiers, 41, "max_soldiers pooled to 41")
	assert_eq(UnitFormation.frontage(host), 41, "frontage clamped to post-pool capacity")
	assert_eq(host._file_assignment_files, 41, "file assignment files matches post-pool capacity")
	# Querying formation_slots must not trigger a re-deal.
	# _file_assignment_files matches frontage(host).
	host.formation_slots(host.soldiers)
	assert_eq(host._file_assignment_files, 41, "file assignment files remains 41 after slot query")
	assert_eq(host._sim_soldier_file.size(), 21, "every soldier has a file assignment")

