extends GutTest
## Exact-value pins for every constant the metric-definition migration converts
## from a bare world-unit literal to a parse-time-folded metric expression
## (docs/units-convention.md). Written and committed BEFORE the initializers
## were swapped, against the original wu literals, so a conversion that is not
## bit-identical fails here rather than silently changing the simulation.
## Exact assert_eq throughout -- never assert_almost_eq: identical float64
## const values guarantee identical float32 narrowing downstream, and that
## bit-identity is the migration's whole determinism argument.

const UnitScript = preload("res://scripts/Unit.gd")
const SoldierCombatScript = preload("res://scripts/SoldierCombat.gd")


func test_unit_geometry_constants_hold_their_exact_world_unit_values() -> void:
	assert_eq(UnitScript.FORMATION_SPACING, 9.0)
	assert_eq(UnitScript.MARK_RADIUS, 4.5)
	assert_eq(UnitScript.CAV_MARK_RADIUS, 10.0)
	assert_eq(UnitScript.RADIUS, 18.0)
	assert_eq(UnitScript.SEPARATION_RADIUS_INFANTRY, 18.0)
	assert_eq(UnitScript.SEPARATION_RADIUS_SPEARMEN, 20.0)
	assert_eq(UnitScript.SEPARATION_RADIUS_CAVALRY, 24.0)
	assert_eq(UnitScript.SEPARATION_RADIUS_MAX, 28.0)


func test_unit_range_constants_hold_their_exact_world_unit_values() -> void:
	assert_eq(UnitScript.DETECTION_RANGE, 190.0)
	assert_eq(UnitScript.RANGED_RANGE, 160.0)
	assert_eq(UnitScript.RALLY_CONTACT_RADIUS, 160.0)
	assert_eq(UnitScript.ROUT_SHOCK_RADIUS, 140.0)


func test_speed_constants_hold_their_exact_world_unit_values() -> void:
	assert_eq(UnitScript.CHARGE_REFERENCE_SPEED, 170.0)
	assert_eq(SoldierCombatScript.CHARGE_REFERENCE_SPEED, 170.0)
	assert_eq(SoldierCombatScript.KNOCKBACK_SPEED_MAX, 60.0)
	assert_eq(SoldierCombatScript.KNOCKBACK_FOCUS_INDEFINITE_SPEED_CAP, 200.0)
	assert_eq(SoldierCombatScript.KINETIC_FRICTION_VELOCITY_REFERENCE, 50.0)


func test_charge_reference_speed_copies_never_diverge() -> void:
	assert_eq(SoldierCombatScript.CHARGE_REFERENCE_SPEED, UnitScript.CHARGE_REFERENCE_SPEED,
		"the two copies exist only because of the historical preload cycle; they must stay one value")


func test_rally_contact_radius_equals_ranged_range() -> void:
	assert_eq(UnitScript.RALLY_CONTACT_RADIUS, UnitScript.RANGED_RANGE,
		"a router in archer reach has not broken contact -- the identity its comment asserts, made structural")
