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
func _spawn(reserve_type: String = "Infantry") -> Node:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.drill_mode = true
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "count": 40, "x": HOST_POS.x, "y": HOST_POS.y},
		{"team": 0, "type": reserve_type, "count": 40, "x": RESERVE_POS.x, "y": RESERVE_POS.y},
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
	assert_eq(UnitReinforce.refusal_reason(reserve, host), "", "a like-armed idle pair is allowed")

	_order_reinforce(reserve, host)

	assert_eq(reserve.current_order.type, Order.Type.REINFORCE, "the reserve holds a REINFORCE order")
	assert_eq(reserve.current_order.reinforce_axis, BattleScript.ReinforceAxis.FILES, "on the files axis")
	assert_eq(reserve.current_order.friendly_target, host, "the pass-through link names the host")
	assert_true(reserve._separation_exempt(host), "the pair is exempt from separation")
	assert_true(reserve.has_move_target, "the reserve is marching")
	var rendezvous: Vector2 = UnitReinforce.rendezvous_point(host, reserve)
	assert_true(rendezvous.y < host.position.y, "the rendezvous lies behind a down-facing host")
	assert_eq(reserve.move_target, rendezvous, "aimed at the rendezvous")
	assert_eq(reserve.ordered_facing, host.facing, "with the host's heading held")
	assert_null(host.current_order, "the host's own order is untouched")
	assert_eq(reserve.current_maneuver(), Unit.Maneuver.REINFORCING, "reads as REINFORCING")
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
	assert_ne(UnitReinforce.refusal_reason(reserve, host), "", "differing loadouts are refused")
	_order_reinforce(reserve, host)
	assert_null(reserve.current_order.friendly_target, "a refused pair arms no link")
	assert_false(reserve.has_move_target, "and no march")
	await get_tree().physics_frame
	assert_null(reserve.current_order, "the no-op order retires")
	assert_ne(UnitReinforce.refusal_reason(reserve, reserve), "", "a regiment cannot reinforce itself")


func test_guards_on_state_refuse_the_pair() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	host.state = Unit.State.ROUTING
	assert_ne(UnitReinforce.refusal_reason(reserve, host), "", "a routing host is refused")
	host.state = Unit.State.IDLE
	reserve.state = Unit.State.FIGHTING
	assert_ne(UnitReinforce.refusal_reason(reserve, host), "", "an engaged reserve is refused")
	reserve.state = Unit.State.IDLE
	host.set_formation(Unit.FORMATION_SQUARE)
	assert_ne(UnitReinforce.refusal_reason(reserve, host), "", "a squared host is refused")
	host.set_formation(Unit.FORMATION_NORMAL)
	host.file_major_reform_mode = Unit.ReformMode.ROW_MAJOR
	assert_ne(UnitReinforce.refusal_reason(reserve, host), "", "a row-major host is refused")
	host.file_major_reform_mode = Unit.ReformMode.FILE_MAJOR
	assert_eq(UnitReinforce.refusal_reason(reserve, host), "", "restored, the pair is allowed again")


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


func test_a_refused_order_halts_a_marching_reserve() -> void:
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
	_order_reinforce(reserve, host)
	assert_null(reserve.current_order.friendly_target, "a refused pair arms no link")
	assert_false(reserve.has_move_target, "and drops the stale march: the reserve halts")
	await get_tree().physics_frame
	assert_null(reserve.current_order, "so the no-op order retires next tick")


func test_the_unwired_ranks_axis_and_far_or_touching_reserves_are_refused() -> void:
	_spawn()
	await get_tree().physics_frame
	var host: Unit = _unit_at(HOST_POS)
	var reserve: Unit = _unit_at(RESERVE_POS)
	var files_before: int = UnitFormation.frontage(host)
	assert_ne(UnitReinforce.refusal_reason(reserve, host, BattleScript.ReinforceAxis.RANKS), "",
			"the ranks axis is refused rather than silently run as files")
	_battle._apply_order_cmd({
		"units": [reserve.uid], "x": host.position.x, "y": host.position.y,
		"target": host.uid, "mode": BattleScript.OrderMode.NORMAL,
		"reinforce": BattleScript.ReinforceAxis.RANKS,
	})
	assert_null(reserve.current_order.friendly_target, "a RANKS order arms nothing")
	assert_false(reserve.has_move_target, "and starts no march")
	assert_eq(UnitFormation.frontage(host), files_before, "the host is untouched")
	reserve._in_enemy_contact = true
	assert_ne(UnitReinforce.refusal_reason(reserve, host), "",
			"a reserve whose bodies touch an enemy is refused even when not fighting")
	reserve._in_enemy_contact = false
	reserve.tier = FormationTier.FAR
	assert_ne(UnitReinforce.refusal_reason(reserve, host), "",
			"a far-tier reserve has no bodies to file in with and is refused")
	reserve.tier = FormationTier.CLOSE
	assert_eq(UnitReinforce.refusal_reason(reserve, host), "", "restored, the pair is allowed")


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
