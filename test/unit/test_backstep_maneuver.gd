extends GutTest
## A SHORT move order into the unit's rear sector should back-step -- hold facing
## and shuffle backward -- rather than about-face (conversio) and march, which is
## the right call for a longer rear-sector reposition (see test_rear_move_conversio.gd)
## but overkill for a move that barely covers any ground. Two layers: the pure
## UnitManeuver.is_backstep classifier (no SceneTree), and a Battle-level
## integration confirming _apply_order_cmd holds facing instead of arming the
## about-face composite.

const Maneuver = preload("res://scripts/UnitManeuver.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")

const FACING_RIGHT := Vector2.RIGHT


# --- pure classifier -------------------------------------------------------

func test_short_move_straight_behind_is_a_backstep() -> void:
	assert_true(Maneuver.is_backstep(FACING_RIGHT, Vector2(-20, 0)),
		"a short destination directly behind is a back-step")


func test_long_move_straight_behind_is_not_a_backstep() -> void:
	assert_false(Maneuver.is_backstep(FACING_RIGHT, Vector2(-200, 0)),
		"a long rear-sector move is a repositioning march (about-face), not a nudge")


func test_short_forward_move_is_not_a_backstep() -> void:
	assert_false(Maneuver.is_backstep(FACING_RIGHT, Vector2(20, 0)),
		"marching forward is never a back-step, however short")


func test_short_flank_move_is_not_a_backstep() -> void:
	assert_false(Maneuver.is_backstep(FACING_RIGHT, Vector2(0, 20)),
		"a 90° flank move is not in the rear sector, so it side-steps instead")


func test_threshold_distance_is_the_boundary() -> void:
	var behind := Vector2.LEFT
	var just_under := behind * (Maneuver.SIDESTEP_MAX_DISTANCE - 1.0)
	var just_over := behind * (Maneuver.SIDESTEP_MAX_DISTANCE + 1.0)
	assert_true(Maneuver.is_backstep(FACING_RIGHT, just_under),
		"a rear move just inside the distance cap back-steps")
	assert_false(Maneuver.is_backstep(FACING_RIGHT, just_over),
		"...and just outside it does not (it's a rear move instead)")


func test_degenerate_inputs_are_not_a_backstep() -> void:
	assert_false(Maneuver.is_backstep(Vector2.ZERO, Vector2(-10, 0)),
		"no facing -> no back-step")
	assert_false(Maneuver.is_backstep(FACING_RIGHT, Vector2.ZERO),
		"a zero-length move -> no back-step (re-click on the spot)")


# --- Battle-level integration ------------------------------------------------

func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins groups, sets the footprint
	u.uid = uid
	u.position = pos
	# No reform hold to step through -- these tests are about the backstep classification,
	# not the reform-before-move hold (reform_before_move is a per-unit field now, no
	# longer a global Settings default a raw cmd dict falls back to).
	u.reform_before_move = false
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


func test_short_backward_move_holds_facing_as_a_backstep() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -20.0, "y": 0.0, "target": -1})
	assert_eq(u.ordered_facing, Vector2.RIGHT, "a short backward move holds the current facing")
	assert_true(u.has_move_target, "and still marches toward the destination")
	assert_false(u.is_order_turning(), "no about-face armed -- it's a held-facing nudge, not a turn")


func test_long_backward_move_does_not_backstep() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.facing = Vector2.RIGHT
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": -200.0, "y": 0.0, "target": -1})
	assert_eq(u.ordered_facing, Vector2.ZERO,
		"a long rear-sector move about-faces instead of holding facing")
