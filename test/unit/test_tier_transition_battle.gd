extends GutTest
## Live-battle determinism across the tier boundary (docs/large-scale-simulation-design.md,
## phase 3): the same seeded battle, run twice, demotes and promotes its formations on the
## same ticks and reconstructs bit-identical soldier layouts (positions, facing, HP) after
## the promotion — the phase's done-check, asserted on exact state instead of a rendered
## clip. Two formations spawn beyond DEMOTE_RANGE of each other, so Battle's tier pass
## collapses both to the far tier on the first tick; the enemy AI then marches its unit
## in (a far-tier formation keeps moving at regiment level — no per-soldier state), and
## when the gap closes inside PROMOTE_RANGE both formations reconstruct their bodies from
## the seeded hash. Captures are anchored to the sim's own tick counter, never wall-clock.

const BATTLE_SEED := 12345
# Spawn separation: beyond DEMOTE_RANGE (with a buffer against the exact threshold), so
# both formations demote immediately; the enemy then closes the gap to PROMOTE_RANGE.
const SPAWN_X_PLAYER := 300.0
const SPAWN_X_ENEMY := 950.0
const SPAWN_Y := 500.0


func _spawn_battle() -> Node2D:
	# Seed each run identically, exactly as a replay would: Battle._ready() calls
	# Replay.start_recording(), which consumes forced_seed into the RNG stream.
	Replay.forced_seed = BATTLE_SEED
	var battle: Node2D = load("res://scenes/Battle.tscn").instantiate()
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": SPAWN_X_PLAYER, "y": SPAWN_Y, "count": 40},
		{"team": 1, "type": "Cavalry", "x": SPAWN_X_ENEMY, "y": SPAWN_Y, "count": 30},
	]
	add_child(battle)
	return battle


func _team_unit(team: int) -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.team == team:
			return u
	return null


## Tick budget for the approach, from the sim's own constants: the mover closes from the
## spawn separation down to PROMOTE_RANGE at worst at its walk pace (the slowest gait a
## chase can pick), doubled for the acceleration ramp and the enemy-AI cadence — so a
## pacing retune moves the budget with it instead of flaking the test.
func _budget_ticks(mover: Unit) -> int:
	var travel: float = (SPAWN_X_ENEMY - SPAWN_X_PLAYER) - FormationTier.PROMOTE_RANGE
	return int(ceil(travel / mover.walk_speed * Replay.PHYSICS_TPS)) * 2


## Run one seeded battle until both formations have demoted and then promoted, capturing
## the transition ticks and duplicates of the reconstructed per-soldier arrays the moment
## the promotion is observed. The observation loop holds no inner awaits, so it sees every
## physics tick; the captured tick values then pin, across runs, that the sim itself — not
## the observer — transitioned at the same points.
func _run_and_capture() -> Dictionary:
	var battle: Node2D = _spawn_battle()
	var player: Unit = _team_unit(0)
	var mover: Unit = _team_unit(1)
	assert_not_null(player, "the scenario spawns the team-0 formation")
	assert_not_null(mover, "the scenario spawns the team-1 formation")
	var caps := {"demote_tick": -1, "promote_tick": -1}
	if player == null or mover == null:
		battle.free()
		return caps
	var budget: int = _budget_ticks(mover)
	while battle.current_tick() < budget:
		await get_tree().physics_frame
		var tick: int = battle.current_tick()
		if caps["demote_tick"] < 0 \
				and player.tier == FormationTier.FAR and mover.tier == FormationTier.FAR:
			caps["demote_tick"] = tick
			# A far-tier formation carries no per-soldier state at all.
			caps["far_player_bodies"] = player._sim_soldier_pos.size()
			caps["far_mover_bodies"] = mover._sim_soldier_pos.size()
			caps["far_player_unit_pos"] = player.position
		if caps["demote_tick"] >= 0 \
				and player.tier == FormationTier.CLOSE and mover.tier == FormationTier.CLOSE:
			caps["promote_tick"] = tick
			# duplicate() forces a real copy — the live packed arrays keep evolving.
			caps["player_pos"] = player._sim_soldier_pos.duplicate()
			caps["player_hp"] = player._sim_soldier_hp.duplicate()
			caps["player_facing"] = player._sim_soldier_facing.duplicate()
			caps["mover_pos"] = mover._sim_soldier_pos.duplicate()
			caps["mover_hp"] = mover._sim_soldier_hp.duplicate()
			caps["mover_facing"] = mover._sim_soldier_facing.duplicate()
			caps["player_unit_pos"] = player.position
			caps["mover_unit_pos"] = mover.position
			caps["player_morale"] = player.morale
			caps["player_soldiers"] = player.soldiers
			caps["mover_soldiers"] = mover.soldiers
			break
	battle.free()
	return caps


func test_two_runs_from_the_same_seed_transition_and_reconstruct_identically() -> void:
	var first: Dictionary = await _run_and_capture()
	var second: Dictionary = await _run_and_capture()

	# The arc itself: both formations demote (they spawn beyond DEMOTE_RANGE), carry no
	# per-soldier state while far, and promote when the approach crosses PROMOTE_RANGE.
	assert_true(int(first["demote_tick"]) >= 0, "both formations demote within the budget")
	assert_true(int(first["promote_tick"]) > int(first["demote_tick"]),
		"the approach crosses the promotion boundary within the budget (demote tick %d, promote tick %d)"
			% [int(first["demote_tick"]), int(first["promote_tick"])])
	if int(first["promote_tick"]) < 0 or int(second["promote_tick"]) < 0:
		return
	assert_eq(int(first["far_player_bodies"]), 0, "a far-tier formation carries no soldier bodies")
	assert_eq(int(first["far_mover_bodies"]), 0, "on either side")

	# Determinism across runs: same transition ticks, same aggregates, and bit-identical
	# reconstructed soldier layouts (position, facing, HP) — the state-transcript bar.
	assert_eq(first["demote_tick"], second["demote_tick"], "both runs demote on the same tick")
	assert_eq(first["promote_tick"], second["promote_tick"], "both runs promote on the same tick")
	assert_eq(first["player_soldiers"], second["player_soldiers"])
	assert_eq(first["mover_soldiers"], second["mover_soldiers"])
	var first_player_unit_pos: Vector2 = first["player_unit_pos"]
	var second_player_unit_pos: Vector2 = second["player_unit_pos"]
	assert_eq(first_player_unit_pos.x, second_player_unit_pos.x, "aggregate position matches (x)")
	assert_eq(first_player_unit_pos.y, second_player_unit_pos.y, "aggregate position matches (y)")
	var first_mover_unit_pos: Vector2 = first["mover_unit_pos"]
	var second_mover_unit_pos: Vector2 = second["mover_unit_pos"]
	assert_eq(first_mover_unit_pos.x, second_mover_unit_pos.x, "the marcher's aggregate position matches (x)")
	assert_eq(first_mover_unit_pos.y, second_mover_unit_pos.y, "and (y)")
	assert_eq(first["player_morale"], second["player_morale"], "aggregate morale matches")
	assert_eq(first["player_pos"], second["player_pos"], "identical reconstructed positions (idle side)")
	assert_eq(first["player_hp"], second["player_hp"], "identical reconstructed health (idle side)")
	assert_eq(first["player_facing"], second["player_facing"], "identical reconstructed facings (idle side)")
	assert_eq(first["mover_pos"], second["mover_pos"], "identical reconstructed positions (marching side)")
	assert_eq(first["mover_hp"], second["mover_hp"], "identical reconstructed health (marching side)")
	assert_eq(first["mover_facing"], second["mover_facing"], "identical reconstructed facings (marching side)")

	# The reconstruction is real: one body per living soldier came back.
	var first_player_pos: PackedVector2Array = first["player_pos"]
	var first_mover_pos: PackedVector2Array = first["mover_pos"]
	assert_eq(first_player_pos.size(), int(first["player_soldiers"]),
		"the idle formation reconstructs one body per living soldier")
	assert_eq(first_mover_pos.size(), int(first["mover_soldiers"]),
		"the marching formation reconstructs one body per living soldier")
