class_name SoldierCollision
## Newton's laws collision physics for individual soldiers. Per-soldier bodies collide
## bidirectionally (F = -F') with force magnitude inversely proportional to mass. Bracing
## and motion state affect friction: a moving body's kinetic friction damping is stronger
## the closer it is to rest (SoldierCombat.KINETIC_FRICTION_STATIONARY_BOOST). A separate
## static-friction gate (overcomes_static_friction below) is implemented and tested but not
## yet called from any production path -- wiring it into the melee/collision impulse path
## so a resting body can fully resist a sub-threshold shove is tracked as a follow-up. See
## SoldierCombat.gd for the friction model constants.
##
## Pure functions, no state, testable in isolation (like SoldierCombat.gd).
## Called from: SoldierMelee.gd (bidirectional impulse split on strikes),
## SoldierBodies.gd (kinetic friction damping each frame).


## Calculate the bidirectional impulse split when two soldiers collide or exchange a strike.
## Returns [impulse_attacker, impulse_defender] (Vector2 pair): VELOCITY deltas (the caller
## adds them straight to _sim_body_vel via SoldierCombat.capped_knockback_velocity), not raw
## momentum -- attacker recoils backward along the strike axis, defender is shoved forward.
##
## Splits a fixed total momentum P = impulse_magnitude * mu (mu the reduced mass
## m_a_eff*m_d_eff/(m_a_eff+m_d_eff)) between the two bodies via each one's own effective
## mass: delta_v = P / m_eff. Equivalently (and how it's actually computed below, avoiding
## an intermediate reduced-mass term): j_a = impulse_magnitude * m_d_eff / total_mass,
## j_d = impulse_magnitude * m_a_eff / total_mass. This is the standard 1D-collision
## momentum split and it conserves TRUE momentum for any mass/bracing combination:
## m_a_eff * j_a == m_d_eff * j_d always (both equal P), so the mass-weighted momentum
## vectors (m_a_eff * impulse_attacker + m_d_eff * impulse_defender) sum to zero -- NOT the
## bare velocity vectors, which are unequal in magnitude whenever the effective masses
## differ (that's the whole point: a heavier/braced body gets a smaller velocity delta from
## the same momentum). Reduces to an even j_a == j_d split when the effective masses match.
##
## Args:
##   impulse_magnitude: the total impulse from the strike (force * duration)
##   strike_axis: unit vector from attacker toward defender (direction of the strike)
##   attacker_mass: mass of the attacking soldier
##   attacker_brace: bracing value of the attacker (0 = unbraced, 1 = full brace)
##   defender_mass: mass of the defending soldier
##   defender_brace: bracing value of the defender
##
## Returns: [impulse_attacker, impulse_defender] where impulse_attacker is opposite
## the strike_axis and impulse_defender is along it. Caller applies these to velocities.
static func bidirectional_impulse(
	impulse_magnitude: float,
	strike_axis: Vector2,
	attacker_mass: float,
	attacker_brace: float,
	defender_mass: float,
	defender_brace: float
) -> Array:
	# Effective mass includes bracing: m_eff = m * (1 + k_br * br)
	# Higher bracing = higher inertia = harder to move.
	var m_a_eff: float = attacker_mass * (1.0 + SoldierCombat.FRICTION_BRACING_MULTIPLIER * attacker_brace)
	var m_d_eff: float = defender_mass * (1.0 + SoldierCombat.FRICTION_BRACING_MULTIPLIER * defender_brace)

	# Split a fixed total momentum P = impulse_magnitude * mu (mu = reduced mass) between the
	# two bodies via each one's own effective mass (delta_v = P / m_eff), computed directly as
	# j_a = P/m_a_eff = impulse_magnitude * m_d_eff / total_mass (and symmetrically for j_d) --
	# this is Newton's third law (equal and opposite MOMENTUM, m_a_eff*j_a == m_d_eff*j_d),
	# not an equal split of the velocity deltas themselves.
	var total_mass: float = m_a_eff + m_d_eff
	if total_mass < 0.01:
		total_mass = 0.01  # Guard against div-by-zero
	var j_a: float = impulse_magnitude * m_d_eff / total_mass
	var j_d: float = impulse_magnitude * m_a_eff / total_mass

	# Attacker recoils backward (opposite the strike axis)
	var impulse_attacker: Vector2 = -strike_axis * j_a
	# Defender is shoved forward (along the strike axis)
	var impulse_defender: Vector2 = strike_axis * j_d

	return [impulse_attacker, impulse_defender]


## Scale a defender's bidirectional-impulse component by how much of the strike survives
## bracing absorption. `received` is the surplus impulse magnitude above the defender's file
## brace capacity (SoldierCombat.brace_capacity) -- 0 at or below capacity, rising toward
## `impulse_magnitude` as the strike overwhelms it. Scaling `impulse_defender` by the ratio
## received/impulse_magnitude (rather than gating on `received > 0` and applying it at full
## magnitude) makes the defender's shove grow smoothly from zero at the capacity threshold,
## instead of jumping straight to the full momentum-split impulse the instant the strike
## crosses it. Does not touch the attacker's own recoil -- bracing absorbs the defender's
## motion, not the attacker's.
##
## Args:
##   impulse_defender: the defender's raw impulse from bidirectional_impulse (impulses[1])
##   received: the surplus impulse magnitude above brace capacity (0 if fully absorbed)
##   impulse_magnitude: the strike's total impulse magnitude (bidirectional_impulse's own
##     first argument) -- the denominator of the surviving fraction
##
## Returns: impulse_defender scaled by received/impulse_magnitude, or Vector2.ZERO if
## impulse_magnitude is negligible (guards div-by-zero; there is nothing to scale).
static func braced_defender_impulse(
	impulse_defender: Vector2,
	received: float,
	impulse_magnitude: float
) -> Vector2:
	if impulse_magnitude < 0.01:
		return Vector2.ZERO
	return impulse_defender * (received / impulse_magnitude)


## Check if an impulse overcomes a stationary body's static friction and initiates motion.
## A standing body (v ≈ 0) has a friction threshold that must be exceeded to start moving;
## a moving body (v > SoldierCombat.STATIC_FRICTION_VELOCITY_GATE) experiences kinetic
## friction instead, with no threshold gate. Returns true if the impulse should move the
## body, false if static friction absorbs it.
##
## Args:
##   impulse_magnitude: magnitude of the applied impulse
##   body_velocity_magnitude: current speed of the body (0 = stationary)
##   mass: mass of the soldier
##   brace: bracing value (0 = unbraced)
##
## Returns: true if the body should move, false if static friction holds it in place.
static func overcomes_static_friction(
	impulse_magnitude: float,
	body_velocity_magnitude: float,
	mass: float,
	brace: float
) -> bool:
	# If already moving, static friction doesn't gate further motion (kinetic friction only).
	if body_velocity_magnitude > SoldierCombat.STATIC_FRICTION_VELOCITY_GATE:
		return true

	# Standing body: compare impulse against effective-mass-scaled threshold.
	var m_eff: float = mass * (1.0 + SoldierCombat.FRICTION_BRACING_MULTIPLIER * brace)
	var threshold: float = SoldierCombat.STATIC_FRICTION_THRESHOLD * m_eff
	return impulse_magnitude > threshold


## Apply kinetic friction damping to a body's velocity (exponential decay per frame).
## A moving body decelerates due to ground friction: v_new = v * (1 - friction_factor * delta).
## The friction factor depends on motion state: stationary/slow bodies (v < v_ref) experience
## higher friction ("static friction" regime), while fast bodies (v >= v_ref) experience
## lower friction ("kinetic friction" regime). Lighter bodies also decelerate faster
## (high friction_factor / mass ratio), reflecting higher surface-area-to-mass drag.
##
## Args:
##   current_velocity: the body's velocity vector (world units/sec)
##   mass: mass of the soldier
##   brace: bracing value (0 = unbraced; affects friction only indirectly via mass)
##   delta: time step (seconds)
##
## Returns: the new velocity after friction damping is applied.
static func apply_kinetic_friction(
	current_velocity: Vector2,
	mass: float,
	brace: float,
	delta: float
) -> Vector2:
	var v_mag: float = current_velocity.length()
	if v_mag < 0.01:
		return Vector2.ZERO  # Already stopped

	# Friction damping: base + stationary_boost * (1 - min(v / v_ref, 1))
	# At v=0 (stationary): f = base + boost
	# At v >= v_ref (mobile): f = base (minimal extra friction)
	var velocity_fraction: float = minf(1.0, v_mag / SoldierCombat.KINETIC_FRICTION_VELOCITY_REFERENCE)
	var friction_factor: float = SoldierCombat.KINETIC_FRICTION_DAMPING \
		+ SoldierCombat.KINETIC_FRICTION_STATIONARY_BOOST * (1.0 - velocity_fraction)

	# Scale friction by inverse mass: lighter bodies decelerate faster
	# (high inertia / low friction effect for heavy bodies).
	var mass_scale: float = 1.0 / maxf(0.01, mass)
	friction_factor *= mass_scale

	# Apply per-tick damping: v_new = v * (1 - friction * delta)
	# Clamp damping to not over-damp in a single tick (friction * delta shouldn't exceed 1).
	var damping: float = minf(1.0, friction_factor * delta)
	return current_velocity * (1.0 - damping)
