extends Node2D
class_name Unit
## A regiment: one selectable token with a soldier count and morale.
## Renders itself via _draw() with per-type sprite shapes: infantry kite
## shield, spearmen hoplon + spear, cavalry horse + rider.
## Its soldier marks are flat geometric shapes when zoomed out and swap to
## detailed figure silhouettes (a standing soldier, a mounted rider) when the
## camera zooms in past LOD_ZOOM_IN — see _update_lod / UnitMeshes.figure_mesh.

enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }

# Stable per-battle id (assigned by Battle.gd at spawn). Replays reference units
# by this so recorded orders survive scene reloads.
var uid: int = -1

# --- Tunable stats (set by Battle.gd when spawning) ---
@export var unit_name: String = "Spearmen"
@export var team: int = 0
@export var max_soldiers: int = 120
@export var attack: int = 12
@export var defense: int = 6
@export var move_speed: float = 90.0    # sprint pace (also the loadout's declared top speed)
# Walk/jog paces, in world units/s -- independent per-type values (Battle sets them
# from the loadout's walk_mps/jog_mps), not a fixed fraction of move_speed. Real gaits
# don't scale by a uniform ratio across unit types (a horse's walk/trot/gallop ratios
# look nothing like a human's walk/jog/sprint ratios), and load-carriage research shows
# a heavier panoply costs proportionally more at a run than at a walk. Defaults here
# match the old 0.5/0.75 fractions of the default move_speed, for bare test units that
# never get a loadout.
@export var walk_speed: float = 45.0
@export var jog_speed: float = 67.5
