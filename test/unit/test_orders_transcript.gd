extends GutTest
## Phase 5 of the unified orders-queue design (docs/orders-queue-design.md): the transcript
## surface's verification payoff. Exercises DemoInputRecorder._unit_record /_build_snapshot
## directly (the QuietRecorder pattern from test_state_transcript_routing.gd) against a live
## Battle so the phase 1-4 fields -- current_order, order_phase, order_guard, frontage,
## queue_tail -- are checked against the SAME snapshot code CI's demo state-dump path runs,
## not a hand-rolled read of Unit fields.


## The recorder with its env/script bootstrap stubbed out -- see test_state_transcript_routing.gd
## for why: the real _ready() reads SPARTA_DEMO_INPUT and spawns its own battle, which would
## collide with the one staged here. The snapshot path under test only needs the node in the
## tree and _battle wired.
class QuietRecorder:
	extends "res://tools/demo/DemoInputRecorder.gd"

	func _ready() -> void:
		pass


var _battle: Node = null
var _recorder: Node = null


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(_recorder):
		_recorder.free()
	_recorder = null
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _spawn_battle_with_recorder(scenario: Array) -> void:
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	_battle.scenario = scenario
	add_child(_battle)
	_recorder = QuietRecorder.new()
	_recorder._battle = _battle
	add_child(_recorder)


func _team_unit(team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			return unit
	return null


func _record_for(uid: int) -> Dictionary:
	var snapshot: Dictionary = _recorder._build_snapshot(_battle.current_tick())
	for rec in snapshot["units"]:
		if rec["uid"] == uid:
			return rec
	return {}


# --- The verification payoff: conversio vs a plain march read apart ---------------------

func test_transcript_distinguishes_a_rear_move_about_face_from_a_plain_march() -> void:
	# The design doc's whole motivating example: an about-face (MOVE:TURN, mid-reversal) and
	# an ordinary forward march (MOVE, no phase) both used to read as state: MOVING with
	# nothing else to tell them apart. current_order + order_phase must resolve that from a
	# single transcript read, with no motion-inference needed.
	_spawn_battle_with_recorder([{"team": 0, "type": "Infantry", "x": 500, "y": 500}])
	await get_tree().physics_frame
	var mine: Unit = _team_unit(0)
	assert_not_null(mine)
	if mine == null:
		return

	# A plain forward march: current_order MOVE, phase NONE.
	mine.seed_sim_soldiers()
	var plain := Order.new_move(mine.position + Vector2(0, 100))
	mine.set_current_order(plain)
	mine.move_target = plain.target_pos
	mine.has_move_target = true
	var march_rec: Dictionary = _record_for(mine.uid)
	assert_eq(march_rec["current_order"], "MOVE")
	assert_eq(march_rec["order_phase"], "NONE")

	# A rear-move about-face, mid-reversal: current_order MOVE, phase TURN. Give the unit a
	# partial last rank (frontage 4 at 10 soldiers) so begin_about_face has real work to do.
	mine.frontage_override = 4
	mine.facing = Vector2.DOWN
	mine.seed_sim_soldiers()
	var rear := Order.new_move(mine.position - mine.facing * 200.0)
	mine.set_current_order(rear)
	mine.has_move_target = false
	assert_true(mine.begin_about_face(rear), "the about-face arms on a seeded idle unit")
	var turn_rec: Dictionary = _record_for(mine.uid)
	assert_eq(turn_rec["current_order"], "MOVE")
	assert_eq(turn_rec["order_phase"], "TURN")
	assert_ne(turn_rec["order_phase"], march_rec["order_phase"],
		"the two reads are distinguishable from the transcript alone")


# --- Phase 4 fields: order_guard -----------------------------------------------------------

func test_transcript_reports_null_order_guard_for_an_unguarded_order() -> void:
	_spawn_battle_with_recorder([{"team": 0, "type": "Infantry", "x": 500, "y": 500}])
	await get_tree().physics_frame
	var mine: Unit = _team_unit(0)
	if mine == null:
		return
	mine.set_current_order(Order.new_move(mine.position + Vector2(0, 100)))
	var rec: Dictionary = _record_for(mine.uid)
	assert_null(rec["order_guard"])


func test_transcript_reports_the_pending_guard_by_name() -> void:
	_spawn_battle_with_recorder([{"team": 0, "type": "Infantry", "x": 500, "y": 500}])
	await get_tree().physics_frame
	var mine: Unit = _team_unit(0)
	if mine == null:
		return
	mine.set_current_order(Order.new_move(mine.position + Vector2(0, 500)).with_guard(Order.Guard.CONTACT_MADE))
	var rec: Dictionary = _record_for(mine.uid)
	assert_eq(rec["order_guard"], "CONTACT_MADE")


# --- Phase 5 fields: frontage + queue_tail --------------------------------------------------

func test_transcript_reports_the_units_current_frontage() -> void:
	_spawn_battle_with_recorder([{"team": 0, "type": "Infantry", "x": 500, "y": 500}])
	await get_tree().physics_frame
	var mine: Unit = _team_unit(0)
	if mine == null:
		return
	mine.set_frontage(3)
	var rec: Dictionary = _record_for(mine.uid)
	assert_eq(rec["frontage"], 3)


func test_transcript_queue_tail_is_empty_with_only_a_current_order() -> void:
	_spawn_battle_with_recorder([{"team": 0, "type": "Infantry", "x": 500, "y": 500}])
	await get_tree().physics_frame
	var mine: Unit = _team_unit(0)
	if mine == null:
		return
	mine.set_current_order(Order.new_move(mine.position + Vector2(0, 100)))
	var rec: Dictionary = _record_for(mine.uid)
	assert_eq(rec["queue_tail"], [])


func test_transcript_queue_tail_lists_the_queued_orders_behind_current() -> void:
	_spawn_battle_with_recorder([{"team": 0, "type": "Infantry", "x": 500, "y": 500}])
	await get_tree().physics_frame
	var mine: Unit = _team_unit(0)
	if mine == null:
		return
	mine.set_current_order(Order.new_move(mine.position + Vector2(0, 100)))
	mine.append_order(Order.new_move(mine.position + Vector2(0, 200)))
	mine.append_order(Order.new_attack(-1))
	var rec: Dictionary = _record_for(mine.uid)
	assert_eq(rec["queue_tail"], ["MOVE", "ATTACK"])


func test_transcript_reports_null_current_order_and_empty_tail_when_idle() -> void:
	_spawn_battle_with_recorder([{"team": 0, "type": "Infantry", "x": 500, "y": 500}])
	await get_tree().physics_frame
	var mine: Unit = _team_unit(0)
	if mine == null:
		return
	var rec: Dictionary = _record_for(mine.uid)
	assert_null(rec["current_order"])
	assert_null(rec["order_phase"])
	assert_null(rec["order_guard"])
	assert_eq(rec["queue_tail"], [])
