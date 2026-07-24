extends GutTest
## Live-battle regression for issue #1027: a full, centre-symmetric block ordered to
## reverse direction TWICE in a row (two consecutive about-faces) used to collapse into a
## blob on the SECOND reversal, then slowly re-expand over hundreds of ticks -- the
## "pulsing" the report showed.
##
## Root cause: after one about-face a full block rests validly with _formation_angle folded
## to +/-PI -- a point-reflected but self-consistent grid the bodies already sit on. The
## next fresh order's start_order_response() re-squared with a naked `_formation_angle = 0.0`,
## which un-reflects the SLOT grid while the bodies stay point-reflected: every soldier is
## suddenly a full block-DIAGONAL from its own (index-matched) slot, so the arrival dragged
## them all across the block centre at once (mean nearest-neighbour distance collapsing from
## the 9 wu commanded spacing to under 2 wu -- genuine body overlap). The fix routes the
## re-square through reform_ranks(), which leaves a full block's +/-PI fold in place (and
## arms the depth-only mirror for a partial block), so the second reversal turns in good
## order exactly like the first.
##
## Stages it directly (no enemy, drill mode): a lone Infantry regiment faces down, is ordered
## to reverse UP (first about-face), and once that turn has settled is ordered to reverse DOWN
## again (second about-face). Budgets bound on Battle.current_tick() (real sim ticks) so
## coverage instrumentation cannot drift them.

## Ticks allowed for a single about-face to arm, turn, and settle back onto its slots.
const TURN_SETTLE_BUDGET: int = 250
## Ticks to run through the second come-about and its re-form.
const SECOND_TURN_BUDGET: int = 350
## A body sits within this of its own slot once the block is formed (not mid-sweep). The
## clean turn's mid-rotation residual -- slots rotating while the bodies hold -- is far
## larger and transient, so this is only asserted when the unit is NOT maneuver-turning.
const FORMED_RESID_MAX: float = 8.0
## The point-reflection strands every body a full block-diagonal (~140 wu here) off its slot
## the instant the second order applies, an order of magnitude past any formed residual --
## so this arm-time bound catches the un-reflect flip directly and phase-independently.
const REFLECT_RESID_MAX: float = 30.0
## Nearest-neighbour distance never collapses toward body overlap. Pre-fix bottomed near
## 1.9 wu on the second reversal; the fix holds it well above. The floor clears both.
const NND_FLOOR: float = 5.0


func _max_resid(unit: Unit) -> float:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var n: int = mini(slots.size(), unit._sim_soldier_pos.size())
	var worst: float = 0.0
	for i in range(n):
		worst = maxf(worst, unit._sim_soldier_pos[i].distance_to(slots[i]))
	return worst


func _mean_nnd(unit: Unit) -> float:
	var pos: PackedVector2Array = unit._sim_soldier_pos
	var n: int = pos.size()
	if n < 2:
		return 0.0
	var total: float = 0.0
	for i in range(n):
		var best: float = INF
		for j in range(n):
			if i == j:
				continue
			best = minf(best, pos[i].distance_squared_to(pos[j]))
		total += sqrt(best)
	return total / float(n)


## Order a rear-sector move and wait until the about-face it decomposes into has armed,
## turned, and fully settled (turning seen, then cleared). Returns the tick it settled on.
func _reverse_and_settle(battle: Node, unit: Unit, dest: Vector2) -> void:
	battle._apply_order_cmd({"units": [unit.uid], "x": dest.x, "y": dest.y, "target": -1})
	var deadline: int = battle.current_tick() + TURN_SETTLE_BUDGET
	var turned: bool = false
	while battle.current_tick() < deadline:
		await get_tree().physics_frame
		if unit.is_maneuver_turning():
			turned = true
		elif turned:
			# The about-face finished this tick; give the bodies a moment to re-seat.
			var settle: int = battle.current_tick() + 30
			while battle.current_tick() < settle:
				await get_tree().physics_frame
			return
	assert_true(turned, "the reverse move ran an about-face within its budget")


func test_second_consecutive_reversal_does_not_point_reflect_or_blob() -> void:
	Replay.forced_seed = 12345
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	battle.drill_mode = true
	battle.terrain = []
	battle.scenario = [
		{"team": 0, "type": "Infantry", "x": 557, "y": 400, "facing": [0, 1], "count": 120},
	]
	add_child_autofree(battle)
	var inf: Unit = null
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit:
			inf = node
	assert_not_null(inf, "the scenario spawns the infantry")
	if inf == null:
		return
	# Let the bodies seed onto their slots before any order.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(inf.soldiers % maxi(1, inf.frontage), 0, 0,
		"the block is full (centre-symmetric) -- the case that rests at a +/-PI fold")

	# First reversal: face-down block ordered UP. A single about-face from a clean
	# (_formation_angle == 0) baseline -- this one was always fine.
	await _reverse_and_settle(battle, inf, Vector2(557, 120))
	assert_lt(_max_resid(inf), FORMED_RESID_MAX,
		"after the first about-face the block is formed on its slots")

	# Second reversal: now-up-facing block ordered back DOWN. This is the regressed case:
	# start_order_response() must NOT naively zero the +/-PI fold and point-reflect the bodies.
	# Check the instant the order applies (synchronous), before the turn rotates any slots.
	battle._apply_order_cmd({"units": [inf.uid], "x": 557.0, "y": 680.0, "target": -1})
	assert_lt(_max_resid(inf), REFLECT_RESID_MAX,
		"the second order re-squares without point-reflecting the bodies off their slots")

	# Drive the second come-about and its re-form; the block must never blob.
	var deadline: int = battle.current_tick() + SECOND_TURN_BUDGET
	var min_nnd: float = INF
	var saw_turn: bool = false
	var settled_resid: float = -1.0
	while battle.current_tick() < deadline:
		await get_tree().physics_frame
		min_nnd = minf(min_nnd, _mean_nnd(inf))
		if inf.is_maneuver_turning():
			saw_turn = true
		elif saw_turn:
			settled_resid = _max_resid(inf)
	assert_true(saw_turn, "the second reverse move ran its own about-face")
	assert_gt(min_nnd, NND_FLOOR,
		"the block holds its spacing through the second reversal instead of blobbing")
	assert_gte(settled_resid, 0.0, "the second about-face settled within the budget")
	if settled_resid >= 0.0:
		assert_lt(settled_resid, FORMED_RESID_MAX,
			"and the block re-forms cleanly on its slots afterward")
