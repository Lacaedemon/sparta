extends RefCounted
## Hand-off from the main menu's "Parade Ground" button to a tactical battle.
##
## Godot's change_scene_to_file is one-way (no constructor args reach the new scene's
## _ready), so this static holder ferries the request across the scene swap — same
## pattern as CampaignBattle.active/pending. Battle._ready() reads `pending` and sets
## its own drill_mode from it, giving the player a no-enemy battle to freely maneuver
## in. Left set (not consumed/cleared on read) so a later "Restart Battle" reload — which
## re-runs Battle._ready() on a fresh instance — still lands in drill mode; only cleared
## by `clear()`, called defensively whenever the main menu loads.

static var pending: bool = false


## Forget any pending request (once the battle has read it into drill_mode, or
## whenever the main menu loads so a later standalone battle isn't mistaken for a
## parade ground).
static func clear() -> void:
	pending = false
