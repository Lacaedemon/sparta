class_name OutcomePower
## Minimum detectable changes at a stated power, by simulation, for the tests in
## OutcomeStats. A row's minimum detectable shift (MDS) is the change a fresh pair of
## samples of the row's sizes would show as significant with probability `power` (default
## 0.8): not a guarantee that a change that size is caught, and not the 50% point.
##
## - shift_sd: the location shift, in standard deviations, of two normal samples that the
##   exact rank-sum test rejects at `level`. Multiply by the row's own spread for its units.
##   On a heavily tied metric the real test is weaker, so treat it as a lower bound there.
## - proportion_change: the change in a proportion that Fisher's exact test rejects.
##
## Both use a fixed RNG seed and common random numbers across the bisection, so they are
## deterministic and monotone, and they are cached by their arguments.

## Default power and trial count.
const DEFAULT_POWER := 0.8
const DEFAULT_TRIALS := 400
## The fixed seed every simulation starts from.
const SIM_SEED := 1826
## Bisection steps, and the largest shift searched, in standard deviations.
const STEPS := 12
const MAX_SHIFT_SD := 8.0

static var _cache: Dictionary = {}


## The normal location shift, in SD, detected at `level` with probability `power` by the
## exact rank-sum test on samples of nb and nh. INF when even MAX_SHIFT_SD is not enough.
static func shift_sd(nb: int, nh: int, level: float, power: float = DEFAULT_POWER,
		trials: int = DEFAULT_TRIALS) -> float:
	var key: String = "s|%d|%d|%s|%s|%d" % [nb, nh, str(level), str(power), trials]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = SIM_SEED
	var draws: Array = []
	for t in range(trials):
		var b: Array = []
		var h: Array = []
		for i in range(nb):
			b.append(rng.randfn(0.0, 1.0))
		for i in range(nh):
			h.append(rng.randfn(0.0, 1.0))
		draws.append([b, h])
	var power_at := func(d: float) -> float:
		var hits: int = 0
		for pair in draws:
			var shifted: Array = pair[1].map(func(v: float) -> float: return v + d)
			if OutcomeStats.rank_sum_p(pair[0], shifted) <= level:
				hits += 1
		return float(hits) / float(trials)
	var result: float = INF
	if power_at.call(MAX_SHIFT_SD) >= power:
		var lo: float = 0.0
		var hi: float = MAX_SHIFT_SD
		for i in range(STEPS):
			var mid: float = (lo + hi) / 2.0
			if power_at.call(mid) >= power:
				hi = mid
			else:
				lo = mid
		result = hi
	_cache[key] = result
	return result


## The smallest change, as a proportion (0.25 = 25 percentage points), from a base
## proportion p1 that Fisher's exact test detects at `level` with probability `power`, with
## nb base and nh head runs. The smaller of the upward and downward changes; INF when
## neither direction can reach the power even at 0 or 1.
static func proportion_change(p1: float, nb: int, nh: int, level: float,
		power: float = DEFAULT_POWER, trials: int = DEFAULT_TRIALS) -> float:
	var key: String = "p|%s|%d|%d|%s|%s|%d" % [str(snappedf(p1, 0.0001)), nb, nh, str(level),
			str(power), trials]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = SIM_SEED
	var draws: Array = []
	for t in range(trials):
		var b: Array = []
		var h: Array = []
		for i in range(nb):
			b.append(rng.randf())
		for i in range(nh):
			h.append(rng.randf())
		draws.append([b, h])
	var power_at := func(p2: float) -> float:
		var hits: int = 0
		for pair in draws:
			var x1: int = pair[0].filter(func(u: float) -> bool: return u < p1).size()
			var x2: int = pair[1].filter(func(u: float) -> bool: return u < p2).size()
			if OutcomeStats.fisher_p(x1, nb, x2, nh) <= level:
				hits += 1
		return float(hits) / float(trials)
	var best: float = INF
	for target in [1.0, 0.0]:
		if power_at.call(target) < power:
			continue
		var near: float = p1
		var far: float = target
		for i in range(STEPS):
			var mid: float = (near + far) / 2.0
			if power_at.call(mid) >= power:
				far = mid
			else:
				near = mid
		best = minf(best, absf(far - p1))
	_cache[key] = best
	return best
