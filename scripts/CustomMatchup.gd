extends RefCounted
## Hand-off from PrebattleScreen's "Start Custom Battle" button to a tactical battle.
##
## Godot's change_scene_to_file is one-way (no constructor args reach the new scene's
## _ready), so this static holder ferries the two configured rosters across the scene
## swap -- same pattern as CampaignBattle.active/pending and ParadeGround.pending.
## Battle._ready() reads the rosters (each entry a Faction.FACTION_ROSTERS historical
## name, e.g. "Spartan Hoplites") and spawns a custom matchup from them instead of the
## default two-line battle. Left set (not consumed/cleared on read) so a later "Restart
## Battle" reload still lands in the same custom matchup; only cleared by `clear()`,
## called defensively whenever the main menu loads.

static var pending_team_0: Array[String] = []
static var pending_team_1: Array[String] = []


## Whether either team has a configured roster waiting to be read by Battle._ready().
static func pending() -> bool:
	return not pending_team_0.is_empty() or not pending_team_1.is_empty()


## Forget any pending request (once the battle has read it, or whenever the main menu
## loads so a later standalone/parade-ground battle isn't mistaken for a custom matchup).
static func clear() -> void:
	pending_team_0 = []
	pending_team_1 = []
