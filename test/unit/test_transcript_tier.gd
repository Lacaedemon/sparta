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
# Staging: the enemy sits at ENEMY_POS; one player unit spawns mid-hysteresis-band from
# it (neither trigger fires, so it keeps its spawn tier: CLOSE, with live bodies), and a
# second player unit spawns beyond DEMOTE_RANGE (it demotes on an early tier pass). Both
# distances derive from the FormationTier constants, so a threshold retune moves the
# spawns with it instead of breaking the staging.
const ENEMY_POS := Vector2(800.0, 850.0)
# Ticks allowed for the demotion to land. It fires on the first tier pass, but the
# budget leaves slack so an added spin-up tick can't flake the test.
const DEMOTE_BUDGET_TICKS := 30


func test_record_distinguishes_far_tier_from_not_requested() -> void:
	Replay.forced_seed = BATTLE_SEED
	var battle: Node2D = load("res://scenes/Battle.tscn").instantiate()
	var band_mid: float = (FormationTier.PROMOTE_RANGE + FormationTier.DEMOTE_RANGE) * 0.5
	var far_dist: float = FormationTier.DEMOTE_RANGE + 100.0
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": ENEMY_POS.x, "y": ENEMY_POS.y - band_mid, "count": 40},
		{"team": 0, "type": "Infantry", "x": ENEMY_POS.x - far_dist, "y": ENEMY_POS.y, "count": 40},
		{"team": 1, "type": "Infantry", "x": ENEMY_POS.x, "y": ENEMY_POS.y, "count": 30},
	]
	add_child(battle)

	var recorder = RecorderScript.new()   # never added to the tree: _ready must not run
	autofree(recorder)
	recorder._battle = battle
	recorder._state_full = true

	var close_unit: Unit = _player_unit_at_x(ENEMY_POS.x)
	var far_unit: Unit = _player_unit_at_x(ENEMY_POS.x - far_dist)
	assert_not_null(close_unit, "the scenario spawns the hysteresis-band unit")
	assert_not_null(far_unit, "the scenario spawns the beyond-demote-range unit")
	if close_unit == null or far_unit == null:
		battle.free()
		return

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


func _player_unit_at_x(x: float) -> Unit:
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u != null and u.team == 0 and absf(u.position.x - x) < 1.0:
			return u
	return null
