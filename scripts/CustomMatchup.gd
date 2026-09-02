extends RefCounted
## Hand-off from PrebattleScreen's "Start Custom Battle" button to a tactical battle.
##
## Godot's change_scene_to_file is one-way (no constructor args reach the new scene's
## _ready), so this static holder ferries the two configured rosters and the factions
## they were drawn from across the scene swap -- same pattern as
## CampaignBattle.active/pending and ParadeGround.pending.
## Battle._ready() reads the rosters (each entry a Faction.FACTION_ROSTERS historical
## name, e.g. "Spartan Hoplites") and spawns a custom matchup from them instead of the
## default two-line battle. Left set (not consumed/cleared on read) so a later "Restart
## Battle" reload still lands in the same custom matchup; only cleared by `clear()`,
## called defensively whenever the main menu loads.

const FactionRef = preload("res://scripts/Faction.gd")

static var pending_team_0: Array[String] = []
static var pending_team_1: Array[String] = []

## Each team's chosen Faction.Type, ferried across the same scene swap as the rosters above so
## Battle can hand them to the HUD (Battle.team_factions -> HUD.set_team_factions) and the
## historical formation/form-up/doctrine names show for the side that actually fights under
## them. Faction.NONE means "no faction chosen", which every Faction display helper renders as
## the plain name -- so a battle reached by any path that doesn't set these looks exactly as
## it did before.
static var pending_faction_0: int = FactionRef.NONE
static var pending_faction_1: int = FactionRef.NONE


## Whether either team has a configured roster waiting to be read by Battle._ready().
## Keyed on the ROSTERS alone: a faction with no units behind it is not a matchup, and the
## prebattle screen never emits one (its Start button is disabled while either roster is
## empty).
static func pending() -> bool:
	return not pending_team_0.is_empty() or not pending_team_1.is_empty()


## Forget any pending request (once the battle has read it, or whenever the main menu
## loads so a later standalone/parade-ground battle isn't mistaken for a custom matchup).
static func clear() -> void:
	pending_team_0 = []
	pending_team_1 = []
	pending_faction_0 = FactionRef.NONE
	pending_faction_1 = FactionRef.NONE
