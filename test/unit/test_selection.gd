extends GutTest
## Selection helpers: the pure type classification, number-key
## mapping, and control-group bind/recall behind double-click type-select and
## control groups. (Live mouse/key routing is exercised manually.)

const SelectionScript = preload("res://scripts/SelectionManager.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func _sm() -> Node:
	var sm = SelectionScript.new()
	add_child_autofree(sm)
	return sm


func _unit(cav: bool, anti: bool) -> Unit:
	var u: Unit = UnitScript.new()
	u.is_cavalry = cav
	u.anti_cavalry = anti
	add_child_autofree(u)
	return u


func test_same_type_matches_role_not_identity() -> void:
	var sm := _sm()
	var inf1 := _unit(false, false)
	var inf2 := _unit(false, false)
	var spear := _unit(false, true)
	var cav := _unit(true, false)
	var cav2 := _unit(true, false)
	assert_true(sm._same_type(inf1, inf2), "two infantry share a type")
	assert_true(sm._same_type(cav, cav2), "two distinct cavalry share a type")
	assert_false(sm._same_type(inf1, spear), "infantry and spearmen differ")
	assert_false(sm._same_type(inf1, cav), "infantry and cavalry differ")


func test_same_type_distinguishes_archers() -> void:
	var sm := _sm()
	var inf := _unit(false, false)
	var archer := _unit(false, false)
	archer.is_ranged = true
	var archer2 := _unit(false, false)
	archer2.is_ranged = true
	assert_false(sm._same_type(inf, archer), "an archer is a different type from infantry")
	assert_true(sm._same_type(archer, archer2), "two archers share a type")


func test_digit_for_keycode_maps_number_row_only() -> void:
	var sm := _sm()
	assert_eq(sm._digit_for_keycode(KEY_0), 0, "KEY_0 -> group 0")
	assert_eq(sm._digit_for_keycode(KEY_9), 9, "KEY_9 -> group 9")
	assert_eq(sm._digit_for_keycode(KEY_A), -1, "letters are not group keys")


func test_bind_then_recall_restores_selection() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(true, false)
	sm._select(a)
	sm._select(b)
	sm._bind_group(1)
	sm._clear_selection()
	assert_eq(sm._selected.size(), 0, "selection is cleared")
	sm._recall_group(1)
	assert_eq(sm._selected.size(), 2, "recalling group 1 restores both bound units")


func test_recall_unbound_group_is_a_noop() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	sm._select(a)
	sm._recall_group(5)   # never bound
	assert_eq(sm._selected.size(), 1, "recalling an empty slot leaves selection intact")


func test_group_members_returns_the_live_bound_units() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(true, false)
	sm._select(a)
	sm._select(b)
	sm._bind_group(2)
	assert_eq(sm.group_members(2), [a, b], "group_members returns the units bound to group 2")


func test_group_members_is_empty_for_an_unbound_group() -> void:
	var sm := _sm()
	assert_eq(sm.group_members(7), [], "returns [] for a slot that was never bound")


func test_group_members_excludes_a_member_that_has_since_died() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var dead := _unit(false, false)
	sm._select(a)
	sm._select(dead)
	sm._bind_group(3)
	dead.state = UnitScript.State.DEAD
	assert_eq(sm.group_members(3), [a], "a dead bound member drops out of the live list")


func test_has_group_distinguishes_unbound_from_bound_but_empty() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	sm._select(a)
	sm._bind_group(4)
	assert_true(sm.has_group(4), "group 4 was bound")
	assert_false(sm.has_group(6), "group 6 was never bound")
	a.state = UnitScript.State.DEAD
	assert_true(sm.has_group(4),
			"a bound group whose members have all since died is still bound -- " +
			"has_group and group_members answer different questions")
	assert_eq(sm.group_members(4), [], "...even though group_members is now empty")


# --- composite (nested) control groups --------------------------------------

func test_bind_group_as_clean_union_of_two_groups_becomes_a_composite() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(false, false)
	var c := _unit(true, false)
	sm._select(a)
	sm._bind_group(2)
	sm._clear_selection()
	sm._select(b)
	sm._select(c)
	sm._bind_group(3)
	sm._clear_selection()
	sm._select(a)
	sm._select(b)
	sm._select(c)
	sm._bind_group(1)   # exactly the union of groups 2 and 3, no leftovers
	assert_true(sm._group_children.has(1), "group 1 is recorded as a composite")
	assert_eq(sm._group_children[1], [2, 3], "group 1's children are groups 2 and 3")
	assert_eq(sm.group_members(1), [a, b, c], "group 1 resolves to the live union of its children")
	sm._clear_selection()
	sm._recall_group(1)
	assert_eq(sm._selected.size(), 3, "recalling the composite group selects all three units")


func test_recalling_a_composite_group_reflects_a_later_rebind_of_a_child() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(false, false)
	var c := _unit(true, false)
	sm._select(a)
	sm._bind_group(2)
	sm._clear_selection()
	sm._select(b)
	sm._bind_group(3)
	sm._clear_selection()
	sm._select(a)
	sm._select(b)
	sm._bind_group(1)   # composite of groups 2 and 3
	assert_eq(sm.group_members(1), [a, b], "sanity: group 1 starts as the union of a and b")
	# Re-bind group 2 -- a CHILD of composite group 1 -- to a different unit entirely.
	sm._clear_selection()
	sm._select(c)
	sm._bind_group(2)
	assert_eq(sm.group_members(1), [c, b],
			"group 1 live-resolves the child's new membership, not a frozen snapshot")
	sm._clear_selection()
	sm._recall_group(1)
	assert_eq(sm._selected.size(), 2, "recalling group 1 now selects c (the rebound child) and b")


func test_bind_group_with_extra_units_beyond_a_clean_union_falls_back_to_flat_bind() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(false, false)
	var extra := _unit(true, false)
	sm._select(a)
	sm._select(b)
	sm._bind_group(2)
	sm._clear_selection()
	sm._select(a)
	sm._select(b)
	sm._select(extra)   # an extra unit not covered by any existing group
	sm._bind_group(1)
	assert_false(sm._group_children.has(1), "extra units break the clean union -- not a composite")
	assert_eq(sm.group_members(1), [a, b, extra],
			"falls back to an ordinary flat snapshot bind, unchanged from today's behavior")


func test_bind_group_with_a_partial_subset_of_a_group_falls_back_to_flat_bind() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(false, false)
	sm._select(a)
	sm._select(b)
	sm._bind_group(2)   # group 2 = {a, b}
	sm._clear_selection()
	sm._select(a)   # only PART of group 2's members -- a partial overlap
	sm._bind_group(1)
	assert_false(sm._group_children.has(1),
			"a partial overlap is not a clean union -- not a composite")
	assert_eq(sm.group_members(1), [a], "falls back to a flat bind of just what's selected")


func test_bind_group_matching_exactly_one_other_group_is_a_degenerate_composite_of_one() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(false, false)
	sm._select(a)
	sm._select(b)
	sm._bind_group(2)
	sm._clear_selection()
	sm._select(a)
	sm._select(b)
	sm._bind_group(1)   # selection exactly matches group 2's own current members
	assert_true(sm._group_children.has(1),
			"a selection matching one whole existing group still counts as a (degenerate) composite")
	assert_eq(sm._group_children[1], [2], "group 1's sole child is group 2")
	assert_eq(sm.group_members(1), [a, b], "group 1 resolves the same as group 2")


func test_bind_group_with_an_empty_selection_is_not_treated_as_a_composite() -> void:
	var sm := _sm()
	sm._bind_group(1)   # Ctrl+1 with nothing selected -- an empty flat bind, unchanged behavior
	assert_false(sm._group_children.has(1), "an empty selection never counts as a clean union")
	assert_true(sm.has_group(1), "still an ordinary (empty) flat bind, same as before composites existed")
	assert_eq(sm.group_members(1), [], "resolves to no members")


func test_bind_group_ignores_a_bound_but_currently_empty_group_as_a_candidate() -> void:
	var sm := _sm()
	var dead := _unit(false, false)
	sm._select(dead)
	sm._bind_group(5)   # group 5 = {dead}
	dead.state = UnitScript.State.DEAD
	assert_true(sm.has_group(5), "group 5 is still bound...")
	assert_eq(sm.group_members(5), [], "...but every member has since died")
	var a := _unit(false, false)
	sm._clear_selection()
	sm._select(a)
	sm._bind_group(2)   # group 2 = {a}
	sm._clear_selection()
	sm._select(a)
	sm._bind_group(1)   # selection == {a}; group 5 (bound, but empty) must not falsely qualify
	assert_true(sm._group_children.has(1), "group 1 still composites cleanly over group 2 alone")
	assert_eq(sm._group_children[1], [2], "the empty, dead group 5 is never picked as a candidate child")
	assert_eq(sm.group_members(1), [a], "group 1 resolves to just a, not affected by group 5 at all")


func test_mutually_composite_groups_do_not_infinite_loop_and_resolve_to_something_sane() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	sm._select(a)
	sm._bind_group(2)   # group 2 = {a} (flat)
	sm._clear_selection()
	sm._select(a)
	sm._bind_group(1)   # group 1 = composite of group 2 (selection == group 2's members)
	assert_eq(sm.group_members(1), [a], "sanity: group 1 resolves to group 2's member before the cycle forms")
	sm._clear_selection()
	sm._select(a)   # group 1 currently resolves to exactly {a} too
	sm._bind_group(2)   # rebind group 2 as a composite of group 1 -- forms a 1<->2 cycle
	assert_true(sm._group_children.has(1) and sm._group_children.has(2),
			"both groups are now recorded as composites of each other")
	# The cycle guard must terminate without crashing or hanging, resolving to something safe.
	assert_eq(sm.group_members(1), [], "a mutual cycle resolves to an empty (safe) result, not an error or a hang")
	assert_eq(sm.group_members(2), [], "...for both sides of the cycle")
	assert_true(sm.has_group(1), "a composite group whose children resolve to a cycle is still considered bound")
	assert_true(sm.has_group(2), "...for both sides")


# --- _unit_at DEAD filter --------------------------------------

func test_unit_at_skips_dead_units() -> void:
	var sm := _sm()
	# Put the DEAD unit exactly under the cursor and the living one slightly off,
	# so the dead node is the strictly nearer candidate. _unit_at uses a strict
	# `<` on distance, so without the DEAD guard the dead unit would win regardless
	# of group iteration order — this fails if the guard regresses.
	var dead := _unit(false, false)
	dead.team = 0
	dead.position = Vector2(100, 100)   # exactly under the click, about to be freed
	dead.state = Unit.State.DEAD
	var alive := _unit(false, false)
	alive.team = 0
	alive.position = Vector2(105, 100)   # 5px off, so it only wins once dead is skipped
	assert_eq(sm._unit_at(Vector2(100, 100), 0), alive,
		"_unit_at returns the living unit, skipping the nearer dead one")


func test_unit_at_returns_null_when_only_match_is_dead() -> void:
	var sm := _sm()
	var dead := _unit(false, false)
	dead.team = 0
	dead.position = Vector2(50, 50)
	dead.state = Unit.State.DEAD
	assert_null(sm._unit_at(Vector2(50, 50), 0),
		"a click on a dead unit's last position selects nothing")
