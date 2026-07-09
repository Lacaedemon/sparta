extends GutTest

## Test that the relief separation exemption clears only when the pair has moved
## sufficiently apart — confirming soldiers are no longer interpenetrating when
## steering forces resume.
##
## This test was written to investigate issue #682 (chaotic entity swirling during
## line relief). The hypothesis: the current 24px buffer in UnitRelief.update()
## clears the exemption before soldiers are fully separated, causing steering
## reversals when separation forces kick in.

var battle: Battle
var unit_a: Unit
var unit_b: Unit

func before_each() -> void:
	battle = add_child_autofree(load("res://scenes/Battle.tscn").instantiate())
	Replay.forced_seed = 12345
	battle.add_child_autofree(GUT_SIGNAL_WATCHER)
	await gut.wait_frames(1)  # Let Battle._ready() complete

	# Spawn two units side by side
	unit_a = battle._spawn_unit(0, Battle.UnitType.INFANTRY, 400.0, 300.0, Battle.Formation.NORMAL)
	unit_b = battle._spawn_unit(0, Battle.UnitType.INFANTRY, 500.0, 300.0, Battle.Formation.NORMAL)

	# Verify they spawned correctly
	assert_true(is_instance_valid(unit_a), "Unit A should be spawned")
	assert_true(is_instance_valid(unit_b), "Unit B should be spawned")
	assert_true(unit_a.soldiers > 0, "Unit A should have soldiers")
	assert_true(unit_b.soldiers > 0, "Unit B should have soldiers")

func test_relief_exemption_clears_with_separation() -> void:
	## Verify that once separation exemption clears, the pair is actually apart.

	# Start a relief: unit_a takes over unit_b (the tired unit)
	var relief_order := Order.new_relief(unit_b)
	unit_a.enqueue_order(relief_order)

	# Advance unit_a toward unit_b to close the gap
	var engage_order := Order.new_move(unit_b.position)
	# (relief order is the current one; engage is queued behind it)
	unit_a.enqueue_order(engage_order)

	# Let the relief begin
	await gut.wait_frames(1)
	var relief_started := unit_a.current_order != null and unit_a.current_order.type == Order.Type.RELIEF
	assert_true(relief_started, "Relief order should be current on unit_a")

	# The exemption should be armed
	var exemption_armed := unit_a.current_order.relief_partner == unit_b
	assert_true(exemption_armed, "Relief exemption should be armed")

	# Record the initial separation distance
	var initial_distance := unit_a.position.distance_to(unit_b.position)

	# Let them move for a while (advancing + retreating)
	# Unit A advances toward unit B; unit B retreats. Eventually they should separate.
	var max_ticks = 500
	var exemption_cleared_at_tick: int = -1
	var distance_at_clear: float = -1.0

	for tick in range(max_ticks):
		await gut.wait_frames(1)

		# Check if exemption has cleared
		if unit_a.current_order == null or unit_a.current_order.relief_partner == null:
			exemption_cleared_at_tick = tick
			distance_at_clear = unit_a.position.distance_to(unit_b.position)
			break

	# The exemption should have cleared (relief completed)
	assert_ne(exemption_cleared_at_tick, -1, "Relief exemption should eventually clear")

	# At the moment exemption cleared, they should be far enough apart that
	# no soldiers are interpenetrating. The sum of separation radii is roughly:
	# infantry_separation_radius (~45) + infantry_separation_radius (~45) = 90px
	# Current buffer (24px) means exemption clears at center distance ~114px
	# With that buffer, soldiers can still overlap significantly.
	#
	# A safer buffer (e.g. 240px) would clear at ~330px, ensuring clean separation.
	# This test passes with either buffer, but documents the concern: if swirling
	# occurs right after exemption clears, the buffer is suspect.

	assert_gt(distance_at_clear, unit_a.separation_radius + unit_b.separation_radius,
		"Units should be center-distance apart by at least their separation radii when exemption clears")

	# Log the actual distance for investigation
	var buffer_used = distance_at_clear - (unit_a.separation_radius + unit_b.separation_radius)
	gut.p("Exemption cleared at center distance: %.1f (buffer over radii: %.1f)" % [distance_at_clear, buffer_used])

func test_relief_interruptible_on_dead() -> void:
	## Verify that relief exemption clears immediately if the partner dies/routs.

	var relief_order := Order.new_relief(unit_b)
	unit_a.enqueue_order(relief_order)

	await gut.wait_frames(1)
	assert_true(unit_a.current_order.relief_partner == unit_b, "Relief should be armed")

	# Kill the partner mid-relief
	unit_b.state = Unit.State.DEAD

	# Update should clear the exemption
	UnitRelief.update(unit_a)

	assert_null(unit_a.current_order.relief_partner, "Exemption should clear when partner dies")

func test_self_relief_refused() -> void:
	## Verify that a unit can't relieve itself (no-op).

	var relief_order := Order.new_relief(unit_a)
	UnitRelief.begin(unit_a, unit_a, relief_order)

	# The exemption should not arm
	assert_null(relief_order.relief_partner, "Self-relief should not arm exemption")
