extends GutTest
## The state transcript's `tier` field and far-tier payload omission (docs/
## large-scale-simulation-design.md, phase 4): a close-tier unit's record carries
## `tier: "CLOSE"` plus the per-soldier payload (`soldier_summary`, and `soldiers_full`
## when the full dump is requested), while a far-tier unit's record carries `tier: "FAR"`
## and NO per-soldier payload at all — so "this formation has no individual soldiers"
## reads differently from "per-soldier detail not requested". Asserted against a live
## battle whose formations actually hold both tiers, not a hand-built record.

const RecorderScript = preload("res://tools/demo/DemoInputRecorder.gd")
const BATTLE_SEED := 12345
# Staging: the enemy sits at ENEMY_POS; one player unit starts mid-hysteresis-band from
# it (neither trigger fires, so it keeps its spawn tier: CLOSE, with live bodies), and a
# second player unit starts beyond DEMOTE_RANGE (it demotes on an early tier pass). The
# tier pass judges the gap between the blocks' edges, so each unit is placed (before the
# first tier pass) at the centre distance that puts its edge gap where the staging wants
# it, measured from the live blocks' reaches. Both gaps derive from the FormationTier
# constants, so a threshold retune moves the staging with it instead of breaking it.
const ENEMY_POS := Vector2(1200.0, 850.0)
# Ticks allowed for the demotion to land. It fires on the first tier pass, but the
# budget leaves slack so an added spin-up tick can't flake the test.
const DEMOTE_BUDGET_TICKS := 30


func test_record_distinguishes_far_tier_from_not_requested() -> void:
	Replay.forced_seed = BATTLE_SEED
	var battle: Node2D = load("res://scenes/Battle.tscn").instantiate()
	var band_mid: float = (FormationTier.PROMOTE_RANGE + FormationTier.DEMOTE_RANGE) * 0.5
	var far_gap: float = FormationTier.DEMOTE_RANGE + 100.0
	# Nominal spawn spots, one on each axis from the enemy; _place_at_gap then re-measures.
	var far_x: float = ENEMY_POS.x - 700.0
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": ENEMY_POS.x, "y": ENEMY_POS.y - band_mid, "count": 40},
		{"team": 0, "type": "Infantry", "x": far_x, "y": ENEMY_POS.y, "count": 40},
		{"team": 1, "type": "Infantry", "x": ENEMY_POS.x, "y": ENEMY_POS.y, "count": 30},
	]
	add_child(battle)

	var recorder = RecorderScript.new()   # never added to the tree: _ready must not run
	autofree(recorder)
	recorder._battle = battle
	recorder._state_full = true

	var close_unit: Unit = _player_unit_at_x(ENEMY_POS.x)
	var far_unit: Unit = _player_unit_at_x(far_x)
	assert_not_null(close_unit, "the scenario spawns the hysteresis-band unit")
	assert_not_null(far_unit, "the scenario spawns the beyond-demote-range unit")
	if close_unit == null or far_unit == null:
		battle.free()
		return

	var enemy: Unit = null
	for node in get_tree().get_nodes_in_group("units"):
		var e: Unit = node as Unit
		if e != null and e.team == 1:
			enemy = e
	_place_at_gap(close_unit, enemy, band_mid)
	_place_at_gap(far_unit, enemy, far_gap)

	# Let the tier pass run: the distant unit demotes, the band unit keeps its tier.
	var demoted: bool = false
	while battle.current_tick() < DEMOTE_BUDGET_TICKS:
		await get_tree().physics_frame
		if far_unit.tier == FormationTier.FAR:
			demoted = true
			break
	assert_true(demoted, "the formation demotes within the budget (spawned beyond DEMOTE_RANGE)")

	# Close-tier record shape: tier marker plus the full per-soldier payload.
	assert_eq(close_unit.tier, FormationTier.CLOSE,
		"mid-band, neither trigger fires — the unit keeps its close spawn tier")
	var close_rec: Dictionary = recorder._unit_record(close_unit)
	assert_eq(close_rec["tier"], "CLOSE", "a close-tier unit's record names its tier")
	assert_true(close_rec.has("soldier_summary"), "a close-tier record carries the summary")
	assert_true(close_rec.has("soldiers_full"),
		"a close-tier record carries the raw arrays when the full dump is requested")
	assert_eq(int(close_rec["soldier_summary"]["count"]), 40,
		"the close-tier summary describes the real bodies")

	# Far-tier record shape: tier marker, aggregate scalars, and NO per-soldier payload.
	var far_rec: Dictionary = recorder._unit_record(far_unit)
	assert_eq(far_rec["tier"], "FAR", "a far-tier unit's record names its tier")
	assert_false(far_rec.has("soldier_summary"),
		"a far-tier record omits soldier_summary — no individual bodies to summarize")
	assert_false(far_rec.has("soldiers_full"),
		"a far-tier record omits soldiers_full even when the full dump is requested")
	assert_eq(int(far_rec["soldiers"]), 40,
		"the aggregate living count still serializes for a far-tier unit")

	battle.free()


## Slide `unit` along its line from `enemy` so the edge gap between their blocks (the
## quantity the tier pass tests) equals `gap`: the centre distance is `gap` plus both
## blocks' reaches along that line.
func _place_at_gap(unit: Unit, enemy: Unit, gap: float) -> void:
	var dir: Vector2 = (unit.position - enemy.position).normalized()
	var unit_reach: float = FormationTier.support_reach(unit.tier_half_extents(),
			unit.soldier_block_world_angle(), -dir)
	var enemy_reach: float = FormationTier.support_reach(enemy.tier_half_extents(),
			enemy.soldier_block_world_angle(), dir)
	unit.position = enemy.position + dir * (gap + unit_reach + enemy_reach)


func _player_unit_at_x(x: float) -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.team == 0 and absf(u.position.x - x) < 1.0:
			return u
	return null
