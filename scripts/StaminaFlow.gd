class_name StaminaFlow
extends RefCounted
## Per-gait stamina flow (docs/combat-model.md "Posture"): the posture table's stamina
## column, read off the regiment's live pace instead of a named posture state. Resting
## regenerates, a walk is neutral, a jog drains slowly, a sprint drains fast. Pure and
## static: callers pass their own paces and rates in, so a Unit, a far-tier record, or a
## test can share one rule without any of them owning it.
##
## Rates are stamina points per SECOND of simulated time -- a time rate, not a length,
## so the units convention's metres-to-world-units conversion does not apply to them.


## The "band" for a stationary or near-stationary regiment: resting, so it regenerates.
## Distinct from every Unit.GAIT_* value (all >= 0).
const BAND_REST: int = -1


## Which stamina band a regiment moving at `speed` (world units/s) is in, given its own
## walk and jog paces. The boundaries sit halfway between adjacent paces, so a unit
## ramping from one pace to the next flips band at the midpoint of the ramp rather than
## the instant it leaves the slower pace; anything at or below `rest_epsilon` is at rest.
## Returns BAND_REST, Unit.GAIT_WALK, Unit.GAIT_JOG, or Unit.GAIT_SPRINT.
static func band_for_speed(speed: float, walk_speed: float, jog_speed: float,
		rest_epsilon: float) -> int:
	if speed <= rest_epsilon:
		return BAND_REST
	if jog_speed <= walk_speed:
		# A jog no faster than the walk leaves the jog band no width, so the halfway
		# boundaries below would bill every jog as a walk or a sprint and GAIT_JOG could
		# never be charged. Loud, then explicit: up to the walk pace walks, anything
		# faster is billed as a jog, the slower of the two drains.
		push_error("StaminaFlow.band_for_speed: jog_speed %f is not above walk_speed %f"
				% [jog_speed, walk_speed])
		return Unit.GAIT_WALK if speed <= walk_speed else Unit.GAIT_JOG
	if speed <= (walk_speed + jog_speed) * 0.5:
		return Unit.GAIT_WALK
	# The sprint boundary is the same half-step above the jog pace that the walk/jog
	# boundary sits below it, so the jog band is symmetric about jog_speed.
	if speed <= jog_speed + (jog_speed - walk_speed) * 0.5:
		return Unit.GAIT_JOG
	return Unit.GAIT_SPRINT


## Signed stamina change per second for a band: positive regenerates, negative drains.
## The four rates are the caller's own (Unit.stamina_rest_regen_per_s and siblings), so a
## loadout or a test can retune any of them independently.
static func flow_per_s(band: int, rest_regen_per_s: float, walk_regen_per_s: float,
		jog_drain_per_s: float, sprint_drain_per_s: float) -> float:
	match band:
		BAND_REST:
			return rest_regen_per_s
		Unit.GAIT_WALK:
			return walk_regen_per_s
		Unit.GAIT_JOG:
			return -jog_drain_per_s
		Unit.GAIT_SPRINT:
			return -sprint_drain_per_s
		_:
			# RUN is a distance-gated jog/sprint blend with no pace of its own (Unit._move_to),
			# so it never reaches here as a band; any other value is a caller error, and
			# charging nothing keeps the pool inspectable rather than silently draining.
			push_error("StaminaFlow.flow_per_s: unknown band %d" % band)
			return 0.0


## One tick of flow applied to a pool: `stamina + flow * delta`, clamped to [0, max].
static func apply(stamina: float, flow_per_second: float, delta: float, max_stamina: float) -> float:
	return clampf(stamina + flow_per_second * delta, 0.0, max_stamina)
