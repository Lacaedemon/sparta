extends GutTest
## Default battle spawn line: adjacent units' formation blocks must never overlap in
## world space, regardless of each type's soldier count / formation density -- a flat
## 150-world-unit spacing let the standard loadout's wide LOOSE-order Archers
## regiment overlap its Infantry neighbour by ~21 world units. Verified against the
## actual formation geometry (UnitFormation.half_width_for_soldiers), not by eyeballing
## a render -- see the "Verify maneuvers/soldier bodies tick by tick" memory.
##
## Also guards the no-overlap fix's own follow-up finding: the no-overlap gap alone makes
## no promise about the TOTAL line width, so a max-size campaign stack
## (CampaignBattle.MAX_UNITS) can need more room than Battle.FIELD has -- pushing the outer
## units off the playable field -- unless the gaps are scaled back down to fit.

const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")


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
				a.max_soldiers, a.file_pitch_wu())
		var half_b: float = UnitFormation.half_width_for_soldiers(
				b.max_soldiers, b.file_pitch_wu())
		var gap: float = b.position.x - a.position.x
		assert_gt(gap, half_a + half_b,
				"%s (half-width %.1f) and %s (half-width %.1f) overlap: centre gap %.1f" %
				[a.unit_name, half_a, b.unit_name, half_b, gap])


func test_max_campaign_stack_stays_within_field() -> void:
	# At CampaignBattle.MAX_UNITS (12), cycling the standard 5-archetype loadout
	# twice-plus needs a no-overlap-gap sum of ~1620.6 world units -- wider than
	# Battle.FIELD's own spawn budget (FIELD.size.x - 200 == 1400) -- so simply taking
	# every pair's no-overlap minimum (as test_default_line_units_do_not_overlap alone
	# would allow) pushes the outer units off the field entirely. Confirms the line is
	# instead scaled back down to fit within FIELD, at the cost of the no-overlap
	# guarantee ONLY in this rare high-count extreme (unlike the standard 5v5 case
	# above, which the fallback must leave untouched).
	CampaignBattle.clear()
	CampaignBattle.active = true
	CampaignBattle.pending = {
		"attacker_strength": CampaignBattle.MAX_UNITS,
		"defender_strength": 1,
	}

	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame   # one tick to let _spawn_line run

	CampaignBattle.clear()   # drop the static hand-off before it leaks into a later test

	var team0: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("units"):
		var unit: Unit = node as Unit
		if unit != null and unit.team == 0:
			team0.append(unit)
	team0.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.x < b.position.x)

	assert_eq(team0.size(), CampaignBattle.MAX_UNITS,
			"expected the max-size campaign stack to spawn all %d units" %
			CampaignBattle.MAX_UNITS)
	if team0.size() != CampaignBattle.MAX_UNITS:
		return

	var leftmost: Unit = team0[0]
	var rightmost: Unit = team0[team0.size() - 1]
	var half_left: float = UnitFormation.half_width_for_soldiers(
			leftmost.max_soldiers, leftmost.file_pitch_wu())
	var half_right: float = UnitFormation.half_width_for_soldiers(
			rightmost.max_soldiers, rightmost.file_pitch_wu())

	var left_edge: float = leftmost.position.x - half_left
	var right_edge: float = rightmost.position.x + half_right
	var field_min: float = battle.FIELD.position.x
	var field_max: float = battle.FIELD.position.x + battle.FIELD.size.x

	assert_true(left_edge >= field_min and left_edge <= field_max,
			"leftmost unit's formation block spills outside FIELD's left edge at x=%.1f (FIELD [%.1f, %.1f])" %
			[left_edge, field_min, field_max])
	assert_true(right_edge >= field_min and right_edge <= field_max,
			"rightmost unit's formation block spills outside FIELD's right edge at x=%.1f (FIELD [%.1f, %.1f])" %
			[right_edge, field_min, field_max])


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
	# Historical pin: the cavalry row reproduces the issue's measurement at the FOOT
	# pitch it used then. Cavalry has since moved to its own wider file pitch, so its
	# live width is pinned separately below with the real pitch as input.
	assert_almost_eq(
			2.0 * UnitFormation.half_width_for_soldiers(80, spacing.call(Unit.FORMATION_NORMAL)),
			99.0, 0.01, "Cavalry (80, NORMAL) width at the foot pitch")


func test_cavalry_grid_pitch_reaches_the_live_units_bit_exactly() -> void:
	# The loadout's metric pitch fields must reach the spawned units exactly: cavalry
	# authors 1.0 m between files and 3.0 m between ranks (riding room side-to-side
	# and nose-to-tail); foot rows omit the fields and fall back to close order on
	# both axes. Bit-exact equality, per the units convention's pin-test rule.
	var battle: Node = load("res://scenes/Battle.tscn").instantiate()
	add_child_autofree(battle)
	await get_tree().physics_frame   # one tick to let _spawn_line run

	var saw_cavalry := false
	var saw_foot := false
	for node in get_tree().get_nodes_in_group("units"):
		var u: Unit = node as Unit
		if u == null:
			continue
		if u.is_cavalry:
			saw_cavalry = true
			assert_eq(u.file_pitch, 1.0 * WorldScale.WU_PER_M,
					"%s file pitch should be 1.0 m in wu" % u.unit_name)
			assert_eq(u.rank_pitch, 3.0 * WorldScale.WU_PER_M,
					"%s rank pitch should be 3.0 m in wu" % u.unit_name)
		else:
			saw_foot = true
			assert_eq(u.file_pitch, Unit.FORMATION_SPACING,
					"%s file pitch should stay at close order" % u.unit_name)
			assert_eq(u.rank_pitch, Unit.FORMATION_SPACING,
					"%s rank pitch should stay at close order" % u.unit_name)
	assert_true(saw_cavalry and saw_foot,
			"default line should include both cavalry and foot units")


func test_cavalry_formation_width_uses_its_own_file_pitch() -> void:
	# 80 cavalry at Normal order form 12 files; at the 1.0 m file pitch the block
	# spans (12-1) * 20 = 220 world units -- the realistic frontage that motivated
	# the per-type pitch, more than double the foot-pitch width pinned above.
	assert_almost_eq(
			2.0 * UnitFormation.half_width_for_soldiers(80,
					1.0 * WorldScale.WU_PER_M * Unit.spacing_scale_for_mode(Unit.FORMATION_NORMAL)),
			220.0, 0.01, "Cavalry (80, NORMAL) width at its own file pitch")
