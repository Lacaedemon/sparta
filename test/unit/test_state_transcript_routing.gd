extends GutTest
## A ROUTING unit must stay visible in the state-transcript snapshot. Unit._rout() moves a
## breaking unit from the "units" group to "routers", so a dumper that walks "units" alone
## drops its record for the whole rout — hiding exactly the arc (state ROUTING, morale
## recovering, position fleeing) the transcript exists to expose. The snapshot builder walks
## the DemoState.COMBAT_GROUPS union instead, so these tests pin: a router appears in every
## snapshot with state ROUTING, its morale recovery is observable tick by tick, and records
## stay uid-ordered across the group swap.


## The recorder with its env/script bootstrap stubbed out. The real _ready() reads
## SPARTA_DEMO_INPUT and spawns its own default battle (deferred), which would fight the
## battle this test stages. The snapshot path under test (_build_snapshot/_unit_record) only
## needs the node in the tree and _battle wired, so the override skips the bootstrap.
class QuietRecorder:
	extends "res://tools/demo/DemoInputRecorder.gd"

	func _ready() -> void:
		pass


var _battle: Node = null
var _recorder: Node = null


func after_each() -> void:
	# Free THIS test's nodes before the next test spawns, so units don't linger in the shared
	# "units"/"routers" groups and pollute a later test's group scan. Awaiting a frame lets
	# queue_free() settle; unpausing guards against an end-screen pause leaking between tests.
	get_tree().paused = false
	if is_instance_valid(_recorder):
		_recorder.free()
	_recorder = null
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _spawn_battle_with_recorder() -> void:
	# Seed so Battle._ready's Replay.start_recording draws from a pinned RNG stream rather
	# than whatever state earlier tests left; the units here never reach melee inside the
	# test window, but seeding keeps every run identical regardless.
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	# One unit per side, far apart: the router flees away from an enemy that can't close the
	# gap within the sampled window, so no combat perturbs the morale-recovery curve.
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 500, "y": 200},
		{"team": 1, "type": "Infantry", "x": 500, "y": 1400},
	]
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


func _snapshot() -> Dictionary:
	return _recorder._build_snapshot(_battle.current_tick())


## The record for `uid` in a snapshot, or an empty Dictionary when the uid is absent.
func _record_for(snapshot: Dictionary, uid: int) -> Dictionary:
	for rec in snapshot["units"]:
		if rec["uid"] == uid:
			return rec
	return {}


## Await physics frames until the battle's own tick counter advances by `n`. Under coverage
## instrumentation an awaited physics_frame doesn't map one-to-one onto a sim tick, so count
## sim progress by current_tick(), with a generous frame cap so a stall can't hang the suite.
func _advance_ticks(n: int) -> void:
	var target: int = _battle.current_tick() + n
	var safety: int = n * 20 + 200
	while _battle.current_tick() < target and safety > 0:
		safety -= 1
		await get_tree().physics_frame


func test_routing_unit_stays_in_the_snapshot() -> void:
	_spawn_battle_with_recorder()
	await get_tree().physics_frame            # _ready spawns the scenario units

	var mine: Unit = _team_unit(0)
	assert_not_null(mine, "the lone team-0 unit deployed")
	if mine == null:
		return
	var uid: int = mine.uid

	var before: Dictionary = _snapshot()
	assert_eq((before["units"] as Array).size(), 2, "both units appear pre-rout")
	assert_false(_record_for(before, uid).is_empty(), "the team-0 unit has a record pre-rout")

	# Break the unit the way the sim does: morale exhausted, then the rout group swap.
	mine.morale = 0.0
	mine._rout()
	assert_true(mine.is_in_group("routers"), "the broken unit moved to the routers group")
	await get_tree().physics_frame

	var during: Dictionary = _snapshot()
	assert_eq((during["units"] as Array).size(), 2,
		"the routing unit still appears in the snapshot -- a 'units'-only walk dropped it")
	var rec: Dictionary = _record_for(during, uid)
	assert_false(rec.is_empty(), "the router's record is present, keyed by its stable uid")
	if rec.is_empty():
		return
	assert_eq(rec["state"], "ROUTING", "its state reads ROUTING")
	assert_true(rec.has("morale"), "its morale is dumped like any fightable unit's")
	assert_true(rec.has("position"), "and so is its position")


func test_snapshot_records_stay_uid_ordered_across_the_group_swap() -> void:
	_spawn_battle_with_recorder()
	await get_tree().physics_frame

	var mine: Unit = _team_unit(0)
	assert_not_null(mine, "the lone team-0 unit deployed")
	if mine == null:
		return

	# Routing walks the unit in the "routers" group AFTER every fightable unit, so raw group
	# order would move its record to the end; the uid sort keeps rows aligned tick to tick.
	mine.morale = 0.0
	mine._rout()
	await get_tree().physics_frame

	var uids: Array = []
	for rec in _snapshot()["units"]:
		uids.append(rec["uid"])
	var expected: Array = uids.duplicate()
	expected.sort()
	assert_eq(uids, expected, "records are uid-ascending even with a unit mid-rout")


func test_router_morale_recovery_is_observable_across_ticks() -> void:
	_spawn_battle_with_recorder()
	await get_tree().physics_frame

	var mine: Unit = _team_unit(0)
	assert_not_null(mine, "the lone team-0 unit deployed")
	if mine == null:
		return
	var uid: int = mine.uid
	mine.morale = 0.0
	mine._rout()

	# Three snapshots ~10 sim ticks apart. Fleeing morale recovers toward ROUT_RALLY_BASELINE
	# at ROUT_MORALE_RECOVER_RATE of the gap per second, so each gap raises it by well over
	# the 0.1 the dump's one-decimal rounding resolves (~1.8 from a floor of 0). The whole
	# window (~30 ticks, half a second) sits far inside ROUT_TIME and leaves morale far below
	# RALLY_MORALE_THRESHOLD, so the unit is still ROUTING at every sample.
	var morales: Array = []
	for _i in range(3):
		await _advance_ticks(10)
		var rec: Dictionary = _record_for(_snapshot(), uid)
		assert_false(rec.is_empty(), "the router appears in every snapshot mid-rout")
		if rec.is_empty():
			return
		assert_eq(rec["state"], "ROUTING", "still routing at every sampled tick")
		morales.append(rec["morale"])
	assert_gt(morales[1], morales[0], "dumped morale rises tick over tick while fleeing")
	assert_gt(morales[2], morales[1], "and keeps rising toward the rally baseline")
