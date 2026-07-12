extends GutTest
## Battle AI phase 2 (docs/battle-ai-design.md): Subcommander.decide_group's three
## behaviours -- line integrity, mutual support, flank coverage -- and their priority
## ordering. Exercised at the same level as test_unit_leader.gd: units built directly via
## the script (add_child_autofree so _ready() joins "units"), no full Battle scene needed
## since Subcommander reads only unit fields and the arrays it's handed. Each test checks
## the returned {uid: directive} Dictionary shape, not sim side effects -- those are
## UnitLeader's own contract (test_unit_leader.gd) plus _apply_order_cmd's
## (test_battle.gd).

const UnitScript = preload("res://scripts/Unit.gd")
const SubcommanderScript = preload("res://scripts/Subcommander.gd")


func _unit(uid: int, pos: Vector2, team: int = 1) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins "units", sets the footprint
	u.uid = uid
	u.position = pos
	u.team = team
	return u


# --- trivial / degenerate cases -------------------------------------------------

func test_a_group_of_fewer_than_two_units_gets_no_directives() -> void:
	var solo := _unit(1, Vector2(600, 700))
	var cmd: Dictionary = SubcommanderScript.decide_group([solo], [solo])
	assert_true(cmd.is_empty(), "nothing to coordinate with only one (or zero) units")


func test_an_empty_group_gets_no_directives() -> void:
	var cmd: Dictionary = SubcommanderScript.decide_group([], [])
	assert_true(cmd.is_empty())


# --- line integrity ---------------------------------------------------------------

func test_line_integrity_holds_a_unit_that_races_ahead_of_the_group() -> void:
	var a := _unit(1, Vector2(600, 400))   # far closer to the enemy than its allies
	var b := _unit(2, Vector2(500, 700))
	var c := _unit(3, Vector2(700, 700))
	var enemy := _unit(4, Vector2(600, 100), 0)
	var group: Array = [a, b, c]
	var all_units: Array = [a, b, c, enemy]

	var directives: Dictionary = SubcommanderScript.decide_group(group, all_units)

	assert_true(directives.has(a.uid), "the unit far ahead of the line's median gets held")
	assert_eq(directives[a.uid]["type"], SubcommanderScript.DIRECTIVE_HOLD_LINE)
	# Held back to the line's own median depth (y=700, matching b/c) at its own
	# lateral (x) position -- rejoins the line rather than jumping to another unit's spot.
	assert_almost_eq(float(directives[a.uid]["x"]), 600.0, 0.1)
	assert_almost_eq(float(directives[a.uid]["y"]), 700.0, 0.1)
	assert_false(directives.has(b.uid), "b is already at the line's own depth")
	assert_false(directives.has(c.uid), "c is already at the line's own depth")


func test_line_integrity_leaves_a_unit_within_threshold_alone() -> void:
	var a := _unit(1, Vector2(600, 650))   # only a modest lead, under LINE_AHEAD_THRESHOLD
	var b := _unit(2, Vector2(500, 700))
	var c := _unit(3, Vector2(700, 700))
	var enemy := _unit(4, Vector2(600, 100), 0)
	var directives: Dictionary = SubcommanderScript.decide_group(
		[a, b, c], [a, b, c, enemy])
	assert_true(directives.is_empty(), "a routine few-step lead doesn't trigger a hold")


func test_line_integrity_exempts_a_unit_already_in_contact() -> void:
	var a := _unit(1, Vector2(600, 400))   # same far lead as the first test...
	a.state = Unit.State.FIGHTING           # ...but already fighting: not held back
	var b := _unit(2, Vector2(500, 700))
	var c := _unit(3, Vector2(700, 700))
	var enemy := _unit(4, Vector2(600, 100), 0)
	var directives: Dictionary = SubcommanderScript.decide_group(
		[a, b, c], [a, b, c, enemy])
	assert_false(directives.has(a.uid),
		"a unit already in a fight is left to that fight, not yanked back")


func test_no_living_enemies_means_no_line_integrity_directives() -> void:
	# No enemy anywhere -- there's no axis to advance along, so line integrity (and flank
	# coverage, which also depends on the axis) both no-op; only mutual support can still fire.
	var a := _unit(1, Vector2(600, 400))
	var b := _unit(2, Vector2(500, 700))
	var c := _unit(3, Vector2(700, 700))
	var directives: Dictionary = SubcommanderScript.decide_group([a, b, c], [a, b, c])
	assert_true(directives.is_empty())


# --- mutual support ----------------------------------------------------------------

func test_mutual_support_directs_the_nearest_idle_ally_to_the_fighting_unit() -> void:
	var fighter := _unit(1, Vector2(600, 600))
	fighter.state = Unit.State.FIGHTING
	var near_ally := _unit(2, Vector2(650, 600))   # 50 away
	var far_ally := _unit(3, Vector2(600, 750))     # 150 away
	var group: Array = [fighter, near_ally, far_ally]

	var directives: Dictionary = SubcommanderScript.decide_group(group, group)

	assert_eq(directives, {
		near_ally.uid: {"type": SubcommanderScript.DIRECTIVE_SUPPORT, "ward_uid": fighter.uid},
	}, "the nearer idle ally is sent to support -- the farther one gets nothing")


func test_mutual_support_skips_an_ally_already_committed_elsewhere() -> void:
	var fighter := _unit(1, Vector2(600, 600))
	fighter.state = Unit.State.FIGHTING
	var near_ally := _unit(2, Vector2(650, 600))
	near_ally.support_target = fighter   # already guarding a (any) ward
	var far_ally := _unit(3, Vector2(600, 750))
	var group: Array = [fighter, near_ally, far_ally]

	var directives: Dictionary = SubcommanderScript.decide_group(group, group)

	assert_eq(directives, {
		far_ally.uid: {"type": SubcommanderScript.DIRECTIVE_SUPPORT, "ward_uid": fighter.uid},
	}, "an already-committed ally is skipped in favour of the next nearest")


func test_mutual_support_skips_an_ally_mid_relief_swap() -> void:
	var fighter := _unit(1, Vector2(600, 600))
	fighter.state = Unit.State.FIGHTING
	var near_ally := _unit(2, Vector2(650, 600))
	near_ally.set_current_order(Order.new_relief(99))   # mid-swap for someone else
	var far_ally := _unit(3, Vector2(600, 750))
	var group: Array = [fighter, near_ally, far_ally]

	var directives: Dictionary = SubcommanderScript.decide_group(group, group)

	assert_eq(directives[far_ally.uid]["ward_uid"], fighter.uid)
	assert_false(directives.has(near_ally.uid))


func test_mutual_support_skips_an_ally_already_chasing_a_live_target() -> void:
	# The subcommander's own defense-in-depth counterpart to
	# UnitLeader.is_chasing_live_target: a unit mid-pursuit of a live foe is never even
	# offered as a directive candidate, so it's skipped in favour of the next-nearest
	# ally even though it's physically closer.
	var fighter := _unit(1, Vector2(600, 600))
	fighter.state = Unit.State.FIGHTING
	var chasing_ally := _unit(2, Vector2(640, 600))   # nearest by distance, but mid-chase
	var foe := _unit(3, Vector2(900, 600), 0)         # chasing_ally's live target
	chasing_ally.set_current_order(Order.new_attack(foe.uid))
	chasing_ally.target_enemy = foe
	var near_ally := _unit(4, Vector2(650, 600))      # next-nearest, free to be sent
	var group: Array = [fighter, chasing_ally, near_ally]

	var directives: Dictionary = SubcommanderScript.decide_group(group, group)

	assert_eq(directives, {
		near_ally.uid: {"type": SubcommanderScript.DIRECTIVE_SUPPORT, "ward_uid": fighter.uid},
	}, "an ally already chasing a live target of its own is skipped, even though nearest")


func test_no_idle_ally_in_range_means_no_support_directive() -> void:
	var fighter := _unit(1, Vector2(600, 600))
	fighter.state = Unit.State.FIGHTING
	var distant_ally := _unit(2, Vector2(600, 600 + SubcommanderScript.SUPPORT_CALL_RANGE + 50))
	var directives: Dictionary = SubcommanderScript.decide_group(
		[fighter, distant_ally], [fighter, distant_ally])
	assert_true(directives.is_empty(), "no ally close enough to call on")


# --- flank coverage -----------------------------------------------------------------

func test_flank_coverage_sends_a_unit_to_cover_an_outflanked_edge() -> void:
	var left := _unit(1, Vector2(400, 700))
	var mid := _unit(2, Vector2(600, 700))
	var right := _unit(3, Vector2(800, 700))
	var enemy_front := _unit(4, Vector2(600, 300), 0)
	# Sits 150 further out (in x) than the left flank, well within FLANK_ENEMY_RANGE and
	# well outside melee contact -- outflanking, not yet closed.
	var enemy_flanker := _unit(5, Vector2(250, 700), 0)
	# A third enemy that keeps the enemy team's centroid -- and so the axis this test's
	# expected coordinates are computed from -- directly north of the group, unskewed by
	# enemy_flanker's own sideways pull (its x offset from center exactly cancels
	# enemy_flanker's, keeping the axis vertical). It sits well outside FLANK_ENEMY_RANGE
	# of both flanks, so it never itself registers as a threat.
	var enemy_counterweight := _unit(6, Vector2(950, 300), 0)
	var group: Array = [left, mid, right]
	var all_units: Array = [left, mid, right, enemy_front, enemy_flanker, enemy_counterweight]

	var directives: Dictionary = SubcommanderScript.decide_group(group, all_units)

	assert_eq(directives, {
		mid.uid: {"type": SubcommanderScript.DIRECTIVE_COVER_FLANK, "x": 320.0, "y": 700.0},
	}, "the nearest available (non-flank) ally covers the outflanked left edge")


func test_flank_coverage_does_nothing_when_no_flank_is_threatened() -> void:
	var left := _unit(1, Vector2(400, 700))
	var mid := _unit(2, Vector2(600, 700))
	var right := _unit(3, Vector2(800, 700))
	var enemy_front := _unit(4, Vector2(600, 300), 0)   # only a frontal enemy, no flanker
	var directives: Dictionary = SubcommanderScript.decide_group(
		[left, mid, right], [left, mid, right, enemy_front])
	assert_true(directives.is_empty(), "no exposed flank: nothing to cover")


func test_flank_coverage_ignores_an_enemy_already_at_melee_contact() -> void:
	var left := _unit(1, Vector2(400, 700))
	var mid := _unit(2, Vector2(600, 700))
	var right := _unit(3, Vector2(800, 700))
	var enemy_front := _unit(4, Vector2(600, 300), 0)
	# Outflanking direction, but already within melee contact of `left` -- that unit's own
	# UnitLeader flank-threat reaction owns this case, not the subcommander.
	var contact: float = left.attack_range + Unit.RADIUS * 2.0 - 5.0
	var enemy_close := _unit(5, left.position + Vector2(-contact, 0.0), 0)
	# Same counterweight trick as the outflanked-edge test above: cancels enemy_close's
	# sideways pull on the enemy team's centroid, keeping the advance axis vertical so
	# this test's "nothing happens" expectation isn't confounded by line integrity also
	# firing off a diagonal axis (a real failure mode this test caught while it was being
	# written -- an unbalanced two-enemy setup skewed the axis enough that `left` read as
	# "ahead of the line" purely as a geometric artifact, independent of the contact check
	# this test actually means to exercise).
	var enemy_counterweight := _unit(6, Vector2(857, 300), 0)
	var directives: Dictionary = SubcommanderScript.decide_group(
		[left, mid, right], [left, mid, right, enemy_front, enemy_close, enemy_counterweight])
	assert_true(directives.is_empty(), "already in contact: the unit's own reaction handles it")


# --- priority ordering: support > flank coverage > line integrity ------------------

func test_support_takes_priority_over_a_hold_line_directive_on_the_same_unit() -> void:
	# `a` is simultaneously (1) the nearest idle ally to a fighting unit, so it qualifies
	# for a SUPPORT directive, and (2) far enough ahead of the group's own median to
	# qualify for a HOLD_LINE directive on its own. Support must win -- an ally already
	# needed for an active fight outranks ordinary line discipline.
	var fighter := _unit(1, Vector2(600, 420))
	fighter.state = Unit.State.FIGHTING
	var a := _unit(2, Vector2(600, 400))     # right next to the fighter; also "ahead"
	var b := _unit(3, Vector2(500, 700))
	var c := _unit(4, Vector2(700, 700))
	var enemy := _unit(5, Vector2(600, 100), 0)
	var group: Array = [fighter, a, b, c]
	var all_units: Array = [fighter, a, b, c, enemy]

	var directives: Dictionary = SubcommanderScript.decide_group(group, all_units)

	assert_eq(directives, {
		a.uid: {"type": SubcommanderScript.DIRECTIVE_SUPPORT, "ward_uid": fighter.uid},
	}, "a claimed by support, not also (or instead) held back for line integrity")
