class_name OutcomeStats
## Small, exact, rank-based statistics for comparing two samples of demo outcomes
## (tools/demo/melee_outcome_compare.gd). Pure: every function reads only its arguments.
##
## The test is a two-sided Mann-Whitney / Wilcoxon rank-sum test with an EXACT permutation
## p-value. Ties share their mid-rank, and the null distribution is built from the actual
## tie structure of the pooled sample, so a metric with many ties (a headcount, a censored
## "never" value) gets the right p-value rather than a normal approximation's. The effect
## size is the Hodges-Lehmann shift (the median of every head-minus-base difference), the
## estimator that goes with the rank-sum test. Benjamini-Hochberg turns the p-values of a
## whole report into flags at a chosen false discovery rate.


## The median of `values` (the mean of the middle two for an even count). 0.0 when empty.
static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) / 2.0


## The Hodges-Lehmann shift of `head` relative to `base`: the median of head[j] - base[i]
## over every pair. Positive when head runs higher. 0.0 when either sample is empty.
static func hodges_lehmann(base: Array, head: Array) -> float:
	var diffs: Array = []
	for b in head:
		for a in base:
			diffs.append(float(b) - float(a))
	return median(diffs)


## Twice the mid-rank of each value of `pooled`, in input order. Doubling keeps every
## mid-rank an integer (a tie spanning ranks i..j has mid-rank (i + j) / 2).
static func doubled_midranks(pooled: Array) -> PackedInt64Array:
	var n: int = pooled.size()
	var order: Array = range(n)
	order.sort_custom(func(x: int, y: int) -> bool: return float(pooled[x]) < float(pooled[y]))
	var ranks := PackedInt64Array()
	ranks.resize(n)
	var i: int = 0
	while i < n:
		var j: int = i
		while j + 1 < n and float(pooled[order[j + 1]]) == float(pooled[order[i]]):
			j += 1
		# Ranks are 1-based: positions i..j hold ranks i+1..j+1, whose doubled mean is i+j+2.
		for k in range(i, j + 1):
			ranks[order[k]] = i + j + 2
		i = j + 1
	return ranks


## Exact two-sided p-value of the rank-sum test of `head` against `base`: the probability,
## over every equally likely split of the pooled values into groups of the two sizes, of a
## rank sum at least as far from its expectation as the observed one. 1.0 when either
## sample is empty or every pooled value is equal (no split can differ).
static func rank_sum_p(base: Array, head: Array) -> float:
	var nb: int = head.size()
	var n: int = base.size() + nb
	if base.is_empty() or head.is_empty():
		return 1.0
	var pooled: Array = base + head
	var ranks: PackedInt64Array = doubled_midranks(pooled)
	var observed: int = 0
	for k in range(base.size(), n):
		observed += ranks[k]
	var max_sum: int = 0
	for r in ranks:
		max_sum += r
	# counts[j][s]: how many j-element subsets of the values seen so far have doubled
	# rank sum s. Counts reach C(n, nb), past int64 for large samples, so they are floats;
	# only their ratio is used.
	var counts: Array = []
	for j in range(nb + 1):
		var row := PackedFloat64Array()
		row.resize(max_sum + 1)
		counts.append(row)
	counts[0][0] = 1.0
	var seen: int = 0
	for r in ranks:
		seen += 1
		for j in range(mini(seen, nb), 0, -1):
			var row: PackedFloat64Array = counts[j]
			var prev: PackedFloat64Array = counts[j - 1]
			for s in range(max_sum, r - 1, -1):
				row[s] += prev[s - r]
			counts[j] = row
	# The doubled expectation of the head group's rank sum is nb * (n + 1).
	var expected: int = nb * (n + 1)
	var deviation: int = absi(observed - expected)
	var total: float = 0.0
	var extreme: float = 0.0
	var dist: PackedFloat64Array = counts[nb]
	for s in range(max_sum + 1):
		total += dist[s]
		if absi(s - expected) >= deviation:
			extreme += dist[s]
	return extreme / total if total > 0.0 else 1.0


## Benjamini-Hochberg at false discovery rate `q`: true at index i when p_values[i] is
## rejected. With every null true, the chance of any rejection is at most q.
static func benjamini_hochberg(p_values: Array, q: float) -> Array:
	var m: int = p_values.size()
	var order: Array = range(m)
	order.sort_custom(func(x: int, y: int) -> bool: return float(p_values[x]) < float(p_values[y]))
	var cutoff: int = -1
	for k in range(m):
		if float(p_values[order[k]]) <= q * float(k + 1) / float(m):
			cutoff = k
	var rejected: Array = []
	rejected.resize(m)
	rejected.fill(false)
	for k in range(cutoff + 1):
		rejected[order[k]] = true
	return rejected
