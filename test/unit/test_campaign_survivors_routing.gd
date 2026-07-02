extends GutTest
## The campaign result must count a still-routing unit as a survivor. _check_victory
## keeps a team in play while its last unit routs (the unit sits in the "routers"
## group, off the "units" group), so a battle can end the instant one side is
## annihilated while the other side's last body is mid-rout. _report_campaign_result
## used to count survivors from the "units" group only, so that fugitive vanished
## from the campaign even though the victory check said the team was still in play.
## Regression guard: survivor counting unions "units" + "routers" (_team_survivors),
## mirroring _team_in_play, so the two ends of the battle agree about who exists.
##
## Stages the minimal campaign clash: one unit per side, far apart (never in contact),
## seeded like a replay; each test forces the end state directly.

const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")

var _battle: Node = null


func before_each() -> void:
	# A campaign-launched clash of one strength point per side: each spawns one unit
	# (units_for(1) == 1), so a lone survivor maps straight back to strength 1.
	CampaignBattle.clear()
	CampaignBattle.active = true
	CampaignBattle.pending = {"attacker_strength": 1, "defender_strength": 1}


func after_each() -> void:
	# Free THIS test's battle before the next test spawns, so its units don't linger in
	# the shared "units"/"routers" groups and pollute a later test's group scan. Clear
	# the pause show_end() set and the campaign holder (a process-wide static), and
	# drop any unconsumed seed so no state leaks into a later test.
	get_tree().paused = false
	CampaignBattle.clear()
	Replay.forced_seed = -1
	if is_instance_valid(_battle):
		_battle.free()
	_battle = null
	await get_tree().physics_frame


func _spawn_campaign_duel() -> Node:
	# Seed like a replay would: Battle._ready() calls Replay.start_recording(), which
	# consumes forced_seed into the RNG stream, so the staged fight is deterministic.
	Replay.forced_seed = 12345
	_battle = load("res://scenes/Battle.tscn").instantiate()
	# One unit per side, far apart, so neither engages before the test forces the end.
	_battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 500, "y": 200},
		{"team": 1, "type": "Infantry", "x": 500, "y": 1400},
	]
	add_child(_battle)
	return _battle


func _team_unit(team: int) -> Unit:
	for u in get_tree().get_nodes_in_group("units"):
		var unit: Unit = u as Unit
		if unit != null and unit.team == team:
			return unit
	return null


func test_victory_counts_the_still_routing_last_unit_as_a_survivor() -> void:
	var battle := _spawn_campaign_duel()
	await get_tree().physics_frame            # _ready spawns the scenario units

	var mine: Unit = _team_unit(0)
	var enemy: Unit = _team_unit(1)
	assert_not_null(mine, "the lone team-0 unit deployed")
	assert_not_null(enemy, "the lone team-1 unit deployed")
	if mine == null or enemy == null:
		return

	# The player's last unit breaks: it leaves the "units" group for "routers".
	mine._rout()
	assert_true(mine.is_in_group("routers"), "the last player unit is mid-rout")

	# The enemy is annihilated, ending the battle while the player's unit still routs.
	enemy._remove_from_play()
	await get_tree().physics_frame            # let queue_free() settle
	battle._check_victory()

	assert_true(battle._ended, "annihilating the enemy ends the battle")
	assert_eq(mine.state, Unit.State.ROUTING,
		"the winner's last unit is still routing when the battle ends")
	assert_true(bool(CampaignBattle.result.get("attacker_won", false)), "the attacker won")
	assert_eq(int(CampaignBattle.result.get("survivors", -1)), 1,
		"the still-routing unit counts as a campaign survivor, not a casualty")


func test_defeat_counts_the_defenders_still_routing_unit_as_a_survivor() -> void:
	var battle := _spawn_campaign_duel()
	await get_tree().physics_frame

	var mine: Unit = _team_unit(0)
	var enemy: Unit = _team_unit(1)
	assert_not_null(mine, "the lone team-0 unit deployed")
	assert_not_null(enemy, "the lone team-1 unit deployed")
	if mine == null or enemy == null:
		return

	# Mirror case: the defender's last unit is mid-rout when the attacker is wiped out,
	# so the Defeat branch must count the fugitive for the defending side.
	enemy._rout()
	assert_true(enemy.is_in_group("routers"), "the last defender unit is mid-rout")

	mine._remove_from_play()
	await get_tree().physics_frame
	battle._check_victory()

	assert_true(battle._ended, "annihilating the player ends the battle")
	assert_eq(enemy.state, Unit.State.ROUTING,
		"the defender's last unit is still routing when the battle ends")
	assert_false(bool(CampaignBattle.result.get("attacker_won", true)), "the attacker lost")
	assert_eq(int(CampaignBattle.result.get("survivors", -1)), 1,
		"the defender's still-routing unit counts as a campaign survivor")
