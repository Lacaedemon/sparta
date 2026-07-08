extends GutTest
## Default battle spawn line: adjacent units' formation blocks must never overlap in
## world space, regardless of each type's soldier count / formation density (issue #677
## -- a flat 150-world-unit spacing let the standard loadout's wide LOOSE-order Archers
## regiment overlap its Infantry neighbour by ~21 world units). Verified against the
## actual formation geometry (UnitFormation.half_width_for_soldiers), not by eyeballing
## a render -- see the "Verify maneuvers/soldier bodies tick by tick" memory.


func test_default_line_units_do_not_overlap() -> void:
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame   # one tick to let _spawn_line run

	var team0: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit: Unit = node as Unit
		if unit != null and unit.team == 0:
			team0.append(unit)
	team0.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.x < b.position.x)

	assert_gt(team0.size(), 1,
			"expected the standard multi-unit default line to be spawned")

	for i in range(team0.size() - 1):
		var a: Unit = team0[i]
		var b: Unit = team0[i + 1]
		var half_a: float = UnitFormation.half_width_for_soldiers(
				a.max_soldiers, Unit.FORMATION_SPACING * a.spacing_scale)
		var half_b: float = UnitFormation.half_width_for_soldiers(
				b.max_soldiers, Unit.FORMATION_SPACING * b.spacing_scale)
		var gap: float = b.position.x - a.position.x
		assert_gt(gap, half_a + half_b,
				"%s (half-width %.1f) and %s (half-width %.1f) overlap: centre gap %.1f" %
				[a.unit_name, half_a, b.unit_name, half_b, gap])


func test_half_width_helper_matches_known_issue_measurements() -> void:
	# Pure-function regression pinned to the issue's own reported bbox widths (measured via
	# a direct state dump, not eyeballed): Spearmen 135.0, Infantry 126.1 (rounds to 126.0
	# from pure geometry -- the reported figure includes per-soldier jitter), Archers 216.1,
	# Cavalry 99.1/99.0. Confirms half_width_for_soldiers (and its spacing_scale_for_mode
	# input) reproduce the exact widths that motivated the fix, not just "some" width.
	var spacing := func(mode: int) -> float:
		return Unit.FORMATION_SPACING * Unit.spacing_scale_for_mode(mode)

	assert_almost_eq(
			2.0 * UnitFormation.half_width_for_soldiers(140, spacing.call(Unit.FORMATION_TIGHT)),
			135.0, 0.01, "Spearmen (140, TIGHT) width")
	assert_almost_eq(
			2.0 * UnitFormation.half_width_for_soldiers(120, spacing.call(Unit.FORMATION_NORMAL)),
			126.0, 0.01, "Infantry (120, NORMAL) width")
	assert_almost_eq(
			2.0 * UnitFormation.half_width_for_soldiers(90, spacing.call(Unit.FORMATION_LOOSE)),
			216.0, 0.01, "Archers (90, LOOSE) width")
	assert_almost_eq(
			2.0 * UnitFormation.half_width_for_soldiers(80, spacing.call(Unit.FORMATION_NORMAL)),
			99.0, 0.01, "Cavalry (80, NORMAL) width")
