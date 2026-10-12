class_name OutcomeStats
## Small, exact, rank-based statistics for comparing two samples of demo outcomes
## (tools/demo/melee_outcome_compare.gd). Every function reads only its arguments; the one
## piece of state is a cache of null distributions, which depend only on their inputs.
##
## The test is a two-sided Mann-Whitney / Wilcoxon rank-sum test with an EXACT permutation
## p-value. Ties share their mid-rank, and the null distribution is built from the actual
## tie structure of the pooled sample, so a metric with many ties (a headcount, a censored
## "never" value) gets the right p-value rather than a normal approximation's. The effect
## size is the Hodges-Lehmann shift (the median of every head-minus-base difference), the
## estimator that goes with the rank-sum test.
##
## Benjamini-Hochberg turns a report's p-values into flags at a false discovery rate q: in
## expectation, at most a fraction q of the flags are false. That holds for independent or
## positively dependent rows. Only when no row has a real change does it also mean the
## chance of any flag is at most q. Benjamini-Yekutieli divides q by the harmonic number of
## the row count and holds the same FDR bound under any dependence.

## Null distributions already built, keyed by the pooled tie structure and the head size.
static var _null_cache: Dictionary = {}


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


## A robust standard deviation: 1.4826 times the median absolute deviation, which equals
## the standard deviation for a normal sample. Falls back to the plain sample standard
## deviation when more than half the values are equal (a MAD of 0). 0.0 for fewer than 2.
static func robust_sd(values: Array) -> float:
	if values.size() < 2:
		return 0.0
	var m: float = median(values)
	var deviations: Array = values.map(func(v) -> float: return absf(float(v) - m))
	var mad: float = 1.4826 * median(deviations)
	if mad > 0.0:
		return mad
	var mean: float = 0.0
	for v in values:
		mean += float(v)
	mean /= values.size()
	var ss: float = 0.0
	for v in values:
		ss += (float(v) - mean) * (float(v) - mean)
	return sqrt(ss / (values.size() - 1))


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


## The null distribution of the head group's doubled rank sum: entry s counts the head-sized
## subsets of `ranks` summing to s. Counts reach C(n, nb), past int64 for large samples, so
## they are floats; only their ratios are used. Cached by tie structure.
static func _null_distribution(ranks: PackedInt64Array, nb: int) -> PackedFloat64Array:
	var sorted: Array = Array(ranks)
	sorted.sort()
	var key: String = "%d|%s" % [nb, str(sorted)]
	if _null_cache.has(key):
		return _null_cache[key]
	var max_sum: int = 0
	for r in ranks:
		max_sum += r
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
	_null_cache[key] = counts[nb]
	return counts[nb]


## The two-sided p-value of a doubled head rank sum `observed` under `dist`, whose
## expectation is nb * (n + 1).
static func _tail_p(dist: PackedFloat64Array, observed: int, expected: int) -> float:
	var deviation: int = absi(observed - expected)
	var total: float = 0.0
	var extreme: float = 0.0
	for s in range(dist.size()):
		total += dist[s]
		if absi(s - expected) >= deviation:
			extreme += dist[s]
	return extreme / total if total > 0.0 else 1.0


## Exact two-sided p-value of the rank-sum test of `head` against `base`: the probability,
## over every equally likely split of the pooled values into groups of the two sizes, of a
## rank sum at least as far from its expectation as the observed one. 1.0 when either
## sample is empty or every pooled value is equal (no split can differ).
static func rank_sum_p(base: Array, head: Array) -> float:
	var nb: int = head.size()
	var n: int = base.size() + nb
	if base.is_empty() or head.is_empty():
		return 1.0
	var ranks: PackedInt64Array = doubled_midranks(base + head)
	var observed: int = 0
	for k in range(base.size(), n):
		observed += ranks[k]
	return _tail_p(_null_distribution(ranks, nb), observed, nb * (n + 1))


## The smallest p-value any split of these pooled values could give: the head group taking
## the lowest or the highest ranks. A row whose minimum attainable p is above the level it
## must reach can never be flagged, whatever the change.
static func min_attainable_p(base: Array, head: Array) -> float:
	var nb: int = head.size()
	var n: int = base.size() + nb
	if base.is_empty() or head.is_empty():
		return 1.0
	var ranks: PackedInt64Array = doubled_midranks(base + head)
	var sorted: Array = Array(ranks)
	sorted.sort()
	var low: int = 0
	var high: int = 0
	for k in range(nb):
		low += sorted[k]
		high += sorted[n - 1 - k]
	var dist: PackedFloat64Array = _null_distribution(ranks, nb)
	var expected: int = nb * (n + 1)
	return minf(_tail_p(dist, low, expected), _tail_p(dist, high, expected))


## The smallest shift that, added to every value of `base` to make a head sample of the same
## size, gives a rank-sum p-value at or below `level`: this row's minimum detectable pure
## location shift, in its own units. 0.0 when base is constant (any shift separates it),
## INF when even a complete separation cannot reach `level`.
static func min_detectable_shift(base: Array, level: float) -> float:
	if base.is_empty():
		return INF
	var shifted := func(d: float) -> Array: return base.map(func(v) -> float: return float(v) + d)
	# The p-value only changes where the shift crosses a pairwise gap of base, so those gaps,
	# plus one past the range (complete separation), are the only candidates.
	var gaps: Dictionary = {}
	for a in base:
		for b in base:
			if float(b) > float(a):
				gaps[float(b) - float(a)] = true
	var candidates: Array = gaps.keys()
	candidates.sort()
	var span: float = 0.0 if candidates.is_empty() else candidates[-1]
	if rank_sum_p(base, shifted.call(span + 1.0)) > level:
		return INF
	if candidates.is_empty():
		return 0.0
	for d in candidates:
		# Just past each gap, where the crossing has happened.
		var past: float = d * (1.0 + 1e-9) + 1e-9
		if rank_sum_p(base, shifted.call(past)) <= level:
			return d
	return span


## Benjamini-Hochberg at false discovery rate `q`: true at index i when p_values[i] is
## rejected. Valid for independent or positively dependent p-values.
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


## Benjamini-Yekutieli: Benjamini-Hochberg at q / (1 + 1/2 + ... + 1/m), which bounds the
## false discovery rate at q under any dependence between the rows.
static func benjamini_yekutieli(p_values: Array, q: float) -> Array:
	return benjamini_hochberg(p_values, q / harmonic(p_values.size()))


## 1 + 1/2 + ... + 1/m; 1.0 for m <= 1.
static func harmonic(m: int) -> float:
	var h: float = 0.0
	for k in range(1, maxi(m, 1) + 1):
		h += 1.0 / float(k)
	return h
