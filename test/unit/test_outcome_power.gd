extends GutTest
## OutcomePower (tools/demo/OutcomePower.gd): the 80%-power minimum detectable changes. Each
## is checked by an independent simulation, on another seed, that a change of that size is
## detected about 80% of the time: the property the report claims for its MDS column.


func _rank_power(k: int, d: float, level: float, seed: int, trials: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hits: int = 0
	for t in range(trials):
		var a: Array = []
		var b: Array = []
		for i in range(k):
			a.append(rng.randfn(0.0, 1.0))
			b.append(rng.randfn(d, 1.0))
		if OutcomeStats.rank_sum_p(a, b) <= level:
			hits += 1
	return float(hits) / trials


func _fisher_power(n: int, p1: float, p2: float, level: float, seed: int, trials: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hits: int = 0
	for t in range(trials):
		var x1: int = 0
		var x2: int = 0
		for i in range(n):
			x1 += 1 if rng.randf() < p1 else 0
			x2 += 1 if rng.randf() < p2 else 0
		if OutcomeStats.fisher_p(x1, n, x2, n) <= level:
			hits += 1
	return float(hits) / trials


func test_shift_sd_has_80_percent_power() -> void:
	# 16 runs a side at the level one row of ten must reach alone.
	var d: float = OutcomePower.shift_sd(16, 16, 0.005)
	assert_between(d, 1.3, 1.7, "near the 1.45 SD a direct simulation gives")
	var power: float = _rank_power(16, d, 0.005, 777, 400)
	assert_between(power, 0.72, 0.88, "independent power at the MDS: %s" % power)


func test_shift_sd_is_inf_when_the_level_is_unreachable() -> void:
	# 3 against 3 can reach at best p = 2 / 20 = 0.1.
	assert_eq(OutcomePower.shift_sd(3, 3, 0.05), INF)


func test_proportion_change_has_80_percent_power() -> void:
	var change: float = OutcomePower.proportion_change(0.0, 16, 16, 0.05)
	assert_between(change, 0.3, 0.7)
	var power: float = _fisher_power(16, 0.0, change, 0.05, 778, 400)
	assert_between(power, 0.72, 0.88, "independent power at the MDS: %s" % power)
	assert_eq(OutcomePower.proportion_change(0.5, 4, 4, 0.001), INF,
			"4 against 4 cannot reach p = 0.001")
