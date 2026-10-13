class_name DemoSeed
## Opt-in seed perturbation for demo runs, read from SPARTA_DEMO_SEED_RUN.
##
## Melee outcomes in the catalog clips are chaotic: a negligible change to one unit flips
## which router escapes. One run of a clip is therefore one draw from a distribution, and
## a change to melee dynamics has to be judged across several draws
## (tools/ci/melee-outcome-delta.sh). This is where the draws come from.
##
## A run index k >= 1 replaces the clip's own seed with a seed derived from (base seed, k),
## so the scenario, its orders and its spawn are unchanged. What differs is every draw from
## Replay.rng (melee land and fall rolls, damage rolls, missile hits) and the scatter of a
## far-tier promotion, which comes from a local RNG seeded with Replay.seed_value. Each run
## is bit-identical to the clip until the first of those: a melee roll, but also a missile
## volley or a far-tier promotion, either of which can come before any melee contact.
##
## Unset, empty, or "0" leaves the clip's own seed alone, so every existing clip's hash is
## unchanged. Pure: a function of its arguments only.

## The environment variable both demo entry points read.
const ENV_VAR := "SPARTA_DEMO_SEED_RUN"


## The run index named by `spec`: 0 (off) for an empty string, and -1 for anything that is
## not a non-negative integer, which the caller must treat as an error rather than as off --
## a typo would otherwise run every "perturbed" draw on the clip's own seed and report a
## distribution of identical runs.
static func parse_run(spec: String) -> int:
	var trimmed: String = spec.strip_edges()
	if trimmed == "":
		return 0
	if not trimmed.is_valid_int():
		return -1
	var run: int = trimmed.to_int()
	return run if run >= 0 else -1


## The seed run `run` plays: `base` itself for run 0, otherwise a non-negative 32-bit seed
## hashed from both values, so neighbouring run indices give unrelated RNG streams rather
## than seeds one apart.
static func seed_for_run(base: int, run: int) -> int:
	if run <= 0:
		return base
	return hash([base, run]) & 0x7fffffff
