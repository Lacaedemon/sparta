extends GutTest
## Battle AI phase 4 (docs/battle-ai-design.md): PlayerDelegation's pure helpers in isolation --
## grouping delegated units by player_group_id, and resolving a subcommander's rank title from
## a doctrine profile. Exercised at the same level as test_general.gd/test_subcommander.gd:
## units built directly via the script (add_child_autofree so _ready() joins "units"), no full
## Battle scene needed since PlayerDelegation reads only Unit fields and the doctrine dict it's
## handed. The live-battle integration (delegation actually producing orders through
## _apply_order_cmd, replay determinism, manual-order override) lives in
## test_battle_ai_player_delegation.gd.

const UnitScript = preload("res://scripts/Unit.gd")
const PlayerDelegationScript = preload("res://scripts/PlayerDelegation.gd")


func _unit(pos: Vector2, team: int = 0) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins "units", sets soldiers = max_soldiers
	u.position = pos
	u.team = team
	return u


# --- delegated_groups --------------------------------------------------------------------

func test_non_delegated_units_form_no_group_at_all() -> void:
	var a := _unit(Vector2(500, 700))
	var b := _unit(Vector2(600, 700))
	assert_eq(PlayerDelegationScript.delegated_groups([a, b]), {},
		"an ordinary, non-delegated unit is invisible to the delegation grouping entirely")


func test_delegated_units_group_by_their_own_player_group_id() -> void:
	var a := _unit(Vector2(500, 700))
	a.player_group_id = 3
	var b := _unit(Vector2(600, 700))
	b.player_group_id = 3
	var c := _unit(Vector2(700, 700))
	c.player_group_id = 7
	var d := _unit(Vector2(800, 700))   # left undelegated
	var groups: Dictionary = PlayerDelegationScript.delegated_groups([a, b, c, d])
	assert_eq(groups.keys(), [3, 7])
	assert_eq(groups[3], [a, b])
	assert_eq(groups[7], [c])


func test_dead_or_routing_delegated_units_still_appear_here_leaving_the_filter_to_the_caller() -> void:
	# PlayerDelegation is a pure grouping step, like Subcommander/General's own OUTPUT-not-
	# actuation contract -- it doesn't itself filter by state. Battle._run_player_delegated_ai
	# feeds it _team_units(0), which (like _team_units(1) for team 1's own AI) already excludes
	# DEAD/ROUTING nodes at the group-membership level -- this test documents that the function
	# itself does not duplicate that filtering, mirroring Subcommander._living's own comment
	# that it applies a defensive filter rather than relying on the caller.
	var a := _unit(Vector2(500, 700))
	a.player_group_id = 1
	a.state = Unit.State.DEAD
	var groups: Dictionary = PlayerDelegationScript.delegated_groups([a])
	assert_eq(groups, {1: [a]})


# --- subcommander_rank_title --------------------------------------------------------------

func test_subcommander_rank_title_reads_the_doctrine_field() -> void:
	var doctrine: Dictionary = {"subcommander_rank": "Tribune"}
	assert_eq(PlayerDelegationScript.subcommander_rank_title(doctrine), "Tribune")


func test_subcommander_rank_title_falls_back_for_an_empty_doctrine() -> void:
	assert_eq(PlayerDelegationScript.subcommander_rank_title({}),
		PlayerDelegationScript.DEFAULT_SUBCOMMANDER_RANK,
		"an unknown/malformed doctrine id falls back to a generic rank, mirroring every other "
		+ "doctrine-consumption fallback in this codebase")


func test_the_two_shipped_doctrines_carry_different_subcommander_ranks() -> void:
	var aggressive: Dictionary = DoctrineRegistry.doctrine("aggressive")
	var cautious: Dictionary = DoctrineRegistry.doctrine("cautious")
	assert_ne(PlayerDelegationScript.subcommander_rank_title(aggressive),
		PlayerDelegationScript.subcommander_rank_title(cautious))
