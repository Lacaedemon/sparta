extends GutTest
## A unit that amends or refuses a move order tells whoever gave it: exactly one
## OrderOutcomeReport per amended order, naming the requested and granted destinations and
## the reason. The player hears it as a HUD toast, an AI commander in its inbox.

const BattleScript = preload("res://scripts/Battle.gd")
const HILL := Rect2(1150, 380, 250, 200)   # Battle.TERRAIN's default hill

var _old_field: PathField = null
var _reports: Array = []


func before_each() -> void:
	_old_field = PathField.active
	var field := PathField.new(Rect2(0, 0, 4000, 4000))
	field.block_rect(HILL)
	PathField.active = field
	_reports = []


func after_each() -> void:
	PathField.active = _old_field
	Replay.forced_seed = -1


func _on_report(report: OrderOutcomeReport) -> void:
	_reports.append(report)


## A 3-file x 20-rank Infantry block facing north at `pos`, listening for its reports.
func _make_deep_block(pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 60
	add_child_autofree(u)
	u.frontage_override = 3
	u.facing = Vector2.UP
	u.position = pos
	u.order_outcome_reported.connect(_on_report)
	return u


func _nudge(u: Unit, dir: int) -> void:
	u.ordered_facing = u.facing
	u.move_target = u.position + BattleScript.nudge_offset(u.facing, dir)
	u.has_move_target = true


# --- the report itself -----------------------------------------------------------------------

func test_a_clamped_order_reports_once_with_the_terrain_reason() -> void:
	var u := _make_deep_block(Vector2(1110, 330))
	var asked: Vector2 = u.position + BattleScript.nudge_offset(u.facing, BattleScript.NudgeDir.RIGHT)
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	assert_eq(_reports.size(), 1, "exactly one report for the one amended order")
	var r: OrderOutcomeReport = _reports[0]
	assert_eq(r.unit, u, "the report names the unit")
	assert_eq(r.requested, asked, "it carries the destination that was asked for")
	assert_eq(r.granted, u.move_target, "and the destination the unit will march to instead")
	assert_ne(r.granted, r.requested, "which is short of the request")
	assert_eq(r.reason, OrderOutcomeReport.Reason.CLAMPED_TERRAIN, "pulled back off the hill")
	assert_false(r.is_hold(), "a pull-back is not a hold")


func test_a_refused_order_reports_once_as_a_hold() -> void:
	var u := _make_deep_block(Vector2(1145, 330))
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	assert_eq(_reports.size(), 1, "exactly one report for the refused order")
	var r: OrderOutcomeReport = _reports[0]
	assert_eq(r.reason, OrderOutcomeReport.Reason.REFUSED_HOLD, "nothing along the move is clear")
	assert_true(r.is_hold(), "the unit holds")
	assert_eq(r.granted, u.position, "and the granted point is where it stands")


func test_an_order_pulled_back_to_keep_on_the_field_reports_the_field_edge() -> void:
	PathField.active = PathField.new(Rect2(0, 0, 4000, 4000))   # no terrain: only the edge binds
	var u := _make_deep_block(Vector2(300, 1000))
	u.field_bounds = Rect2(0, 0, 4000, 4000)
	u.ordered_facing = u.facing
	u.move_target = Vector2(-500, 1000)
	assert_eq(_reports.size(), 1, "one report")
	assert_eq(_reports[0].reason, OrderOutcomeReport.Reason.CLAMPED_FIELD_EDGE,
		"the field edge, not terrain, bound the order")
	assert_gt(u.move_target.x, 0.0, "the unit stops on the field")


func test_an_unclamped_order_reports_nothing() -> void:
	var u := _make_deep_block(Vector2(1080, 330))
	_nudge(u, BattleScript.NudgeDir.RIGHT)
	assert_eq(u.move_target, Vector2(1110, 330), "sanity check: the order went as given")
	assert_eq(_reports.size(), 0, "no report for an order carried out as given")
	assert_null(u.last_order_report, "and nothing recorded")


func test_rewriting_the_same_request_under_the_same_order_does_not_report_again() -> void:
	var u := _make_deep_block(Vector2(1110, 330))
	u.set_current_order(Order.new_move(u.position + BattleScript.nudge_offset(u.facing,
			BattleScript.NudgeDir.RIGHT)))
	var asked: Vector2 = u.current_order.target_pos
	u.ordered_facing = u.facing
	u.move_target = asked
	u.move_target = asked   # a leg promoted after a reform writes the same request again
	u.position += Vector2(0.0, -5.0)   # re-validated from a new position
	u.move_target = asked
	assert_eq(_reports.size(), 1, "the one order is reported once however often it is re-clamped")


func test_a_new_order_to_the_same_point_reports_again() -> void:
	var u := _make_deep_block(Vector2(1110, 330))
	var asked: Vector2 = u.position + BattleScript.nudge_offset(u.facing, BattleScript.NudgeDir.RIGHT)
	u.ordered_facing = u.facing
	u.set_current_order(Order.new_move(asked))
	u.move_target = asked
	u.set_current_order(Order.new_move(asked))
	u.move_target = asked
	assert_eq(_reports.size(), 2, "a fresh order is a fresh report")


func test_a_new_request_under_the_same_order_reports_again() -> void:
	var u := _make_deep_block(Vector2(1110, 330))
	u.ordered_facing = u.facing
	u.set_current_order(Order.new_move(Vector2(1140, 330)))
	u.move_target = Vector2(1140, 330)
	u.move_target = Vector2(1160, 330)
	assert_eq(_reports.size(), 2, "a different requested point is a different amendment")


func test_report_message_names_the_unit_and_the_reason() -> void:
	var u := _make_deep_block(Vector2(1110, 330))
	u.unit_name = "Infantry 1"
	var held := OrderOutcomeReport.create(u, Vector2(1, 1), u.position, OrderOutcomeReport.Reason.REFUSED_HOLD)
	assert_eq(held.message(), "Infantry 1: no way through -- holding")
	var short := OrderOutcomeReport.create(u, Vector2(1, 1), Vector2.ZERO, OrderOutcomeReport.Reason.CLAMPED_TERRAIN)
	assert_string_contains(short.message(), "Infantry 1: halting short")
	var edge := OrderOutcomeReport.create(u, Vector2(1, 1), Vector2.ZERO, OrderOutcomeReport.Reason.CLAMPED_FIELD_EDGE)
	assert_string_contains(edge.message(), "edge of the field")


# --- who hears it ----------------------------------------------------------------------------

func _spawn_battle() -> Node:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 1000, "y": 480},
		{"team": 1, "type": "Infantry", "x": 1000, "y": 900},
	]
	add_child_autofree(battle)
	return battle


func _unit_of_team(team: int) -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as Unit
		if u != null and u.team == team:
			return u
	return null


## An order into the middle of the hill: its footprint can never fit there, so it is cut.
func _order_into_the_hill(u: Unit) -> void:
	u.ordered_facing = Vector2.RIGHT
	u.move_target = HILL.get_center()


func test_a_player_units_report_toasts_on_the_hud() -> void:
	var battle: Node = _spawn_battle()
	var u: Unit = _unit_of_team(0)
	_order_into_the_hill(u)
	assert_not_null(u.last_order_report, "sanity check: the order into the hill was amended")
	assert_true(battle._hud._flash_label.visible, "the toast shows")
	assert_eq(battle._hud._flash_label.text, u.last_order_report.message(), "and says what the unit reported")
	assert_string_contains(battle._hud._flash_label.text, u.unit_name, "naming the unit")


func test_an_ai_units_report_never_toasts() -> void:
	var battle: Node = _spawn_battle()
	var u: Unit = _unit_of_team(1)
	_order_into_the_hill(u)
	assert_not_null(u.last_order_report, "sanity check: the order into the hill was amended")
	assert_false(battle._hud._flash_label.visible, "no toast for an AI unit")


func test_a_delegated_player_units_report_goes_to_its_commander_not_the_hud() -> void:
	var battle: Node = _spawn_battle()
	var u: Unit = _unit_of_team(0)
	u.player_group_id = 3
	_order_into_the_hill(u)
	assert_false(battle._hud._flash_label.visible, "an AI subcommander's unit does not toast the player")
	assert_eq(battle.ai_report_inbox.latest(u.uid), u.last_order_report, "its commander has the report")


func test_the_issuing_ai_commanders_inbox_sees_the_report() -> void:
	var battle: Node = _spawn_battle()
	var u: Unit = _unit_of_team(1)
	assert_null(battle.ai_report_inbox.latest(u.uid), "sanity check: nothing waiting beforehand")
	_order_into_the_hill(u)
	var got: OrderOutcomeReport = battle.ai_report_inbox.latest(u.uid)
	assert_not_null(got, "the commander's handler received the report")
	assert_eq(got.unit, u, "from that unit")
	assert_eq(got.requested, HILL.get_center(), "naming what was asked")
	assert_eq(battle.ai_report_inbox.pending_count(), 1, "once")
	battle.ai_report_inbox.acknowledge(u.uid)
	assert_null(battle.ai_report_inbox.latest(u.uid), "acknowledging clears it")


func test_a_player_units_report_does_not_reach_the_ai_inbox() -> void:
	var battle: Node = _spawn_battle()
	_order_into_the_hill(_unit_of_team(0))
	assert_eq(battle.ai_report_inbox.pending_count(), 0, "the player hears their own unit, not an AI commander")


func test_all_teams_control_treats_both_armies_as_the_players() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.all_teams_control = true
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 1000, "y": 480},
		{"team": 1, "type": "Infantry", "x": 1000, "y": 900},
	]
	add_child_autofree(battle)
	var u: Unit = _unit_of_team(1)
	_order_into_the_hill(u)
	assert_true(battle._hud._flash_label.visible, "the player commands team 1 here, so it toasts")
	assert_eq(battle.ai_report_inbox.pending_count(), 0, "and no AI commander is told")


## When a footprint both overlaps terrain and leaves the field, terrain is the reason given;
## each alone names itself, and a clear footprint names neither.
func test_binding_constraint_names_terrain_first_then_the_field_edge() -> void:
	var f := PathField.new(Rect2(0, 0, 1000, 1000))
	f.block_rect(Rect2(900, 400, 100, 200))
	var field := Rect2(0, 0, 1000, 1000)
	var half := Vector2(50, 20)
	assert_eq(OrderFootprint.binding_constraint(f, Vector2(990, 500), Vector2.RIGHT, half, field),
			OrderFootprint.Constraint.TERRAIN, "on the hill and off the field: terrain")
	assert_eq(OrderFootprint.binding_constraint(f, Vector2(990, 100), Vector2.RIGHT, half, field),
			OrderFootprint.Constraint.FIELD_EDGE, "off the field only: the field edge")
	assert_eq(OrderFootprint.binding_constraint(f, Vector2(500, 500), Vector2.RIGHT, half, field),
			OrderFootprint.Constraint.NONE, "clear: neither")
