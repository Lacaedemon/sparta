extends GutTest
## OutcomeStats (tools/demo/OutcomeStats.gd): the exact rank-sum test, the Hodges-Lehmann
## shift and Benjamini-Hochberg behind the perturbed melee-outcome delta. Checked against
## hand-computed values, a brute-force enumeration oracle, and samples drawn from known
## distributions.


## Twice the Mann-Whitney U of `head` over `base`, from the values themselves: 2 per pair
## where head is larger, 1 per tie. No ranks, so it shares no code with OutcomeStats.
func _twice_u(base: Array, head: Array) -> int:
	var u: int = 0
	for h in head:
		for b in base:
			if float(h) > float(b):
				u += 2
			elif float(h) == float(b):
				u += 1
	return u


## Brute-force two-sided p-value: enumerate every split of the pooled values into groups of
## the two sizes and count those whose U is at least as far from its mean as the observed
## one. The independent oracle the dynamic-programming rank-sum version must match exactly.
func _brute_p(base: Array, head: Array) -> float:
	var pooled: Array = base + head
	var n: int = pooled.size()
	var nb: int = head.size()
	var mean_twice: int = base.size() * nb
	var observed: int = absi(_twice_u(base, head) - mean_twice)
	var total: int = 0
	var extreme: int = 0
	for mask in range(1 << n):
		var h: Array = []
		var b: Array = []
		for i in range(n):
			if mask & (1 << i):
				h.append(pooled[i])
			else:
				b.append(pooled[i])
		if h.size() != nb:
			continue
		total += 1
		if absi(_twice_u(b, h) - mean_twice) >= observed:
			extreme += 1
	return float(extreme) / float(total)


func _normal_sample(rng: RandomNumberGenerator, n: int, mean: float) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(rng.randfn(mean, 1.0))
	return out


func test_median_odd_even_and_empty() -> void:
	assert_eq(OutcomeStats.median([3, 1, 2]), 2.0, "odd count: the middle value")
	assert_eq(OutcomeStats.median([4, 1, 3, 2]), 2.5, "even count: the mean of the middle two")
	assert_eq(OutcomeStats.median([]), 0.0, "empty sample reads 0")


func test_hodges_lehmann_is_the_median_pairwise_difference() -> void:
	assert_eq(OutcomeStats.hodges_lehmann([1, 2, 3], [11, 12, 13]), 10.0, "a pure shift of 10")
	assert_eq(OutcomeStats.hodges_lehmann([11, 12, 13], [1, 2, 3]), -10.0, "sign follows head minus base")
	# Pairwise differences of [0, 10] against [1, 2]: 1, 2, -9, -8 -> median (-8 + 1) / 2.
	assert_eq(OutcomeStats.hodges_lehmann([0, 10], [1, 2]), -3.5, "even count of differences")


func test_doubled_midranks_share_ties() -> void:
	assert_eq(OutcomeStats.doubled_midranks([30, 10, 20, 20]), PackedInt64Array([8, 2, 5, 5]),
			"ranks 1..4 doubled; the tie at ranks 2 and 3 shares 2.5, doubled 5")


func test_rank_sum_p_complete_separation_is_exact() -> void:
	# The most extreme of C(8, 4) = 70 splits, in either direction: 2 / 70.
	assert_almost_eq(OutcomeStats.rank_sum_p([1, 2, 3, 4], [5, 6, 7, 8]), 2.0 / 70.0, 1e-12)
	assert_almost_eq(OutcomeStats.rank_sum_p([5, 6, 7, 8], [1, 2, 3, 4]), 2.0 / 70.0, 1e-12)
	assert_almost_eq(OutcomeStats.rank_sum_p([1, 2], [3, 4]), 2.0 / 6.0, 1e-12, "C(4, 2) = 6 splits")


func test_rank_sum_p_is_one_when_nothing_can_differ() -> void:
	assert_eq(OutcomeStats.rank_sum_p([5, 5, 5], [5, 5, 5]), 1.0, "every pooled value equal")
	assert_eq(OutcomeStats.rank_sum_p([], [1, 2]), 1.0, "an empty side")
	assert_eq(OutcomeStats.rank_sum_p([1, 2, 3, 4], [1, 2, 3, 4]), 1.0, "the same sample on both sides")


func test_rank_sum_p_matches_brute_force_with_and_without_ties() -> void:
	var cases: Array = [
		[[1, 2, 3, 4, 5], [3, 4, 5, 6, 7]],
		[[0, 0, 0, 1, 1], [1, 1, 1, 1, 2]],
		[[10, 10, 20, 1.0e12], [1.0e12, 1.0e12, 20, 30]],
		[[7, 1, 4], [2, 9, 9, 3, 8]],
		[[2, 2, 2, 2, 2, 3], [2, 2, 3, 3, 3, 3]],
	]
	for c in cases:
		assert_almost_eq(OutcomeStats.rank_sum_p(c[0], c[1]), _brute_p(c[0], c[1]), 1e-12,
				"dynamic programme equals enumeration for %s vs %s" % [str(c[0]), str(c[1])])


func test_rank_sum_p_holds_its_size_under_the_null() -> void:
	# Two samples of 8 from the same normal, 400 times: an exact test rejects at most 5% in
	# expectation. The bound allows sampling noise (sd of a 5% rate over 400 is about 1.1%).
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var rejections: int = 0
	for trial in range(400):
		if OutcomeStats.rank_sum_p(_normal_sample(rng, 8, 0.0), _normal_sample(rng, 8, 0.0)) <= 0.05:
			rejections += 1
	assert_lt(rejections, 32, "null rejection rate %d/400 must stay near or below 5%%" % rejections)


func test_rank_sum_p_detects_a_two_sd_shift() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rejections: int = 0
	for trial in range(100):
		if OutcomeStats.rank_sum_p(_normal_sample(rng, 8, 0.0), _normal_sample(rng, 8, 2.0)) <= 0.05:
			rejections += 1
	assert_gt(rejections, 85, "power against a 2 sd shift with 8 per side is about 0.93")


func test_benjamini_hochberg_known_example() -> void:
	# m = 8, q = 0.05: thresholds 0.00625, 0.0125, 0.01875, ... -- only the first two pass.
	var p: Array = [0.001, 0.008, 0.039, 0.041, 0.042, 0.06, 0.074, 0.205]
	assert_eq(OutcomeStats.benjamini_hochberg(p, 0.05),
			[true, true, false, false, false, false, false, false])


func test_benjamini_hochberg_step_up_and_input_order() -> void:
	# Sorted 0.01, 0.02, 0.03 against 0.0167, 0.0333, 0.05: the largest passing rank (3)
	# rejects everything below it, in whatever order the inputs came.
	assert_eq(OutcomeStats.benjamini_hochberg([0.03, 0.005, 0.015], 0.05), [true, true, true])
	assert_eq(OutcomeStats.benjamini_hochberg([0.5, 0.9], 0.05), [false, false])
	assert_eq(OutcomeStats.benjamini_hochberg([], 0.05), [])


func test_rank_sum_p_hand_computed_with_ties() -> void:
	# Exact enumerations of every split, computed outside this code base.
	assert_almost_eq(OutcomeStats.rank_sum_p([0, 0, 0, 1, 1], [1, 1, 1, 1, 2]), 0.119048, 1e-6)
	assert_almost_eq(OutcomeStats.rank_sum_p([1, 2, 3, 4, 5], [3, 4, 5, 6, 7]), 0.126984, 1e-6)


func test_min_attainable_p() -> void:
	# Eight distinct values per side: the best a split can do is 2 / C(16, 8).
	var base: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	assert_almost_eq(OutcomeStats.min_attainable_p(base, [9, 10, 11, 12, 13, 14, 15, 16]),
			2.0 / 12870.0, 1e-15)
	assert_eq(OutcomeStats.min_attainable_p([3, 3], [3, 3]), 1.0, "all tied: no split differs")


func test_fisher_p_hand_computed() -> void:
	# Margins 4 and 4 with 4 events: tables k = 0..4 have weights 1, 16, 36, 16, 1 out of 70.
	# k = 3 (or 1) is matched or beaten by 1, 16, 16, 1: 34 / 70.
	assert_almost_eq(OutcomeStats.fisher_p(3, 4, 1, 4), 34.0 / 70.0, 1e-12)
	assert_almost_eq(OutcomeStats.fisher_p(0, 8, 8, 8), 2.0 / 12870.0, 1e-15,
			"complete separation of 8 and 8")
	assert_eq(OutcomeStats.fisher_p(2, 4, 2, 4), 1.0, "equal proportions")
	assert_eq(OutcomeStats.fisher_p(0, 0, 3, 4), 1.0, "an empty side")


func test_robust_sd() -> void:
	# MAD of [1, 2, 3, 4, 100] is 1 (deviations 2, 1, 0, 1, 97), so 1.4826.
	assert_almost_eq(OutcomeStats.robust_sd([1, 2, 3, 4, 100]), 1.4826, 1e-9)
	# More than half equal: MAD 0, so the plain sample sd of [5, 5, 5, 9] (2.0).
	assert_almost_eq(OutcomeStats.robust_sd([5, 5, 5, 9]), 2.0, 1e-9)
	assert_eq(OutcomeStats.robust_sd([7]), 0.0)


func test_benjamini_yekutieli_divides_by_the_harmonic_number() -> void:
	assert_almost_eq(OutcomeStats.harmonic(3), 1.0 + 0.5 + 1.0 / 3.0, 1e-12)
	# m = 3, H = 1.8333: BY thresholds 0.00909, 0.01818, 0.02727; BH 0.0167, 0.0333, 0.05.
	assert_eq(OutcomeStats.benjamini_yekutieli([0.03, 0.005, 0.015], 0.05), [false, true, true])
	assert_eq(OutcomeStats.benjamini_hochberg([0.03, 0.005, 0.015], 0.05), [true, true, true])
