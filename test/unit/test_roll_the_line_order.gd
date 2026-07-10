extends GutTest
## ROLL_THE_LINE attack order mode: once the current target routs or dies, the unit
## automatically re-targets the next-closest enemy still fighting, instead of continuing to
## chase a broken foe (the ordinary chase-to-destroy behaviour) or standing idle after a kill.
## Mirrors test_engage_refacing.gd's pattern: bare Unit.new() instances driven directly
## through _think(), no live Battle/orders-queue plumbing needed.
##
## target_enemy is only ever populated by an explicit order (Battle._apply_order_cmd /
## UnitLeader's AI decision) -- Unit._think() itself never auto-acquires a target from
## scratch, it only maintains/re-validates an already-set one each tick (UnitTargeting.
## current_target / roll_the_line_target). So these tests set target_enemy up front, the
## same way an ATTACK order would, then tick _think() to observe the re-target.


func _unit(uid: int, team: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)            # _ready() sets soldiers = max_soldiers, joins "units"
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.attack_range = 26.0
	u.seed_sim_soldiers()
	return u


func test_retargets_next_closest_enemy_once_current_target_routs() -> void:
	var attacker := _unit(1, 0, Vector2(0, 0), Vector2.DOWN)
	attacker.order_mode = Unit.ORDER_ROLL_THE_LINE
	var near_target := _unit(2, 1, Vector2(0, 40), Vector2.UP)     # in contact, engaged first
	var far_target := _unit(3, 1, Vector2(0, 140), Vector2.UP)     # farther away, still fighting
	attacker.target_enemy = near_target   # an ATTACK order already committed this target

	attacker._think(0.05)
	assert_eq(attacker.target_enemy, near_target, "keeps its ordered target while it's still live")
	assert_eq(attacker.state, Unit.State.FIGHTING, "in contact, so the attacker is fighting")

	near_target._rout()
	assert_eq(near_target.state, Unit.State.ROUTING, "the near target is now routing")

	attacker._think(0.05)
	assert_eq(attacker.target_enemy, far_target,
			"once the engaged target routs, the attacker rolls onto the next enemy still fighting")


func test_retargets_the_geometrically_closest_remaining_enemy() -> void:
	var attacker := _unit(1, 0, Vector2(0, 0), Vector2.DOWN)
	attacker.order_mode = Unit.ORDER_ROLL_THE_LINE
	var primary := _unit(2, 1, Vector2(0, 40), Vector2.UP)          # engaged first, will rout
	var close_target := _unit(3, 1, Vector2(0, 90), Vector2.UP)     # closest survivor
	var far_target := _unit(4, 1, Vector2(0, 140), Vector2.UP)      # farther survivor
	attacker.target_enemy = primary

	attacker._think(0.05)
	assert_eq(attacker.target_enemy, primary, "keeps its ordered target while it's still live")

	primary._rout()
	attacker._think(0.05)

	assert_eq(attacker.target_enemy, close_target,
			"rolls onto the closest surviving enemy, not the farther one")
	assert_ne(attacker.target_enemy, far_target,
			"does not skip past a closer surviving enemy")


func test_does_not_pick_up_a_routing_enemy_as_a_fresh_target() -> void:
	# If every remaining enemy is already routing, ROLL_THE_LINE has nothing fresh to roll
	# onto -- it should NOT fall back to picking up a routing enemy (that would just be the
	# ordinary chase-to-destroy behaviour under a different name).
	var attacker := _unit(1, 0, Vector2(0, 0), Vector2.DOWN)
	attacker.order_mode = Unit.ORDER_ROLL_THE_LINE
	var primary := _unit(2, 1, Vector2(0, 40), Vector2.UP)
	var routing_only := _unit(3, 1, Vector2(0, 90), Vector2.UP)
	attacker.target_enemy = primary

	attacker._think(0.05)
	primary._rout()
	routing_only._rout()
	attacker._think(0.05)

	assert_null(attacker.target_enemy,
			"no fresh (non-routing) enemy remains, so the attacker holds no target")


func test_without_roll_the_line_the_unit_keeps_chasing_a_routed_target() -> void:
	# Baseline: the default (NORMAL) targeting keeps a routing enemy as a live target --
	# proves ROLL_THE_LINE is a genuine behaviour change, not the pre-existing default.
	var attacker := _unit(1, 0, Vector2(0, 0), Vector2.DOWN)
	var primary := _unit(2, 1, Vector2(0, 40), Vector2.UP)
	var _other := _unit(3, 1, Vector2(0, 140), Vector2.UP)
	attacker.target_enemy = primary

	attacker._think(0.05)
	primary._rout()
	attacker._think(0.05)

	assert_eq(attacker.target_enemy, primary,
			"without ROLL_THE_LINE, a routed target stays the unit's target (relentless pursuit)")
