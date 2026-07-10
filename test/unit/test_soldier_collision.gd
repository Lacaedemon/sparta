extends GutTest
## Unit tests for SoldierCollision.gd: bidirectional impulse splitting,
## static/kinetic friction, and momentum conservation. Pure functions, no live nodes.

# Test data: common unit types and their mass profiles
const CAVALRY_MASS: float = 2.5
const ANTI_CAVALRY_MASS: float = 1.0
const ARCHER_MASS: float = 0.9
const INFANTRY_MASS: float = 1.0

# Friction constants (from SoldierCombat.gd)
const FRICTION_BRACING_MULTIPLIER: float = 0.5
const STATIC_FRICTION_THRESHOLD: float = 20.0
const KINETIC_FRICTION_DAMPING: float = 0.08
const KINETIC_FRICTION_VELOCITY_REFERENCE: float = 50.0
const KINETIC_FRICTION_STATIONARY_BOOST: float = 0.03


func test_bidirectional_impulse_equal_mass_equal_split():
	## Two soldiers of equal mass and no bracing should split impulse 50/50.
	var impulse_mag: float = 60.0
	var strike_axis: Vector2 = Vector2.RIGHT
	var mass_a: float = 1.0
	var mass_b: float = 1.0
	var brace_a: float = 0.0
	var brace_b: float = 0.0

	var result: Array = SoldierCollision.bidirectional_impulse(
		impulse_mag, strike_axis, mass_a, brace_a, mass_b, brace_b)
	var impulse_a: Vector2 = result[0]
	var impulse_b: Vector2 = result[1]

	# Each should get 30 units of force (half the total)
	assert_almost_eq(impulse_a.length(), 30.0, 0.1, "Attacker recoil should be 30 (half)")
	assert_almost_eq(impulse_b.length(), 30.0, 0.1, "Defender shove should be 30 (half)")

	# Directions should be opposite
	assert_almost_eq(impulse_a.x, -30.0, 0.1, "Attacker recoil is backward (neg)")
	assert_almost_eq(impulse_b.x, 30.0, 0.1, "Defender shove is forward (pos)")

	# Momentum should be conserved: impulse_a + impulse_b = 0
	var momentum: Vector2 = impulse_a + impulse_b
	assert_almost_eq(momentum.length(), 0.0, 0.1, "Momentum is conserved")


func test_bidirectional_impulse_heavy_attacker_vs_light_defender():
	## Heavy attacker vs. light defender: attacker barely recoils, defender heavily shoved.
	## impulse_attacker/impulse_defender are VELOCITY deltas (the caller adds them straight
	## to _sim_body_vel), so equal-and-opposite MOMENTUM (Newton's third law) means
	## mass_a * impulse_a + mass_b * impulse_b == 0, not impulse_a + impulse_b == 0 --
	## the velocity deltas themselves are inversely proportional to mass, by design.
	var impulse_mag: float = 60.0
	var strike_axis: Vector2 = Vector2.RIGHT
	var mass_a: float = CAVALRY_MASS  # 2.5 (heavy)
	var mass_b: float = ARCHER_MASS   # 0.9 (light)
	var brace_a: float = 0.0
	var brace_b: float = 0.0

	var result: Array = SoldierCollision.bidirectional_impulse(
		impulse_mag, strike_axis, mass_a, brace_a, mass_b, brace_b)
	var impulse_a: Vector2 = result[0]
	var impulse_b: Vector2 = result[1]

	# Heavy cavalry recoils less, light archer is shoved more
	assert_lt(impulse_a.length(), impulse_b.length(),
		"Heavy attacker should recoil less than light defender is shoved")

	# True momentum (mass * velocity delta) is conserved, not the bare velocity deltas.
	var momentum: Vector2 = mass_a * impulse_a + mass_b * impulse_b
	assert_almost_eq(momentum.length(), 0.0, 0.1, "Momentum (mass * velocity delta) is conserved")


func test_bidirectional_impulse_light_attacker_vs_heavy_defender():
	## Light attacker vs. heavy defender: attacker rebounds hard, defender barely shoved.
	var impulse_mag: float = 60.0
	var strike_axis: Vector2 = Vector2.RIGHT
	var mass_a: float = ARCHER_MASS       # 0.9 (light)
	var mass_b: float = CAVALRY_MASS      # 2.5 (heavy)
	var brace_a: float = 0.0
	var brace_b: float = 0.0

	var result: Array = SoldierCollision.bidirectional_impulse(
		impulse_mag, strike_axis, mass_a, brace_a, mass_b, brace_b)
	var impulse_a: Vector2 = result[0]
	var impulse_b: Vector2 = result[1]

	# Light archer recoils hard, heavy cavalry barely shoved
	assert_gt(impulse_a.length(), impulse_b.length(),
		"Light attacker should recoil more than heavy defender is shoved")

	# True momentum (mass * velocity delta) is conserved, not the bare velocity deltas.
	var momentum: Vector2 = mass_a * impulse_a + mass_b * impulse_b
	assert_almost_eq(momentum.length(), 0.0, 0.1, "Momentum (mass * velocity delta) is conserved")


func test_bidirectional_impulse_bracing_raises_effective_mass():
	## Bracing increases effective mass: a braced defender imparts more recoil to the attacker.
	var impulse_mag: float = 60.0
	var strike_axis: Vector2 = Vector2.RIGHT
	var mass_a: float = 1.0
	var mass_b: float = 1.0
	var brace_a: float = 0.0
	var brace_b_unbraced: float = 0.0
	var brace_b_braced: float = 1.0

	# Unbraced defender
	var result_unbraced: Array = SoldierCollision.bidirectional_impulse(
		impulse_mag, strike_axis, mass_a, brace_a, mass_b, brace_b_unbraced)
	var impulse_a_unbraced: Vector2 = result_unbraced[0]

	# Braced defender
	var result_braced: Array = SoldierCollision.bidirectional_impulse(
		impulse_mag, strike_axis, mass_a, brace_a, mass_b, brace_b_braced)
	var impulse_a_braced: Vector2 = result_braced[0]

	# Braced defender imparts more recoil to attacker (larger magnitude)
	assert_gt(impulse_a_braced.length(), impulse_a_unbraced.length(),
		"Braced defender should impart more recoil")


func test_kinetic_friction_moving_body_decelerates():
	## A moving body decelerates due to kinetic friction: v_new < v_old.
	var velocity: Vector2 = Vector2(50.0, 0.0)  # moving at 50 u/s
	var mass: float = 1.0
	var brace: float = 0.0
	var delta: float = 1.0 / 60.0  # one frame

	var new_vel: Vector2 = SoldierCollision.apply_kinetic_friction(velocity, mass, brace, delta)

	# Should be slower than before
	assert_lt(new_vel.length(), velocity.length(), "Velocity should decrease due to friction")
	# Should still be in the same direction
	assert_almost_eq(new_vel.angle(), velocity.angle(), 0.01, "Direction should be unchanged")


func test_kinetic_friction_stationary_body_stays_put():
	## A stationary body with v < epsilon should remain at rest.
	var velocity: Vector2 = Vector2(0.001, 0.0)  # tiny movement
	var mass: float = 1.0
	var brace: float = 0.0
	var delta: float = 1.0 / 60.0

	var new_vel: Vector2 = SoldierCollision.apply_kinetic_friction(velocity, mass, brace, delta)

	# Should be zero (or nearly)
	assert_almost_eq(new_vel.length(), 0.0, 0.001, "Stationary body should remain at rest")


func test_kinetic_friction_light_body_decelerates_faster():
	## Lighter bodies decelerate faster: friction_factor *= 1/mass.
	var velocity: Vector2 = Vector2(50.0, 0.0)
	var mass_light: float = 0.5
	var mass_heavy: float = 2.0
	var brace: float = 0.0
	var delta: float = 1.0 / 60.0

	var new_vel_light: Vector2 = SoldierCollision.apply_kinetic_friction(velocity, mass_light, brace, delta)
	var new_vel_heavy: Vector2 = SoldierCollision.apply_kinetic_friction(velocity, mass_heavy, brace, delta)

	# Light body should slow more than heavy body
	assert_lt(new_vel_light.length(), new_vel_heavy.length(),
		"Light body should decelerate faster than heavy body")


func test_kinetic_friction_slow_body_decelerates_faster():
	## Stationary/slow bodies experience higher friction (static friction regime).
	var mass: float = 1.0
	var brace: float = 0.0
	var delta: float = 1.0 / 60.0

	# Slow velocity (below v_ref = 50)
	var velocity_slow: Vector2 = Vector2(5.0, 0.0)
	var new_vel_slow: Vector2 = SoldierCollision.apply_kinetic_friction(velocity_slow, mass, brace, delta)

	# Fast velocity (above v_ref = 50)
	var velocity_fast: Vector2 = Vector2(150.0, 0.0)
	var new_vel_fast: Vector2 = SoldierCollision.apply_kinetic_friction(velocity_fast, mass, brace, delta)

	# Slow body should lose a larger fraction of its speed
	var frac_slow: float = (velocity_slow.length() - new_vel_slow.length()) / velocity_slow.length()
	var frac_fast: float = (velocity_fast.length() - new_vel_fast.length()) / velocity_fast.length()

	assert_gt(frac_slow, frac_fast,
		"Slow body should lose a larger speed fraction than fast body (higher friction)")


func test_static_friction_threshold():
	## A stationary body below the threshold doesn't move; above it, it does.
	var mass: float = 1.0
	var brace: float = 0.0
	var body_vel_stationary: float = 0.5  # v < v_ref

	# Below threshold: static friction holds
	var impulse_below: float = STATIC_FRICTION_THRESHOLD * mass - 5.0
	var moves_below: bool = SoldierCollision.overcomes_static_friction(
		impulse_below, body_vel_stationary, mass, brace)
	assert_false(moves_below, "Sub-threshold impulse should not overcome static friction")

	# Above threshold: body moves
	var impulse_above: float = STATIC_FRICTION_THRESHOLD * mass + 5.0
	var moves_above: bool = SoldierCollision.overcomes_static_friction(
		impulse_above, body_vel_stationary, mass, brace)
	assert_true(moves_above, "Super-threshold impulse should overcome static friction")


func test_static_friction_moving_body_no_threshold():
	## A moving body (v > threshold) should always move, no static friction gate.
	var mass: float = 1.0
	var brace: float = 0.0
	var body_vel_moving: float = 10.0  # v > v_ref

	# Even a tiny impulse should move a moving body (kinetic friction only)
	var impulse_tiny: float = 1.0
	var moves: bool = SoldierCollision.overcomes_static_friction(
		impulse_tiny, body_vel_moving, mass, brace)
	assert_true(moves, "Moving body should always move (kinetic friction, no threshold)")


func test_static_friction_bracing_raises_threshold():
	## Bracing raises the static friction threshold: harder to initiate motion.
	var mass: float = 1.0
	var body_vel: float = 0.5
	var impulse: float = STATIC_FRICTION_THRESHOLD * mass + 5.0

	# Unbraced
	var moves_unbraced: bool = SoldierCollision.overcomes_static_friction(
		impulse, body_vel, mass, 0.0)
	assert_true(moves_unbraced, "Unbraced body should move with this impulse")

	# Braced (with max brace = 1.0)
	var moves_braced: bool = SoldierCollision.overcomes_static_friction(
		impulse, body_vel, mass, 1.0)
	assert_false(moves_braced, "Braced body should resist this impulse (higher threshold)")


# --- braced_defender_impulse: no discontinuity at the brace-capacity threshold ------------

func test_braced_defender_impulse_zero_at_or_below_capacity():
	## At or below the brace capacity, `received` is 0 -- the defender gets no shove at all,
	## matching the "absorbed" case (this is also what the `received > 0.0` gate in
	## SoldierMelee.gd already skips, but the function itself should still return zero here).
	var impulse_defender := Vector2(0.0, 20.0)
	var result: Vector2 = SoldierCollision.braced_defender_impulse(impulse_defender, 0.0, 50.0)
	assert_eq(result, Vector2.ZERO, "no surviving impulse means no shove")


func test_braced_defender_impulse_grows_smoothly_from_the_capacity_threshold():
	## The bug this fixes: applying `impulse_defender` at FULL magnitude the instant
	## impulse_magnitude clears `cap` would jump straight from ~0 to the full mass-split
	## shove. Scaling by received/impulse_magnitude instead means the shove magnitude is
	## small just above the threshold and grows continuously as the strike overwhelms the
	## brace further -- never a jump to the unscaled impulse_defender magnitude.
	var cap: float = 50.0
	var impulse_defender := Vector2(0.0, 20.0)  # the mass-split defender share, at some impulse_magnitude

	# Just above cap: received is tiny, so the applied shove should be tiny too.
	var impulse_mag_just_above: float = cap + 0.01
	var received_just_above: float = impulse_mag_just_above - cap
	var result_just_above: Vector2 = SoldierCollision.braced_defender_impulse(
		impulse_defender, received_just_above, impulse_mag_just_above)
	assert_lt(result_just_above.length(), 0.01,
		"just above the brace-capacity threshold, the defender's shove should be near zero, not the full mass-split impulse")

	# Well above cap: received is most of impulse_magnitude, so the shove approaches (but
	# never reaches or exceeds) the unscaled impulse_defender magnitude.
	var impulse_mag_well_above: float = cap * 100.0
	var received_well_above: float = impulse_mag_well_above - cap
	var result_well_above: Vector2 = SoldierCollision.braced_defender_impulse(
		impulse_defender, received_well_above, impulse_mag_well_above)
	assert_almost_eq(result_well_above.y, impulse_defender.y, 0.5,
		"far above the brace-capacity threshold, the shove should approach the full mass-split impulse")
	assert_lte(result_well_above.length(), impulse_defender.length(),
		"the scaled shove should never exceed the unscaled mass-split impulse")

	# Monotonic: a strike further above cap yields a larger (or equal) shove than one just
	# above cap -- growth, not a jump followed by a plateau or reversal.
	assert_gt(result_well_above.length(), result_just_above.length(),
		"the shove should grow as the strike overwhelms the brace capacity further")


func test_braced_defender_impulse_guards_zero_impulse_magnitude():
	## Degenerate case: impulse_magnitude ~ 0 (nothing to scale by) returns zero rather than
	## dividing by ~zero.
	var result: Vector2 = SoldierCollision.braced_defender_impulse(Vector2(0.0, 20.0), 0.0, 0.0)
	assert_eq(result, Vector2.ZERO, "zero impulse magnitude guards against div-by-zero")
