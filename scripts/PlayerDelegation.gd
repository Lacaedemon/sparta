class_name PlayerDelegation
## Phase 4 of the chain-of-command battle AI (docs/battle-ai-design.md): player delegation.
## The player taps into the same machinery phases 1-3 already built: "assign player unit
## groups to AI subcommanders" (below), "give group-level directives as the general" (the
## player IS the general here -- they choose group membership by delegating a selection, the
## same act General.assign_groups performs automatically for team 1), "take manual control
## back at any time" (any explicit player order clears delegation -- see Battle.
## _apply_order_cmd's own revocation logic, not this file's concern).
##
## Pure, stateless helpers only, exactly like UnitLeader/Subcommander/General: no Unit-field
## writes happen here. Battle._run_player_delegated_ai is the actual per-tick orchestrator (it
## plays the same role _run_enemy_ai plays for team 1, pointed at team 0's delegated subset
## instead of the whole team), and it is the only thing that reads Unit.player_group_id and
## turns the result into real Orders through _apply_order_cmd -- the single apply site every
## other command level in this game already goes through, so a delegated group's orders are
## structurally indistinguishable from hand-issued ones in the transcript (the design doc's
## own phase-4 acceptance criterion).
##
## Deterministic like every other command level: a pure function of already-serialized sim
## state (each unit's own player_group_id, itself written only through the recorded
## ORDER_DELEGATION_ONLY toggle -- see Unit.player_group_id's own doc comment), so replay
## re-derives the same groups, the same directives, and the same orders every time.

const DEFAULT_SUBCOMMANDER_RANK := "Subcommander"


## Split `team_units` into AI subcommander groups by each delegated unit's own
## player_group_id. A non-delegated unit (Unit.is_delegated() false) contributes to no group
## at all, so it never reaches Subcommander.decide_group / UnitLeader.decide through this
## path -- it keeps behaving exactly as an ordinary, undelegated player unit always has.
## Returns {group_id: Array[Unit]}, iterating `team_units` in the caller's own order (the same
## omniscient, already-serialized order every other command level reads), so this is
## deterministic whenever the caller is.
static func delegated_groups(team_units: Array) -> Dictionary:
	var out: Dictionary = {}
	for node in team_units:
		var u := node as Unit
		if u == null or not u.is_delegated():
			continue
		var gid: int = u.player_group_id
		if not out.has(gid):
			out[gid] = []
		out[gid].append(u)
	return out


## The rank title a newly-delegated group's subcommander is known by, drawn from the player's
## own doctrine profile (DoctrineRegistry.doctrine(player_doctrine)) -- the design doc's "rank
## names... phase 4 surfaces these to the player" requirement. Falls back to a generic title
## for an empty/malformed doctrine (an unknown id, or a hand-authored profile missing the
## field), mirroring every other doctrine-consumption fallback in this codebase (General.
## decide_army's own "empty doctrine -> phase 2 default" convention).
static func subcommander_rank_title(doctrine: Dictionary) -> String:
	return str(doctrine.get("subcommander_rank", DEFAULT_SUBCOMMANDER_RANK))
