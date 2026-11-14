extends GutTest
## SoldierRoutReach: the men of a fighting unit with a routed runner in their reach strike him,
## wherever they stand in the block, not only its engaged front.

const AT := Vector2(500, 500)


func _unit(team: int, count: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = count
	u.team = team
	add_child_autofree(u)
	u.position = AT
	u.seed_sim_soldiers()
	return u


## A 144-man block facing north and one runner just off its east flank, beside the flank man of
## its middle rank, whom neither its front nor its rear ranks take in.
func _runner_at_the_flank() -> Array:
	var block := _unit(0, 144)
	var east: float = -INF
	for p in block._sim_soldier_pos:
		east = maxf(east, p.x)
	var flank: Array = []
	for i in range(block._sim_soldier_pos.size()):
		if block._sim_soldier_pos[i].x > east - 1.0:
			flank.append(i)
	flank.sort_custom(func(a: int, b: int) -> bool:
		return block._sim_soldier_pos[a].y < block._sim_soldier_pos[b].y)
	var flank_man: int = flank[flank.size() / 2]
	var r := _unit(1, 1)
	r._sim_soldier_pos[0] = block._sim_soldier_pos[flank_man] + Vector2(0.5 * block.soldier_reach(), 0)
	r._rout()
	block.state = Unit.State.FIGHTING
	block.target_enemy = r
	return [block, r, flank_man]


func test_the_men_with_a_runner_in_reach_are_the_strikers() -> void:
	var staged: Array = _runner_at_the_flank()
	var block: Unit = staged[0]
	var flank_man: int = staged[2]
	var men: PackedInt32Array = SoldierRoutReach.men_in_reach(block, staged[1])
	assert_true(men.has(flank_man), "the flank man beside the runner strikes")
	assert_false(block.engaged_soldier_indices(block._sim_soldier_pos.size()).has(flank_man),
			"setup: he is not of the block's engaged front")
	for i in men:
		assert_lte(block._sim_soldier_pos[i].distance_to(staged[1]._sim_soldier_pos[0]),
				block.soldier_reach(), "and none out of reach does")


func test_a_runner_at_a_fighting_block_s_flank_is_cut_down() -> void:
	var staged: Array = _runner_at_the_flank()
	var block: Unit = staged[0]
	var r: Unit = staged[1]
	for i in range(block._sim_soldier_facing.size()):
		block._sim_soldier_facing[i] = Vector2.RIGHT   # the flank men turn on the runner
	var before: float = r._sim_soldier_hp[0]
	for _k in range(40):
		if r._sim_soldier_hp.is_empty():
			break
		UnitCombat.strike(block, r)
	var after: float = r._sim_soldier_hp[0] if not r._sim_soldier_hp.is_empty() else 0.0
	assert_lt(after, before, "the men beside him land their blows")
