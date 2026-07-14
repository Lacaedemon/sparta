extends RefCounted
## Hand-off from the main menu's "All-Teams Control" button to a tactical battle.
##
## Godot's change_scene_to_file is one-way (no constructor args reach the new scene's
## _ready), so this static holder ferries the request across the scene swap — same
## pattern as ParadeGround.pending/CampaignBattle.active. Battle._ready() reads
## `pending` and sets its own all_teams_control from it: both armies still spawn
## (unlike ParadeGround's no-enemy drill), but SelectionManager lets the player
## select/command every team's units and Battle skips team 1's AI, so a tester can
## drive a real clash from both sides at once. Left set (not consumed/cleared on
## read) so a later "Restart Battle" reload — which re-runs Battle._ready() on a
## fresh instance — still lands in all-teams control; only cleared by `clear()`,
## called defensively whenever the main menu loads.

static var pending: bool = false


## Forget any pending request (once the battle has read it into all_teams_control, or
## whenever the main menu loads so a later standalone battle isn't mistaken for an
## all-teams-control one).
static func clear() -> void:
	pending = false
