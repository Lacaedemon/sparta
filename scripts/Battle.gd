extends Node2D
## Sets up the battlefield, spawns both armies, runs the enemy AI, and decides
## when the battle is won or lost.

# Preload instead of relying on Unit's global class_name, so the project loads
# without the editor-built global-class cache (works headless / first run / CI).
const UnitRef = preload("res://scripts/Unit.gd")
const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")

const FIELD := Rect2(0, 0, 1600, 1000)

# Extra room beyond FIELD that a ROUTING unit may flee into before it's removed from play
# (see Unit._escape()). Fixed and known up front (not sized per unit) since it's drawn once
# as a visible margin strip at battle start (see _draw()). Sized to the game's maximum
# visual range — the longest ranged attack (RANGED_RANGE) and the farthest a unit can
# currently be noticed at (DETECTION_RANGE, the closest existing stand-in for a
# fog-of-war vision range, which this game doesn't have yet) — so a fleeing unit stays a
# plausible target for as long as it's still visible, rather than vanishing early.
var ROUT_MARGIN: float = maxf(UnitRef.RANGED_RANGE, UnitRef.DETECTION_RANGE)
var FIELD_WITH_MARGIN: Rect2 = FIELD.grow(ROUT_MARGIN)

# Terrain patches; type keys into TERRAIN_COLOR. kind="block" is impassable; kind="slow" is a speed zone.
const TERRAIN: Array = [
	{"rect": Rect2(200,  380, 250, 200), "type": "forest", "kind": "slow", "speed": 0.6},
	{"rect": Rect2(1150, 380, 250, 200), "type": "hill",   "kind": "block"},
]
const TERRAIN_COLOR := {
	"forest": Color(0.12, 0.28, 0.10),
	"hill":   Color(0.55, 0.48, 0.32),
}

# Sentinel order target: a move order carrying this as its `target` appends
# its destination to the units' waypoint queue instead of replacing the route.
# Overloads the existing int field (like merge/relief) so the replay format is
# unchanged — real merge/attack/relief targets are uids >= 0, a plain move is -1.
const ORDER_APPEND_WAYPOINT := -2
# Sentinel for a formation-change-only order (no movement, no target). Handled
# before the main move/attack/merge logic so it doesn't clear waypoints or stances.
const ORDER_FORMATION_ONLY := -3
# Sentinel for a frontage-resize-only order (widen/narrow the line). Carries an
# absolute "frontage" (the target file count, resolved per unit at enqueue time, so
# re-applying on the tick is idempotent). Handled like the formation-only order,
# leaving movement untouched.
const ORDER_FRONTAGE_ONLY := -4
# Sentinel for a wheel order (circumductio, hinge pivot): the block swings 90° about a fixed
# flank file. Carries the direction in the "x" field (-1 wheel-left / +1 wheel-right). UNLIKE
# the conversio and quarter-turn — which touch only per-soldier facing and so never enter the
# replay stream — a wheel moves the regiment (position and facing), which the sim reads, so it
# IS recorded and replayed like a move. Handled before the main move/attack/merge logic.
const ORDER_WHEEL := -5
# Sentinel for an arrow-key nudge: a small fixed-distance drill move that holds
# facing. The nudge direction rides the "frontage" field (1 = left, 2 = right,
# 3 = back, 4 = forward), so the replay format is unchanged. Each unit steps
# from its own facing, so a mixed-facing selection nudges correctly per unit.
const ORDER_NUDGE := -6
enum NudgeDir { LEFT = 1, RIGHT = 2, BACK = 3, FORWARD = 4 }
# Sentinel for a standalone stance-change order (no movement, no target): writes the
# durable order_mode and/or the intra-unit rank-relief mode on each unit, leaving all
# movement state untouched. The stance rides the existing "mode" field (-1 = leave the
# stance unchanged) and the rank-relief toggle rides the "frontage" field (RankRelief),
# so the replay format is unchanged. Handled like the formation-only order.
const ORDER_STANCE_ONLY := -7
# Rank-relief toggle values for a stance order's "frontage" field: LEAVE keeps each
# unit's current setting; ON/OFF write the durable Unit.rank_relief mode.
enum RankRelief { LEAVE = 0, ON = 1, OFF = 2 }
# How far a single arrow-key nudge shifts the unit (world units). 30 wu is ~1.5 m
# (WORLD_UNITS_PER_METER = 20) — a few soldier-widths, and under the side-step
# distance ceiling (UnitManeuver.SIDESTEP_MAX_DISTANCE) so a lateral nudge always
# reads as a shuffle rather than a turn-and-march.
const NUDGE_DISTANCE := 30.0

## Order modes: the "stance" an order applies to its units. NORMAL is the
## current move/attack behaviour. The smart modes are chosen by the player's armed
## mode (SelectionManager), recorded in the replay ("mode") and stamped on
## Unit.order_mode; the per-unit behaviour for each is added in the sibling issues.
## Until then a non-NORMAL stance is stored but behaves as
## NORMAL. NORMAL is 0 so it matches Unit.order_mode's default.
enum OrderMode { NORMAL, HOLD, ATTACK_FLANK, ATTACK_REAR, SKIRMISH, SUPPORT, CYCLE_CHARGE, SWEEP_ROUTERS, ROLL_THE_LINE, PIN_DOWN, ALL_OUT_ATTACK, CHASE, WEDGE_CHARGE, KNOCKBACK_FOCUS }

## Movement gait for a MOVE order: WALK (single click), JOG (double), RUN (triple),
## or SPRINT (quadruple) -- see SelectionManager._gait_from_click_count. Applies to
## any unit that receives an explicit gait; an order with no gait set (-1, AUTO) keeps
## the old walk/jog-under-fire/sprint-at-close-range logic in Unit._move_to. There are
## only three real per-type speeds (walk/jog/sprint -- for cavalry, walk/trot/gallop);
## RUN has no speed of its own, it's jog while far from the target and sprint once
## inside SPRINT_START_DISTANCE (see Unit._move_to).
enum Gait { WALK, JOG, RUN, SPRINT }

## How a multi-unit attack order distributes its target among the ordered units.
## Focused (default): every unit attacks the same enemy.
## Distributed: units spread across nearby enemies sorted by proximity to the
## clicked target; extra units cycle through the list.
enum GroupAttackMode { FOCUSED = 0, DISTRIBUTED = 1 }

const GROUP_ATTACK_MODE_NAMES := {
	GroupAttackMode.FOCUSED: "Attack: focused",
	GroupAttackMode.DISTRIBUTED: "Attack: distributed",
}

const GAIT_NAMES := {
	Gait.WALK: "Walk",
	Gait.JOG: "Jog",
	Gait.RUN: "Run",
	Gait.SPRINT: "Sprint",
}

## Human-readable mode names for the HUD / cursor indicator.
const ORDER_MODE_NAMES := {
	OrderMode.NORMAL: "Normal",
	OrderMode.HOLD: "Hold",
	OrderMode.ATTACK_FLANK: "Attack flank",
	OrderMode.ATTACK_REAR: "Attack rear",
	OrderMode.SKIRMISH: "Skirmish",
	OrderMode.SUPPORT: "Support",
	OrderMode.CYCLE_CHARGE: "Cycle charge",
	OrderMode.SWEEP_ROUTERS: "Sweep routers",
	OrderMode.ROLL_THE_LINE: "Roll the line",
	OrderMode.PIN_DOWN: "Pin down",
	OrderMode.ALL_OUT_ATTACK: "All-out attack",
	OrderMode.CHASE: "Chase",
	OrderMode.WEDGE_CHARGE: "Wedge charge",
	OrderMode.KNOCKBACK_FOCUS: "Knockback focus",
}

## Rebindable order-mode hotkeys, in menu/HUD order. Each entry pairs the
## OrderMode it arms with a stable cfg "slug"; the Settings autoload persists
## slug -> physical keycode (defaults in Settings.DEFAULT_ORDER_BINDINGS), and the
## keybindings dialog labels rows via ORDER_MODE_NAMES. NORMAL (Esc, "clear stance")
## is intentionally absent — it stays a fixed, non-rebindable key.
const ORDER_MODE_HOTKEYS := [
	{"mode": OrderMode.HOLD, "slug": "hold"},
	{"mode": OrderMode.ATTACK_FLANK, "slug": "attack_flank"},
	{"mode": OrderMode.ATTACK_REAR, "slug": "attack_rear"},
	{"mode": OrderMode.SKIRMISH, "slug": "skirmish"},
	{"mode": OrderMode.SUPPORT, "slug": "support"},
	{"mode": OrderMode.CYCLE_CHARGE, "slug": "cycle_charge"},
	{"mode": OrderMode.SWEEP_ROUTERS, "slug": "sweep_routers"},
	{"mode": OrderMode.ROLL_THE_LINE, "slug": "roll_the_line"},
	{"mode": OrderMode.PIN_DOWN, "slug": "pin_down"},
	{"mode": OrderMode.ALL_OUT_ATTACK, "slug": "all_out_attack"},
	{"mode": OrderMode.CHASE, "slug": "chase"},
	{"mode": OrderMode.WEDGE_CHARGE, "slug": "wedge_charge"},
	{"mode": OrderMode.KNOCKBACK_FOCUS, "slug": "knockback_focus"},
]

# Global movement multiplier applied on top of each unit's real-world speed (which
# the loadout now states in metres/second). 1.0 = units move at the authored m/s;
# lower it to slow the whole battle uniformly without disturbing relative speeds.
const SPEED_SCALE := 1.0

# World scale: how many sim/world units make up one metre. Used to express
# real-world lengths (weapon reach, and later movement speed) in metres and
# convert them to the world units the sim runs in. These are WORLD units, not
# screen pixels: Godot renders the fixed FIELD onto any window via the viewport
# stretch (canvas_items / expand) and the Camera2D zoom, so the display
# resolution is independent of this scale. At 20 u/m the 1600x1000 field is an
# 80 m x 50 m engagement frontage. It's a single named knob, so the world's
# unit scale can be rebased here without hunting down hard-coded distances.
const WORLD_UNITS_PER_METER := 20.0

# Enemy AI re-evaluates on a fixed tick cadence (not a wall-clock timer) so the
# simulation is deterministic and replayable. 60 ticks == 1 second at 60 Hz.
const AI_PERIOD := 60

# Fraction of the remaining distance the demo camera closes toward its recorded
# target each tick (exponential smoothing). < 1 low-passes any jitter in the
# recorded presentation track so the clip glides instead of snapping keyframe to
# keyframe; ~0.15/tick at 60 Hz settles a step in ~0.3 s — smooth but responsive.
const CAMERA_SMOOTHING := 0.15

@onready var _units: Node2D = $Units
@onready var _hud = $HUD
@onready var _camera: Camera2D = $Camera2D
@onready var _selection = $SelectionManager

# Fixed-step clock driving the whole simulation; also the timeline for replays.
var _tick: int = 0
var _ended: bool = false

# Drill / solo mode: deploy only the player army (team 0) and never auto-end on "no enemies",
# so a unit can rehearse a maneuver with no combat. Set BEFORE the node enters the tree (the
# demo recorder sets it from the input script's "drill" field) so _ready reads it. Off = the
# normal two-army battle.
var drill_mode: bool = false

# Custom demo matchup (tooling): a list of unit specs the demo recorder can set from an input
# script's "scenario" field BEFORE the node enters the tree, to stage a specific fight (a weak
# unit that will rout, an enemy placed off a unit's flank, cavalry vs a target). Empty = the
# normal default-loadout spawn, byte-for-byte. See _spawn_scenario and demos/README.md.
var scenario: Array = []

# Units deployed per side when this is a campaign-launched battle; used to
# scale survivors back to campaign army strength when the battle ends.
var _camp_atk_spawned: int = 0
var _camp_dfn_spawned: int = 0

# uid -> Unit, so recorded orders can resolve their units after a scene reload.
var _by_uid: Dictionary = {}
# Player orders received since the last physics step (live play only). Applied
# and recorded at the next tick so live and replayed orders take identical paths.
var _pending_orders: Array = []
var _next_uid: int = 0


func _ready() -> void:
	# Unit mirrors a few OrderMode values as plain ints (it can't reference our
	# enum without a preload cycle). Assert the mirror here — where we already hold
	# UnitRef — so a future enum reorder fails loudly instead of misbehaving.
	assert(UnitRef.ORDER_HOLD == OrderMode.HOLD \
			and UnitRef.ORDER_ATTACK_FLANK == OrderMode.ATTACK_FLANK \
			and UnitRef.ORDER_ATTACK_REAR == OrderMode.ATTACK_REAR \
			and UnitRef.ORDER_SKIRMISH == OrderMode.SKIRMISH \
			and UnitRef.ORDER_SUPPORT == OrderMode.SUPPORT \
			and UnitRef.ORDER_CYCLE_CHARGE == OrderMode.CYCLE_CHARGE \
			and UnitRef.ORDER_SWEEP_ROUTERS == OrderMode.SWEEP_ROUTERS \
			and UnitRef.ORDER_ROLL_THE_LINE == OrderMode.ROLL_THE_LINE \
			and UnitRef.ORDER_PIN_DOWN == OrderMode.PIN_DOWN \
			and UnitRef.ORDER_ALL_OUT_ATTACK == OrderMode.ALL_OUT_ATTACK \
			and UnitRef.ORDER_CHASE == OrderMode.CHASE \
			and UnitRef.ORDER_WEDGE_CHARGE == OrderMode.WEDGE_CHARGE \
			and UnitRef.ORDER_KNOCKBACK_FOCUS == OrderMode.KNOCKBACK_FOCUS,
			"Unit order-mode mirror constants are out of sync with Battle.OrderMode")
	# Same mirror-and-assert pattern for Unit's NUDGE_* constants (Battle.NudgeDir).
	assert(UnitRef.NUDGE_LEFT == NudgeDir.LEFT \
			and UnitRef.NUDGE_RIGHT == NudgeDir.RIGHT \
			and UnitRef.NUDGE_BACK == NudgeDir.BACK \
			and UnitRef.NUDGE_FORWARD == NudgeDir.FORWARD,
			"Unit nudge-direction mirror constants are out of sync with Battle.NudgeDir")

	# Start a fresh recording for every live battle (so any battle can be
	# replayed for debugging). During playback the recorder is already armed by
	# the seed loaded from the file, so we leave it alone.
	if Replay.mode != Replay.Mode.PLAYBACK:
		Replay.start_recording()

	_camera.bounds = FIELD
	_camera.position = FIELD.position + FIELD.size * 0.5
	# When the demo recorder replays a presentation track, start already framed on the
	# first keyframe so the smoothing below has nothing to glide in from.
	if Replay.mode == Replay.Mode.PLAYBACK and Replay.drive_camera and Replay.has_camera_track():
		var first: Dictionary = Replay.camera_for_tick(0)
		_camera.position = Vector2(first["x"], first["y"])
		_camera.zoom = Vector2(first["zoom"], first["zoom"])

	# In-flight projectiles (ranged volleys) live here, ticked in _on_soldier_tick; cleared in
	# _exit_tree(). A fresh field per battle so no arrows carry over a restart.
	ProjectileField.active = ProjectileField.new()

	# Register terrain patches as PathField obstacles or speed zones; cleared in _exit_tree().
	PathField.active = PathField.new(FIELD)
	for patch in TERRAIN:
		if patch.get("kind", "block") == "slow":
			assert(patch.has("speed"), "slow terrain patch missing required 'speed' key")
			PathField.active.set_speed_rect(patch["rect"], float(patch["speed"]))
		else:
			PathField.active.block_rect(patch["rect"])

	# Drill mode is a no-opponent rehearsal; a campaign clash always has a defender. They are
	# mutually exclusive — assert it so a future path that ends a drill battle can't silently
	# report campaign survivors against defenders that were never spawned.
	assert(not (drill_mode and CampaignBattle.active),
			"drill mode is incompatible with a campaign battle")
	# Army sizes: a campaign-launched clash deploys units scaled to the two
	# clashing armies' strengths; a standalone battle uses the default 5-unit line.
	var atk_count := 5
	var dfn_count := 5
	if CampaignBattle.active and not CampaignBattle.pending.is_empty():
		atk_count = CampaignBattle.units_for(int(CampaignBattle.pending["attacker_strength"]))
		dfn_count = CampaignBattle.units_for(int(CampaignBattle.pending["defender_strength"]))
		_camp_atk_spawned = atk_count
		_camp_dfn_spawned = dfn_count
	# A demo scenario stages a custom matchup instead of the default two lines (tooling only;
	# a normal battle leaves `scenario` empty). It owns both teams' placement, so it replaces
	# the line spawn entirely rather than layering on top.
	if not scenario.is_empty():
		_spawn_scenario(scenario)
	else:
		# Player army (team 0) deploys along the top, facing down.
		_spawn_line(0, Vector2.DOWN, 300, atk_count)
		# Enemy army (team 1) deploys along the bottom, facing up — skipped in drill mode,
		# where the player army rehearses alone.
		if not drill_mode:
			_spawn_line(1, Vector2.UP, 700, dfn_count)

	# Drive the parallel individual-soldier layer once per tick. physics_frame
	# fires AFTER every unit's _physics_process, so the seed reads settled
	# positions and the global separation runs on this tick's geometry. Connected
	# only when the layer is enabled; it's non-authoritative (nothing in the sim
	# reads _sim_soldier_pos). See docs/individual-collision-design.md.
	if UnitRef.INDIVIDUAL_COLLISION:
		get_tree().physics_frame.connect(_on_soldier_tick)


func _exit_tree() -> void:
	# physics_frame lives on the SceneTree, which outlives this node across a
	# reload_current_scene(). Without disconnecting, this freed-but-not-yet-gone
	# Battle gets one more _on_soldier_tick after it leaves the tree, where
	# get_tree() is null — "Invalid access to property 'paused' on a null instance".
	#
	# get_tree() itself can ALSO already be null by the time _exit_tree runs (the node has
	# already left the tree during teardown), so read it into a local ONCE and guard on that,
	# rather than calling get_tree() twice more below — a null-unguarded call there throws and
	# aborts this function early, silently skipping the static releases beneath it.
	var tree := get_tree()
	if tree != null and tree.physics_frame.is_connected(_on_soldier_tick):
		tree.physics_frame.disconnect(_on_soldier_tick)

	# Don't let this battle's pathfinding grid or in-flight projectiles outlive it (e.g. across
	# a scene reload or a future return-to-map flow) — release them unconditionally, regardless
	# of whether the disconnect above ran, so a teardown that hits the null-tree case above
	# still frees these. The next Battle._ready() republishes both.
	PathField.active = null
	ProjectileField.active = null   # drop any in-flight arrows with the battle

	# The per-tick spatial-hash grids (SpatialHash / SoldierSpatialHash) key their cached
	# _cells on the physics frame they were built for and rebuild from a fresh group scan
	# every tick a battle is running, so they self-heal on the next live battle's first
	# rebuild() regardless. Still reset them here so a freed battle never leaves the LAST
	# built grid pinning freed Unit references between spawns (e.g. across a whole GUT run
	# with no battle currently alive) — cheap, and removes the dangling-reference window.
	SpatialHash.reset()
	SoldierSpatialHash.reset()


func _draw() -> void:
	# The retreat margin (see FIELD_WITH_MARGIN) drawn first, under the field, so it reads
	# as a dimmer strip of ground beyond the playable edge — where a routing unit may still
	# be fleeing (and still fightable) before it's gone for good.
	draw_rect(FIELD_WITH_MARGIN, Color(0.34, 0.42, 0.27).darkened(0.3))
	# Simple grass field + a center line, so the world is readable before art.
	draw_rect(FIELD, Color(0.34, 0.42, 0.27))
	draw_rect(FIELD, Color(0.2, 0.25, 0.16), false, 4.0)
	draw_line(Vector2(0, FIELD.size.y * 0.5), Vector2(FIELD.size.x, FIELD.size.y * 0.5),
		Color(1, 1, 1, 0.08), 2.0)
	# Terrain patches — drawn over the field, under units (Battle is the parent).
	for patch in TERRAIN:
		var col: Color = TERRAIN_COLOR.get(patch["type"], Color(0.4, 0.4, 0.4))
		draw_rect(patch["rect"], col)
		draw_rect(patch["rect"], col.darkened(0.35), false, 2.0)


func _spawn_line(team: int, facing: Vector2, y: float, count: int = 5) -> void:
	# Loadout: spearmen, infantry, archers, cavalry, cavalry. The archers
	# skirmish from range — softer in melee, but they soften the line before contact.
	# `count` units deploy, cycling this composition so a larger army (a bigger
	# campaign stack) fields more of the same mix.
	#
	# `weapon`/`shield` are interned LoadoutRegistry type ids. The weapon type's
	# reach_m (metres) becomes the unit's attack_range below. Longer-reach weapons
	# strike while a shorter-weapon enemy is still closing the gap, so a spearman
	# lands the first blows of a clash. Infantry's gladius sits at the 1.3 m
	# baseline (= the old flat 26-unit reach); the spear out-reaches it, the
	# cavalry spatha a touch longer than the foot sword, and the archers' sidearm
	# is short (they fight at range, not in the press).
	#
	# `walk_mps`/`jog_mps`/`sprint_mps` are the unit's three gait speeds in metres/second,
	# converted to world units below. Independent per type -- not a fixed fraction of each
	# other -- and scaled to each type's panoply weight: heavier kit costs proportionally
	# more at a run than at a walk (walking pace is fairly load-insensitive; sprint pace
	# collapses faster under weight), so spearmen's walk sits close to the lighter types'
	# but their sprint lags well behind. Cavalry's three paces map onto the horse's own
	# real gaits (walk / trot / gallop) rather than a rider-weight-scaled fraction, since a
	# rider's kit is a small fraction of what the horse itself carries (tack, barding, and
	# rider together are still well inside a war-horse's load capacity at these speeds).
	# `accel_mps2`/`decel_mps2` are how fast the unit ramps toward/away from a pace, in
	# metres/second^2. Same panoply-weight reasoning as the pace speeds above: heavier
	# kit accelerates slower, and decel > accel for foot troops (stopping needs no
	# propulsive effort; starting does) -- cavalry is symmetric since a galloping
	# horse can't be reined in any faster than it can build up speed. See
	# website/tactics.qmd for the full table.
	#
	# `formation` is the type's default density (still just a starting point --
	# every unit can cycle Tight/Normal/Loose live with the T hotkey). Anti-cavalry
	# spearmen brace tight by default (locked shields against a charge); ranged
	# skirmishers start loose (room to fire, less to lose from spreading out);
	# sword-armed foot and cavalry start at the plain combat-order default.
	#
	# `back_fraction` is the type's backward-walk speed, as a fraction of its own
	# jog_mps (see Unit.back_speed_fraction) -- a soldier backing up during an
	# in-place maneuver moves slower than one stepping forward, and the shortfall
	# scales with kit weight the same way the pace speeds above do: a heavily-kitted
	# spearman shuffles backward at barely a third of his jog pace, while a light
	# skirmisher archer is closer to half. Cavalry back a horse up carefully rather
	# than trotting it backward, so it sits lowest of all. Optional per entry --
	# _spawn_unit falls back to the Unit.gd default (0.5) when a loadout omits it.
	var loadout := _default_loadout()
	# Tighten the BASE spacing as the line grows so even a max stack stays on the field --
	# but never let it collapse below what keeps a wide neighbour's formation block from
	# overlapping the unit next to it. A flat per-unit spacing assumed a
	# roughly-uniform unit width that doesn't hold once soldier counts / formation density
	# vary per type in the cycling loadout above -- e.g. a 90-soldier LOOSE-order Archers
	# block (UnitFormation.half_width_for_soldiers, scaled by Unit.spacing_scale_for_mode)
	# is far wider than a same-count TIGHT block, so the old flat spacing let it overlap
	# whichever neighbour it cycled next to. Each adjacent pair's minimum gap is instead the
	# sum of their own half-widths plus a soldier-file's worth of daylight (FORMATION_SPACING),
	# so no two blocks so much as touch, regardless of composition.
	var base_spacing: float = minf(150.0, (FIELD.size.x - 200.0) / maxf(1.0, count - 1))
	var half_widths: Array[float] = []
	for i in range(count):
		var d: Dictionary = loadout[i % loadout.size()]
		var d_spacing: float = Unit.FORMATION_SPACING \
				* Unit.spacing_scale_for_mode(d.get("formation", Unit.FORMATION_NORMAL))
		half_widths.append(UnitFormation.half_width_for_soldiers(d["soldiers"], d_spacing))

	# The no-overlap gap above guarantees adjacent blocks never touch, but it makes no
	# promise about the TOTAL line width -- a max-size campaign stack (CampaignBattle.
	# MAX_UNITS) cycling several wide LOOSE-order types back to back can need more total
	# width than FIELD has room for, which would push the outer units off the playable
	# field entirely (the no-overlap fix's own follow-up finding). So sum the no-overlap
	# gaps first; if that sum would overflow the same FIELD budget the old flat spacing
	# always respected, scale every gap down proportionally until the line fits. This
	# accepts a little unavoidable overlap only in that rare wide/high-count extreme --
	# normal-size battles (the standard 5v5 demo, and any count whose no-overlap gaps
	# already fit) are untouched, since the scale factor is 1.0 whenever the raw sum is
	# already within budget.
	var gaps: Array[float] = []
	var raw_total_width: float = 0.0
	for i in range(count - 1):
		var gap: float = maxf(base_spacing,
				half_widths[i] + half_widths[i + 1] + Unit.FORMATION_SPACING)
		gaps.append(gap)
		raw_total_width += gap
	var field_budget: float = FIELD.size.x - 200.0
	if raw_total_width > field_budget and raw_total_width > 0.0:
		var shrink: float = field_budget / raw_total_width
		for i in range(gaps.size()):
			gaps[i] *= shrink

	# xs[i] is unit i's x-offset from the line's own left edge (xs[0] == 0.0); the whole
	# line is then centred on the field below, same as the old uniform-spacing layout.
	var xs: Array[float] = [0.0]
	for i in range(count - 1):
		xs.append(xs[i] + gaps[i])
	var start_x: float = FIELD.size.x * 0.5 - xs[xs.size() - 1] * 0.5

	for i in range(count):
		var d: Dictionary = loadout[i % loadout.size()]
		var pos := Vector2(start_x + xs[i], y)
		_spawn_unit(d, team, facing, pos, "%s %d" % [d["name"], i + 1])


## The default battle loadout: spearmen, infantry, archers, cavalry, cavalry. A line
## cycles this composition, so a larger army fields more of the same mix. Extracted so
## both the line spawn and the scenario spawn (custom demo matchups) share one stat table.
##
## `weapon`/`shield` are interned LoadoutRegistry type ids — the concrete Weapon/Shield
## type every soldier of the unit carries. The weapon type's reach_m (metres) is converted
## to the unit's attack_range in _spawn_unit, so the registry is the single source of truth
## for reach. Longer-reach weapons strike while a shorter-weapon enemy is still closing the
## gap, so a spearman lands the first blows of a clash. Infantry's gladius sits at the
## 1.3 m baseline; the spear out-reaches it, the cavalry spatha a touch longer than the
## foot sword, and the archers' sidearm is short (they fight at range).
##
## `walk_mps`/`jog_mps`/`sprint_mps` are the unit's three gait speeds in metres/second,
## converted to world units in _spawn_unit. Independent per type -- not a fixed fraction of
## each other -- and scaled to each type's panoply weight: heavier kit costs proportionally
## more at a run than at a walk, so spearmen's walk sits close to the lighter types' but
## their sprint lags well behind. Cavalry's three paces map onto the horse's own real gaits
## (walk / trot / gallop). `accel_mps2`/`decel_mps2` follow the same reasoning: heavier kit
## accelerates slower, decel > accel for foot troops, cavalry symmetric. See
## website/tactics.qmd for the full table.
##
## `formation` is the type's default density (every unit can still cycle Tight/Normal/Loose
## live with the T hotkey): anti-cavalry spearmen brace tight, ranged skirmishers start
## loose, sword-armed foot and cavalry at the plain combat-order default.
##
## `back_fraction` is the type's backward-walk speed as a fraction of its own jog_mps (see
## Unit.back_speed_fraction) -- heavier kit backs up proportionally slower, same reasoning
## as the pace speeds above. Optional; _spawn_unit falls back to the Unit.gd default (0.5)
## for a loadout entry that omits it.
func _default_loadout() -> Array:
	return [
		{"name": "Spearmen", "anti_cav": true, "cav": false, "soldiers": 140, "atk": 11, "def": 8, "walk_mps": 1.1, "jog_mps": 1.8, "sprint_mps": 2.8, "accel_mps2": 1.0, "decel_mps2": 2.5, "back_fraction": 0.35, "weapon": LoadoutRegistry.WEAPON_SPEAR, "shield": LoadoutRegistry.SHIELD_SCUTUM, "training": 0.75, "formation": Unit.FORMATION_TIGHT},
		{"name": "Infantry", "anti_cav": false, "cav": false, "soldiers": 120, "atk": 13, "def": 6, "walk_mps": 1.3, "jog_mps": 2.5, "sprint_mps": 4.0, "accel_mps2": 1.5, "decel_mps2": 3.0, "back_fraction": 0.45, "weapon": LoadoutRegistry.WEAPON_GLADIUS, "shield": LoadoutRegistry.SHIELD_SCUTUM, "training": 0.5, "formation": Unit.FORMATION_NORMAL},
		{"name": "Archers", "anti_cav": false, "cav": false, "ranged": true, "soldiers": 90, "atk": 10, "def": 4, "walk_mps": 1.5, "jog_mps": 3.0, "sprint_mps": 4.5, "accel_mps2": 2.0, "decel_mps2": 3.5, "back_fraction": 0.55, "weapon": LoadoutRegistry.WEAPON_SIDEARM, "shield": LoadoutRegistry.SHIELD_NONE, "training": 0.3, "formation": Unit.FORMATION_LOOSE},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "walk_mps": 1.7, "jog_mps": 3.5, "sprint_mps": 8.5, "accel_mps2": 2.0, "decel_mps2": 2.0, "back_fraction": 0.3, "weapon": LoadoutRegistry.WEAPON_SPATHA, "shield": LoadoutRegistry.SHIELD_ROUND, "training": 0.6, "formation": Unit.FORMATION_NORMAL},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "walk_mps": 1.7, "jog_mps": 3.5, "sprint_mps": 8.5, "accel_mps2": 2.0, "decel_mps2": 2.0, "back_fraction": 0.3, "weapon": LoadoutRegistry.WEAPON_SPATHA, "shield": LoadoutRegistry.SHIELD_ROUND, "training": 0.6, "formation": Unit.FORMATION_NORMAL},
	]


## Build one unit from a loadout dict `d` at `pos`, facing `facing`, on `team`, register it,
## and add it to the field. Shared by the default line spawn and the scenario spawn. Keys read
## here (these are DICT keys, not scenario-spec fields -- _spawn_scenario maps a spec's `count`
## onto `soldiers` before calling): `soldiers` sets max_soldiers, `morale` the starting morale
## (default 100), `formation` the starting density.
func _spawn_unit(d: Dictionary, team: int, facing: Vector2, pos: Vector2, unit_label: String) -> Unit:
	var u := UnitRef.new()
	u.uid = _next_uid
	_next_uid += 1
	_by_uid[u.uid] = u
	u.unit_name = unit_label
	u.team = team
	u.anti_cavalry = d["anti_cav"]
	u.is_cavalry = d["cav"]
	u.is_ranged = d.get("ranged", false)
	u.max_soldiers = d["soldiers"]
	u.attack = d["atk"]
	u.defense = d["def"]
	# Real-world m/s -> world units, times the global movement multiplier.
	u.walk_speed = d["walk_mps"] * WORLD_UNITS_PER_METER * SPEED_SCALE
	u.jog_speed = d["jog_mps"] * WORLD_UNITS_PER_METER * SPEED_SCALE
	u.move_speed = d["sprint_mps"] * WORLD_UNITS_PER_METER * SPEED_SCALE
	u.accel = d["accel_mps2"] * WORLD_UNITS_PER_METER * SPEED_SCALE
	u.decel = d["decel_mps2"] * WORLD_UNITS_PER_METER * SPEED_SCALE
	# Per-type backward-walk speed, as a fraction of this type's own jog_speed (see
	# Unit.back_speed_fraction). A dict without a "back_fraction" key (a bare test unit)
	# keeps the Unit.gd default (0.5), matching pre-loadout behavior.
	if d.has("back_fraction"):
		u.back_speed_fraction = d["back_fraction"]
	# Loadout types: interned LoadoutRegistry ids. The weapon type is the single
	# source of truth for melee reach — its reach_m (metres) -> world units becomes
	# the unit's attack_range, the same scalar combat read before the registry
	# existed, so outcomes are unchanged. A dict without loadout keys (a bare test
	# unit) keeps the Unit defaults (gladius + scutum, the 26-unit baseline reach).
	if d.has("weapon"):
		u.weapon_type_id = d["weapon"]
		var weapon_type: Weapon = LoadoutRegistry.weapon(u.weapon_type_id)
		if weapon_type != null:
			u.attack_range = weapon_type.reach_m * WORLD_UNITS_PER_METER
	if d.has("shield"):
		u.shield_type_id = d["shield"]
	u.training = d.get("training", 0.0)
	u.disciplined = d.get("disciplined", true)
	# Cavalry respond faster — more mobile and battle-conditioned.
	if d["cav"]:
		u.order_response_delay = 0.3
	u.facing = facing
	u.position = pos
	u.field_bounds = FIELD   # so a skirmisher kites without backing off the map
	u.retreat_bounds = FIELD_WITH_MARGIN   # a router may flee this far before it escapes
	_units.add_child(u)
	# Set after add_child() so _ready() has already established the type's base
	# separation_radius for set_formation() to scale from, and set soldiers from
	# max_soldiers. A scenario's optional morale override lands here too.
	u.set_formation(d.get("formation", Unit.FORMATION_NORMAL))
	if d.has("morale"):
		u.morale = float(d["morale"])
	# Apply a starting state if specified (ROUTING for demo recovery scenarios, etc).
	if d.has("starting_state"):
		_apply_starting_state(u, int(d["starting_state"]))
	return u


## Spawn a custom demo matchup from a scenario list (see demos/README.md, "Scenario
## staging"). Each spec: {team, type, x, y, facing?, count?, morale?, formation?}. Tooling
## only — reached solely when DemoInputRecorder sets `scenario` before the battle enters the
## tree; a normal battle leaves `scenario` empty and never calls this. `type` names one of
## the default-loadout entries (Spearmen / Infantry / Archers / Cavalry).
func _spawn_scenario(specs: Array) -> void:
	var loadout := _default_loadout()
	var count_by_type: Dictionary = {}   # per-type running index, so labels read "Cavalry 1", not "Cavalry 2"
	for spec in specs:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var base: Dictionary = _loadout_for_type(loadout, str(spec.get("type", "Infantry")))
		if base.is_empty():
			push_warning("[battle] scenario unit has unknown type '%s'; skipping." % spec.get("type", ""))
			continue
		# Copy the base stats, then layer the spec's optional overrides on top.
		var d: Dictionary = base.duplicate()
		if spec.has("count"):
			d["soldiers"] = int(spec["count"])
		if spec.has("morale"):
			d["morale"] = float(spec["morale"])
		if spec.has("formation"):
			d["formation"] = int(spec["formation"])
		if spec.has("starting_state"):
			d["starting_state"] = int(spec["starting_state"])
		if spec.has("disciplined"):
			d["disciplined"] = bool(spec["disciplined"])
		var team := int(spec.get("team", 0))
		var pos := Vector2(float(spec.get("x", FIELD.size.x * 0.5)), float(spec.get("y", FIELD.size.y * 0.5)))
		# Default facing: toward the enemy half (team 0 faces down, team 1 up), matching the
		# line spawn, unless the spec pins an explicit non-degenerate facing vector [x, y].
		var facing := Vector2.DOWN if team == 0 else Vector2.UP
		if spec.has("facing"):
			var f: Array = spec["facing"]
			if f.size() >= 2 and Vector2(float(f[0]), float(f[1])).length() > 0.0001:
				facing = Vector2(float(f[0]), float(f[1])).normalized()
			else:
				push_warning("[battle] scenario 'facing' must be a non-zero [x, y]; using the team default.")
		var type_name: String = str(d["name"])
		count_by_type[type_name] = int(count_by_type.get(type_name, 0)) + 1
		_spawn_unit(d, team, facing, pos, "%s %d" % [type_name, count_by_type[type_name]])


## First default-loadout entry whose "name" matches `type_name` (case-sensitive), or an empty
## dict if none. Lets a scenario spec name a unit type without duplicating its stat block.
func _loadout_for_type(loadout: Array, type_name: String) -> Dictionary:
	for d in loadout:
		if str(d["name"]) == type_name:
			return d
	return {}


## Apply a starting state to a unit (ROUTING for demos/tests). For demo tooling only;
## a normal battle never calls this. ROUTING starts the disengagement/rally sequence.
func _apply_starting_state(u: Unit, starting_state: int) -> void:
	match starting_state:
		Unit.State.ROUTING:
			u._rout()
		Unit.State.DEAD:
			# Unlike the real death path (Unit._remove_from_play), this leaves the unit
			# in place (not freed) so a demo can show an already-dead body on the field --
			# but it still shouldn't count as a fightable unit, so leave the "units" group
			# same as a real death does.
			u.state = Unit.State.DEAD
			u.remove_from_group("units")
		_:
			# Match _spawn_scenario's unknown-'type' handling: warn loudly instead of a
			# silent no-op, so a typo'd enum value (e.g. IDLE's 0 meant as ROUTING's 3)
			# surfaces immediately instead of shipping a demo that doesn't show what it claims.
			push_warning("[battle] scenario 'starting_state' %d is not ROUTING or DEAD; leaving the unit IDLE." % starting_state)


func _physics_process(_delta: float) -> void:
	# Runs before the Units' own _physics_process (parent precedes children in
	# tree order), so orders and AI for this tick are applied before units act.
	if _ended:
		return

	# Rebuild the shared spatial hash once per tick, before the Units process, so
	# every unit's _separate() this frame queries a current grid (O(n) bucketing
	# instead of an O(n^2) all-pairs scan).
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())

	# Apply this tick's orders: recorded ones during playback, queued live input
	# (also recorded) otherwise.
	if Replay.mode == Replay.Mode.PLAYBACK:
		for cmd in Replay.orders_for_tick(_tick):
			_apply_order_cmd(cmd)
		# Drive the camera from the recorded presentation track so the replay is framed
		# (zoom/pan) as it was played — only when asked (the demo recorder), so in-app
		# Watch Replay keeps free pan/zoom. No track -> static camera, as before.
		if Replay.drive_camera:
			var cam: Dictionary = Replay.camera_for_tick(_tick)
			if not cam.is_empty():
				# Ease toward the recorded framing rather than snapping to it, so jitter in
				# the track (e.g. a recording that followed the shifting melee) is low-passed
				# into a smooth glide.
				var target_pos := Vector2(cam["x"], cam["y"])
				var target_zoom := Vector2(cam["zoom"], cam["zoom"])
				_camera.position = _camera.position.lerp(target_pos, CAMERA_SMOOTHING)
				_camera.zoom = _camera.zoom.lerp(target_zoom, CAMERA_SMOOTHING)
	else:
		for o in _pending_orders:
			Replay.record_order(_tick, o["units"], Vector2(o["x"], o["y"]), o["target"],
					int(o.get("mode", OrderMode.NORMAL)),
					int(o.get("formation", UnitRef.FORMATION_NORMAL)),
					int(o.get("frontage", 0)),
					float(o.get("face", INF)),
					int(o.get("group_attack", GroupAttackMode.FOCUSED)),
					bool(o.get("walk_advance", false)),
					float(o.get("anchor_offset", 0.0)))
			# Apply each order EXACTLY ONCE. Live input is applied the instant it's
			# enqueued (zero-latency feedback / paused preview) and tagged; the drain
			# only records it here, it must not apply it a second time. A second apply
			# corrupts any order whose effect is relative to the state the first apply
			# set -- a rear-move about-face (the second apply cancels the conversio
			# mid-turn) or an arrow nudge (target = position + offset, so the goal
			# chases the crept body). An order NOT applied live (a waypoint append,
			# which is tick-authoritative) still drains-applies here, once.
			if not o.get("applied_live", false):
				_apply_order_cmd(o)
		_pending_orders.clear()
		# Capture the camera each tick so a live recording reproduces what the player saw.
		Replay.record_camera(_tick, _camera.position, _camera.zoom.x)
		# Capture the pointer (cursor / selection / drag-box / armed stance) too, so a demo
		# replay can reproduce what the player did with the mouse, not just the orders.
		if _selection != null:
			var ps: Dictionary = _selection.pointer_state()
			Replay.record_pointer(_tick, ps["cursor"], ps["dragging"], ps["drag_start"],
					ps["selection"], ps["mode"])
			# Capture any gameplay hotkeys pressed since the last tick, so a demo replay
			# can flash the keys on screen alongside the cursor.
			Replay.record_keys(_tick, _selection.take_keys_this_tick())

	# Simulation-tier transitions are part of the deterministic sim too: evaluate the
	# distance triggers and promote/demote BEFORE the units act this tick, so both runs
	# of a replay cross the tier boundary on the same tick from the same positions.
	_tick_tier_transitions()

	# Enemy AI is part of the deterministic sim (not player input): re-run it on
	# the same cadence during playback so it reaches the same decisions.
	if _tick % AI_PERIOD == 0:
		_run_enemy_ai()

	_check_victory()
	_tick += 1


## Per-tick orchestration of the parallel individual-soldier layer (connected to
## physics_frame in _ready, so it runs after every unit has settled this frame): run the
## global friendly-avoidance steering pass (SoldierSpatialHash keyed by the physics
## frame), then step every regiment's persistent soldier bodies one fixed tick — the
## bodies ease toward formation, hold any knockback displacement, and damp away from a
## crowding friendly, all at velocity (no body teleports). Skipped while ended or paused —
## physics_frame keeps emitting while paused even though node callbacks don't run, so
## without the guard the pass would re-run on frozen state. The engaged soldier positions
## feed the per-soldier melee (who is in reach of whom — see SoldierMelee), so the layer
## is authoritative for melee resolution but not for regiment movement/morale.
func _on_soldier_tick() -> void:
	if _ended or get_tree().paused:
		return
	# Both groups: a ROUTING unit leaves "units" for "routers" but its soldier bodies must
	# keep stepping/coupling while it flees, or they freeze at wherever they were the
	# instant it broke -- the render then silently diverges further from the regiment's
	# actual (moving) position every tick it stays routing, until some later state change
	# forces a redraw and the bodies visibly snap to catch up.
	var units: Array = get_tree().get_nodes_in_group("units")
	units.append_array(get_tree().get_nodes_in_group("routers"))
	# Friendly-avoidance steering (velocity bias) and enemy-contact resolution (a direct
	# _sim_body_vel impulse, the continuous counterpart to combat knockback) both run BEFORE
	# the bodies integrate, so this tick's contact is already "carried velocity" by the time
	# step_all_sim_soldiers ramps toward the arrival/feed-forward target. Then couple slides
	# each regiment center toward its soldiers' centroid (phase 5: both friendly collision
	# and now enemy-contact resistance emerge from the soldier layer via this coupling). See
	# SoldierSteering / SoldierEnemyContact / SoldierBodies.
	var delta: float = get_physics_process_delta_time()
	var frame: int = Engine.get_physics_frames()
	SoldierSteering.accumulate(units, frame)
	# Distinct (always-negative) cache key: SoldierSpatialHash.rebuild is idempotent per key
	# within a tick, and this pass gathers a different position set (cross-team engaged
	# pairs, no friendly-contact-tier expansion) than SoldierSteering's own rebuild above, so
	# it can't share that key without silently reusing the wrong grid.
	SoldierEnemyContact.accumulate(units, -frame - 1)
	UnitRef.step_all_sim_soldiers(units, delta)
	UnitRef.couple_all_sim_soldiers(units, delta)
	# Advance in-flight volleys and land any that arrived this tick (delivers their casualties
	# in launch order, no RNG -- see ProjectileField). After the bodies settle so a landing
	# reads current positions.
	if ProjectileField.active != null:
		ProjectileField.active.step(delta, self)


## Apply a live-input order the instant it's enqueued (zero-latency feedback and
## paused preview) and tag it so the physics tick that drains _pending_orders
## records it but does NOT apply it again. Each order thus takes effect EXACTLY
## once, on the same deterministic _apply_order_cmd path as a replayed order. The
## tag lives only on the in-memory _pending_orders dict; Replay.record_order copies
## explicit fields, so it never reaches the recorded stream (and a PLAYBACK order,
## untagged, still applies once via orders_for_tick).
func _apply_order_live(cmd: Dictionary) -> void:
	_apply_order_cmd(cmd)
	cmd["applied_live"] = true


## Called by SelectionManager when the player issues a right-click order. The order
## is queued for the next physics tick (which records it for replay) and applied
## immediately so it takes effect with no input latency and the order overlay
## reflects the new destination right away — including while paused, when the tick
## that drains _pending_orders isn't running. _apply_order_live tags it so the tick
## records it without a second apply, keeping live and replayed orders on one
## deterministic path with exactly-once application.
func enqueue_order(uids: Array, world_pos: Vector2, target_uid: int,
		order_mode: int = OrderMode.NORMAL,
		group_attack: int = GroupAttackMode.FOCUSED,
		gait: int = -1,
		knockback_indefinite: bool = false) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": world_pos.x,
		"y": world_pos.y,
		"target": target_uid,
		"mode": order_mode,
		"reform": Settings.reform_before_move,
		"walk_advance": Settings.walk_advance,
		"group_attack": group_attack,
		"gait": gait,
		"knockback_indefinite": knockback_indefinite,
	}
	_pending_orders.append(cmd)
	# A waypoint append is tick-authoritative (its point is derived from positions at
	# the tick, matching replay), so leave it untagged and let the tick apply it once.
	# Every other order applies live now and is tagged so the tick won't repeat it.
	if target_uid != ORDER_APPEND_WAYPOINT:
		_apply_order_live(cmd)


## Change the formation mode for a set of units. Recorded so replays stay exact.
func enqueue_formation(uids: Array, formation: int) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": 0.0,
		"y": 0.0,
		"target": ORDER_FORMATION_ONLY,
		"mode": OrderMode.NORMAL,
		"formation": formation,
	}
	_pending_orders.append(cmd)
	_apply_order_live(cmd)


## Change the durable stance of a set of units in place -- no movement, no target: the
## order_mode (`stance` >= 0; -1 leaves it unchanged) and/or the intra-unit rank-relief
## mode (`rank_relief`, a RankRelief value; LEAVE keeps each unit's setting). Recorded so
## replays stay exact. No gesture drives this yet -- the stance hotkeys still arm a mode
## for the NEXT move/attack order -- but the order path exists so the mode layer is
## reachable from the same recorded, exactly-once dispatch as every other command.
## `knockback_indefinite` is KNOCKBACK_FOCUS's own per-order push-distance parameter (see
## Unit.knockback_push_indefinite): false pushes a struck body just clear of the battle
## line, true pushes it much further. Ignored for every other stance.
func enqueue_stance(uids: Array, stance: int = -1, rank_relief: int = RankRelief.LEAVE,
		knockback_indefinite: bool = false) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": 0.0,
		"y": 0.0,
		"target": ORDER_STANCE_ONLY,
		"mode": stance,
		"frontage": rank_relief,
		"knockback_indefinite": knockback_indefinite,
	}
	_pending_orders.append(cmd)
	_apply_order_live(cmd)


## Widen (delta > 0) or narrow (delta < 0) the frontage of a set of units by
## `delta` files each. Each unit steps from its OWN current frontage to an absolute
## target (so a mixed selection keeps its relative widths), emitting one command per
## unit. The absolute (not relative) target is recorded so replays stay exact and
## keeps the command safe to re-derive from any starting frontage.
func enqueue_frontage(uids: Array, delta: int) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	for uid in uids:
		var u: Unit = _unit_by_uid(int(uid))
		if u == null:
			continue
		var files: int = clampi(UnitFormation.frontage(u) + delta, 1, maxi(1, u.max_soldiers))
		var cmd := {
			"units": [uid],
			"x": 0.0,
			"y": 0.0,
			"target": ORDER_FRONTAGE_ONLY,
			"mode": OrderMode.NORMAL,
			"frontage": files,
		}
		_pending_orders.append(cmd)
		_apply_order_live(cmd)


## Arrow-key nudge: order each unit a small fixed-distance drill step to its own
## `dir` (LEFT / RIGHT side-step, BACK back-step, or FORWARD forward-step), holding
## facing throughout.
## Recorded (the direction rides the frontage field) so replays reproduce it, and
## applied immediately for zero-latency feedback like every other order.
func enqueue_nudge(uids: Array, dir: int) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	if uids.is_empty():
		return
	var cmd := {
		"units": uids,
		"x": 0.0,
		"y": 0.0,
		"target": ORDER_NUDGE,
		"mode": OrderMode.NORMAL,
		"frontage": dir,
	}
	_pending_orders.append(cmd)
	_apply_order_live(cmd)


## File-doubling maneuvers (duplicatio / explicatio): reshape each unit's frontage by
## a whole factor instead of a single file. `direction` > 0 is EXPLICATIO -- each file
## splits and the rear half steps out laterally, doubling the frontage and halving the
## depth (UnitFormation.widened_files, capped at a single rank). `direction` < 0 is
## DUPLICATIO -- alternate files tuck in behind their neighbours, halving the frontage
## and doubling the depth (UnitFormation.narrowed_files, floored at one column). Each
## reshaped width is resolved per unit from its OWN current frontage and emitted as the
## same absolute ORDER_FRONTAGE_ONLY command the [ / ] resize uses, so the soldier bodies
## ease into the reshaped slots at velocity (no teleport) and the maneuver rides the
## replay stream exactly like a manual resize.
##
## `anchor` (UnitFormation.Anchor) picks which flank stays fixed: CENTRE (default) is
## the plain symmetric widen/narrow above -- and RE-CENTRES the block, discarding any
## earlier anchor shift, exactly like the pre-existing [ / ] resize always has; LEFT/
## RIGHT hold that edge in place and let the whole width change land on the opposite
## flank -- an asymmetric explicatio/duplicatio for when a flank must stay pinned to
## terrain or a neighbour. `anchor_shift` always computes the shift a SINGLE widen from
## a centred block needs, so a LEFT/RIGHT anchor composes it on top of the unit's
## CURRENT offset (unit.frontage_anchor_offset) rather than replacing it -- otherwise a
## second anchored widen on the same unit would recompute the shift as if starting from
## centre and the "held" flank would jump. The resulting absolute offset is carried on
## the same command, so re-applying it on the tick is idempotent and it rides the replay
## stream exactly like the centred maneuver.
func enqueue_file_double(uids: Array, direction: int,
		anchor: int = UnitFormation.Anchor.CENTRE) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK or direction == 0:
		return
	for uid in uids:
		var u: Unit = _unit_by_uid(int(uid))
		if u == null:
			continue
		var current: int = UnitFormation.frontage(u)
		var files: int
		if direction > 0:
			files = UnitFormation.widened_files(u.soldiers, current)
		else:
			files = UnitFormation.narrowed_files(current)
		files = clampi(files, 1, maxi(1, u.max_soldiers))
		var spacing: float = Unit.FORMATION_SPACING * u.spacing_scale
		var anchor_offset: float
		if anchor == UnitFormation.Anchor.CENTRE:
			anchor_offset = 0.0
		else:
			anchor_offset = u.frontage_anchor_offset \
				+ UnitFormation.anchor_shift(current, files, spacing, anchor)
		var cmd := {
			"units": [uid],
			"x": 0.0,
			"y": 0.0,
			"target": ORDER_FRONTAGE_ONLY,
			"mode": OrderMode.NORMAL,
			"frontage": files,
			"anchor_offset": anchor_offset,
		}
		_pending_orders.append(cmd)
		_apply_order_live(cmd)


## Wheel (circumductio): each selected unit swings 90° about a fixed flank file (`dir` = -1
## wheel-left / +1 wheel-right). The direction rides in the "x" field. Recorded so replays
## reproduce the arc — a wheel moves the regiment, which the sim reads (see ORDER_WHEEL).
func enqueue_wheel(uids: Array, dir: int) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": float(dir),
		"y": 0.0,
		"target": ORDER_WHEEL,
		"mode": OrderMode.NORMAL,
	}
	_pending_orders.append(cmd)
	_apply_order_live(cmd)


## World-space offset for a nudge of `dir` given a unit's `facing`. LEFT / RIGHT
## are perpendicular to facing (a side-step); BACK is straight opposite facing (a
## back-step); FORWARD is straight along facing (a forward step). Each is
## NUDGE_DISTANCE long. Pure/static so it's unit-testable.
static func nudge_offset(facing: Vector2, dir: int) -> Vector2:
	var fwd: Vector2 = facing.normalized() if facing.length() > 0.01 else Vector2.UP
	var perp := Vector2(-fwd.y, fwd.x)   # unit's right-hand side in world space
	match dir:
		NudgeDir.LEFT:
			return -perp * NUDGE_DISTANCE
		NudgeDir.RIGHT:
			return perp * NUDGE_DISTANCE
		NudgeDir.BACK:
			return -fwd * NUDGE_DISTANCE
		NudgeDir.FORWARD:
			return fwd * NUDGE_DISTANCE
		_:
			return Vector2.ZERO


## Drag-to-form-up: move a single unit to `center` and deploy it there facing
## `face` (radians) with `frontage` files -- the front rank ends up along the
## dragged flank line. A plain move order (target -1) carrying the extra face +
## frontage, recorded so replays reproduce the deploy.
func enqueue_form_up(uids: Array, center: Vector2, face: float, frontage: int,
		order_mode: int = OrderMode.NORMAL, knockback_indefinite: bool = false) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": center.x,
		"y": center.y,
		"target": -1,
		"mode": order_mode,
		"frontage": frontage,
		"face": face,
		"reform": Settings.reform_before_move,
		"walk_advance": Settings.walk_advance,
		"knockback_indefinite": knockback_indefinite,
	}
	_pending_orders.append(cmd)
	_apply_order_live(cmd)


## Apply one order (move or attack) to its units. Shared by live play and
## playback so both produce identical results.
func _apply_order_cmd(cmd: Dictionary) -> void:
	var target_uid: int = int(cmd["target"])
	# Formation-change-only: update each unit's formation and separation footprint,
	# leaving all movement and order-mode state untouched.
	if target_uid == ORDER_FORMATION_ONLY:
		var fm: int = int(cmd.get("formation", UnitRef.FORMATION_NORMAL))
		for uid in cmd["units"]:
			var u: Unit = _unit_by_uid(int(uid))
			if u != null:
				u.set_formation(fm)
				# Instantaneous mode write: only occupy the queue when the unit is idle.
				# Replacing a live order would interrupt the maneuver/march it drives
				# (phase 2), and the durable mode change is already transcript-visible
				# via the formation field itself.
				if u.current_order == null:
					u.set_current_order(Order.new_formation(fm))
		return
	# Frontage-resize-only: set each unit's file count (and anchor shift, for an
	# asymmetric explicatio/duplicatio -- 0.0 for the plain [ / ] resize) to the
	# absolute target, leaving movement and order-mode state untouched. Absolute so
	# re-applying the pending order on the tick is a no-op (idempotent), matching
	# move/formation.
	if target_uid == ORDER_FRONTAGE_ONLY:
		var files: int = int(cmd.get("frontage", 0))
		if files > 0:
			var anchor_offset: float = float(cmd.get("anchor_offset", 0.0))
			for uid in cmd["units"]:
				var u: Unit = _unit_by_uid(int(uid))
				if u != null:
					u.set_frontage(files, anchor_offset)
					# Same idle-only queue write as the formation branch above.
					if u.current_order == null:
						u.set_current_order(Order.new_frontage(files, anchor_offset))
		return
	# Stance-change-only: write the durable order_mode and/or rank-relief mode on each
	# unit, leaving all movement and formation state untouched. Both are instantaneous
	# mode writes (the write IS the completion), so like the formation branch the queue
	# is only occupied when the unit is idle -- a live order keeps running and the mode
	# change is already transcript-visible via the order_mode / rank_relief fields.
	if target_uid == ORDER_STANCE_ONLY:
		var stance: int = int(cmd.get("mode", -1))
		var rank_toggle: int = int(cmd.get("frontage", RankRelief.LEAVE))
		for uid in cmd["units"]:
			var u: Unit = _unit_by_uid(int(uid))
			if u == null or u.state == UnitRef.State.DEAD:
				continue
			if stance >= 0:
				u.order_mode = stance
				# KNOCKBACK_FOCUS's own per-order parameter: how far to push a struck body
				# (see Unit.knockback_push_indefinite). Only meaningful for this stance --
				# refreshed every time the stance is (re)issued so the player can pick
				# either variant each time, rather than it being a fixed/global setting.
				if stance == OrderMode.KNOCKBACK_FOCUS:
					u.knockback_push_indefinite = bool(cmd.get("knockback_indefinite", false))
				# A stance carrying no ward is not a guard duty: SUPPORT only arms via a
				# targeted support order, so a bare stance write can't strand the unit in
				# the support tick with no ward (it would revert next think anyway).
				if stance != OrderMode.SUPPORT:
					u.support_target = null
				# Entering cycle-charge drives in first, matching a fresh move/attack order.
				if stance == OrderMode.CYCLE_CHARGE:
					u._cycle_recharging = false
			if rank_toggle == RankRelief.ON:
				u.rank_relief = true
			elif rank_toggle == RankRelief.OFF:
				u.rank_relief = false
			if u.current_order == null:
				u.set_current_order(Order.new_stance(stance, rank_toggle))
		return
	# Arrow-key nudge: each unit steps a small fixed distance to its own side/rear,
	# holding facing (ordered_facing set), leaving stance and formation untouched. A
	# fresh move order, so it clears any queued route. The direction rides "frontage".
	if target_uid == ORDER_NUDGE:
		var dir: int = int(cmd.get("frontage", 0))
		for uid in cmd["units"]:
			var u: Unit = _unit_by_uid(int(uid))
			if u == null or u.state == UnitRef.State.DEAD:
				continue
			# Don't yank a unit out of melee or a rout with a drill step.
			if u.state == UnitRef.State.FIGHTING or u.state == UnitRef.State.ROUTING:
				continue
			var offset: Vector2 = nudge_offset(u.facing, dir)
			if offset == Vector2.ZERO:
				continue
			# Install the order first: set_current_order interrupts any maneuver the old
			# order had in flight (folding a partial in-place turn), and a rear march --
			# or a queued route -- parked on that order's queue dies with it.
			u.set_current_order(Order.new_nudge(dir))
			u.target_enemy = null
			u.support_target = null
			u.deploy_facing = Vector2.ZERO
			u._reform_timer = 0.0
			u._reform_until_settled = false
			u._reform_on_arrival = false   # a drill step's arrival shouldn't fire a stale reform
			u.ordered_facing = u.facing   # hold facing: side-step / back-step, no pivot
			u.move_target = u.position + offset
			u.has_move_target = true
			u.start_order_response()
		return
	# Wheel: swing each unit 90° about a fixed flank file. The direction rides in "x".
	# Unit.wheel() creates and installs its own WHEEL order (with the swing goal and the
	# captured hinge on it) when the unit stands idle, and no-ops otherwise -- a refused
	# wheel leaves whatever order is running untouched.
	if target_uid == ORDER_WHEEL:
		var wheel_dir: int = int(round(float(cmd["x"])))
		for uid in cmd["units"]:
			var u: Unit = _unit_by_uid(int(uid))
			if u != null:
				u.wheel(wheel_dir)
		return
	# Merge: the target is the primary and is itself one of the ordered units
	# (a relief's target is a friendly OUTSIDE the selection — that's the
	# disambiguator). Handle it first, then fall through to attack/relief/move.
	if target_uid >= 0 and _uids_contain(cmd["units"], target_uid):
		_apply_merge(cmd["units"], target_uid)
		return
	# A move whose target is the append sentinel queues a waypoint instead of
	# replacing the route; any other order resets the queue first.
	var append: bool = target_uid == ORDER_APPEND_WAYPOINT
	# The order's stance, stamped on each ordered unit below for the smart-
	# order behaviours to consume. Defaults to NORMAL for older replays / merges.
	var mode: int = int(cmd.get("mode", OrderMode.NORMAL))
	# The movement gait (WALK/JOG/RUN/SPRINT) for MOVE orders. Defaults to -1 (AUTO,
	# matching Order.gait's own default) for older replays / merges / programmatic
	# orders where the field is not set, so they keep the old walk/jog/sprint logic
	# instead of being silently forced onto a fixed gait.
	var gait: int = int(cmd.get("gait", -1))
	# The target uid may be an enemy (attack) or a friendly (line relief); a
	# plain move has no target. Resolve it and dispatch per ordered unit by team.
	var target_unit: Unit = _unit_by_uid(target_uid) if target_uid >= 0 else null
	var is_move: bool = target_unit == null
	var dest := Vector2(float(cmd["x"]), float(cmd["y"]))
	# Formation cohesion: a move order translates the regiment as a block. Each
	# unit keeps its offset from the group's current centroid, so the formation
	# holds its shape (line stays a line) instead of collapsing and re-packing
	# into a fresh grid. Computed from live positions, so live play and playback
	# (which reach the same positions at this tick) stay in lockstep.
	var centroid := Vector2.ZERO
	if is_move:
		centroid = _centroid_of_uids(cmd["units"])
	# In distributed attack mode, pre-sort all live enemies by proximity to the clicked
	# target so each ordered unit gets its own assignment. Ties broken by uid for replay
	# determinism. Falls back to focused (all share target_unit) when the list is empty.
	var attack_targets: Array = []
	if cmd.get("group_attack", GroupAttackMode.FOCUSED) == GroupAttackMode.DISTRIBUTED \
			and target_unit != null and not is_move:
		# Scan both "units" and "routers" --- a routing (broken or shattered) enemy is
		# still a live, fightable candidate (see UnitTargeting.nearest_enemy's
		# include_routing); it just lives in the other group while fleeing.
		for group in ["units", "routers"]:
			for node in get_tree().get_nodes_in_group(group):
				var candidate: Unit = node as Unit
				if candidate == null or candidate.team != target_unit.team \
						or candidate.state == Unit.State.DEAD:
					continue
				attack_targets.append(candidate)
		var ref_pos: Vector2 = target_unit.position
		attack_targets.sort_custom(func(a: Unit, b: Unit) -> bool:
			var da: float = a.position.distance_to(ref_pos)
			var db: float = b.position.distance_to(ref_pos)
			return da < db if da != db else a.uid < b.uid)
	var relieved: bool = false
	var relief_foe: Unit = null
	for uid in cmd["units"]:
		var u: Unit = _unit_by_uid(int(uid))
		if u == null:
			continue
		# A fresh order (anything but a waypoint append) discards the queued route --
		# each branch below replaces the orders queue, and the route lives there now --
		# and sets the unit's stance; an append continues the current march/stance.
		# Clearing any prior support ward means a plain order drops the guard
		# duty; a SUPPORT order re-sets it in the friendly-target branch below.
		if not append:
			u.order_mode = mode
			# Same per-order push-distance parameter as the stance-only branch above,
			# carried on an ordinary move/attack order too (arming KNOCKBACK_FOCUS then
			# issuing a move/attack is the normal way to use it).
			if mode == OrderMode.KNOCKBACK_FOCUS:
				u.knockback_push_indefinite = bool(cmd.get("knockback_indefinite", false))
			u.walk_advance = bool(cmd.get("walk_advance", false))
			u.support_target = null
			# A fresh order restarts the cycle-charge loop in its charging phase, so a
			# newly-ordered unit drives in rather than resuming a stale pull-back.
			u._cycle_recharging = false
			# Any fresh order drops a deploy facing a prior form-up parked; the form-up
			# move branch below re-sets it. So attack / support / relief / plain move all
			# clear it, and a unit can't pivot to a stale heading on arrival.
			u.deploy_facing = Vector2.ZERO
			# Drop any side-step hold from a prior order; the plain-move branch below
			# re-sets it when this order is itself a small lateral shift.
			u.ordered_facing = Vector2.ZERO
			# A new order always cancels any in-progress reform from the previous one --
			# the hold, its settle-early mode, and the deferred on-arrival case
			# (start_order_response squares the grid itself). A reform still parked
			# behind a rear-move march lives on the old Order and dies when
			# set_current_order below replaces it.
			u._reform_timer = 0.0
			u._reform_until_settled = false
			u._reform_on_arrival = false
		if target_unit != null and target_unit != u and target_unit.team != u.team:
			if attack_targets.is_empty():
				u.target_enemy = target_unit
			else:
				var slot: int = cmd["units"].find(uid)
				u.target_enemy = attack_targets[slot % attack_targets.size()]
			u.has_move_target = false
			u.set_current_order(Order.new_attack(u.target_enemy.uid, mode))
		elif target_unit != null and target_unit != u and target_unit.team == u.team:
			if mode == OrderMode.SUPPORT:
				# Support: guard the targeted friendly. Every ordered unit shadows
				# the same ward and engages threats near it — no relief swap.
				u.support_target = target_unit
				u.target_enemy = null
				u.has_move_target = false
				u.set_current_order(Order.new_support(target_unit.uid))
			elif not relieved:
				# Relief: the first reliever swaps with the tired unit; any others
				# just advance on the same fight so they don't shove the retreating unit.
				# Install the RELIEF order first (interrupting whatever ran before), then
				# arm the swap on it -- the order owns the pass-through link and the
				# tired unit's retreat becomes a queue-visible MOVE order of its own.
				var relief_order := Order.new_relief(target_unit.uid)
				u.set_current_order(relief_order)
				UnitRelief.begin(u, target_unit, relief_order)
				# Capture the foe UnitRelief.begin() resolved (it clears the tired
				# unit's target_enemy, so later relievers can't read it from there).
				relief_foe = u.target_enemy
				relieved = true
				# Skip the order-response delay for the primary reliever — it needs
				# to advance immediately or the tired unit retreats into an uncovered gap.
				continue
			else:
				u.target_enemy = relief_foe
				u.has_move_target = false
				if relief_foe != null:
					u.set_current_order(Order.new_attack(relief_foe.uid, mode))
		else:
			var point: Vector2 = dest + (u.position - centroid)   # formation move
			u.target_enemy = null
			if append:
				# Queue the leg -- the queued MOVE order IS the waypoint (phase 3). An
				# idle unit starts marching it now (append_order made it current); a
				# busy one continues its current order and the leg commits when it is
				# promoted (retire_current_order -> _start_promoted_move).
				var leg := Order.new_move(point, mode, gait, false)
				u.append_order(leg)
				if u.current_order == leg and not u.has_move_target:
					u.move_target = point
					u.has_move_target = true
			else:
				# Choose the drill maneuver for a plain move (a form-up commands its own
				# facing, so it never side-steps). A small lateral shift holds facing and
				# shuffles sideways instead of centre-pivoting to face travel and back.
				var move_vec: Vector2 = point - u.position
				var side_step: bool = not cmd.has("face") \
						and UnitManeuver.is_sidestep(u.facing, move_vec)
				# A short rear-sector move reads as a nudge, not a repositioning march --
				# it holds facing and shuffles backward, the same as a side-step, rather
				# than about-facing for a move that barely covers any ground.
				var back_step: bool = not cmd.has("face") and not side_step \
						and UnitManeuver.is_backstep(u.facing, move_vec)
				if side_step or back_step:
					u.ordered_facing = u.facing
				# A longer move into the rear sector about-faces (conversio) in place, then
				# marches to the destination facing it -- rather than pivoting the whole
				# block 180° about its centre. A form-up, a side-step, a back-step, and a
				# fighting unit (conversio is blocked in melee) all keep the normal march.
				var rear_move: bool = not cmd.has("face") and not side_step and not back_step \
						and u.state != UnitRef.State.FIGHTING \
						and UnitManeuver.is_rear_move(u.facing, move_vec)
				# Drag-to-form-up: apply frontage/facing immediately so soldiers begin
				# adjusting during the reform phase rather than after the march starts.
				if cmd.has("face"):
					u.deploy_facing = Vector2.from_angle(float(cmd["face"]))
					if cmd.has("frontage"):
						u.set_frontage(int(cmd["frontage"]))
				# Facing is not snapped here: an orderly move centre-pivots gradually toward
				# its heading in Unit (turning in place during the reform hold and as it
				# marches), so the ranks come onto the new bearing in good order rather
				# than the whole line flipping its facing at order time.
				# Reform timing rides the recorded "reform" field on the Order: for a plain
				# move it arms the reform-before-move hold below; for a rear move it times
				# the composite's reform phase (see Unit._finish_order_turn).
				var order := Order.new_move(point, mode, gait, gait >= UnitRef.GAIT_RUN)
				order.reform = bool(cmd.get("reform", false))
				# Install the order first: set_current_order interrupts whatever maneuver
				# the old order had in flight (a standing drill turn folds and settles; a
				# wheel stops mid-swing), so a fresh move always starts from consistent
				# ground -- live play and playback take this same path.
				u.set_current_order(order)
				var about_faced: bool = false
				if rear_move:
					# Park the destination on the order and about-face in place; _think
					# starts the march when the turn completes. has_move_target stays false
					# so the turn isn't cancelled. begin_about_face refuses before the
					# bodies seed (a spawn-tick order) -- fall back to a plain march then.
					u.has_move_target = false
					about_faced = u.begin_about_face(order)
				# A rear move that armed the about-face parks its march for _think to commit
				# on completion; every other move commits here (reform-hold or immediate).
				# Fighting units bypass the hold in _think and commit immediately.
				if not about_faced and order.reform:
					u._reform_target = point
					u._reform_timer = UnitRef.REFORM_DURATION
					u.has_move_target = false   # stop any prior march while reforming
				elif not about_faced:
					u.move_target = point
					u.has_move_target = true
		if not append:
			u.start_order_response()


func _uids_contain(uids: Array, target: int) -> bool:
	for u in uids:
		if int(u) == target:
			return true
	return false


## Merge every other ordered unit into the primary. Same-team only.
func _apply_merge(uids: Array, primary_uid: int) -> void:
	var primary: Unit = _unit_by_uid(primary_uid)
	if primary == null:
		return
	for uid in uids:
		var u: Unit = _unit_by_uid(int(uid))
		if u == null or u == primary or u.team != primary.team:
			continue
		# Don't fold a routing or dead unit into a steady regiment (a unit can rout
		# between selecting it and the merge applying); it's no longer a valid body.
		if u.state == UnitRef.State.ROUTING or u.state == UnitRef.State.DEAD:
			continue
		primary.absorb(u)


## Average of a set of positions — the anchor a formation move translates from,
## so the block keeps its shape. Returns ZERO for an empty set.
static func formation_centroid(positions: Array[Vector2]) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in positions:
		sum += p
	return sum / float(positions.size())


## Formation centroid of the live positions of the given unit uids (the anchor a
## formation move translates from). Shared by _apply_order_cmd and the overlay's
## pending-append preview so both compute the same per-unit offset.
func _centroid_of_uids(uids: Array) -> Vector2:
	var ps: Array[Vector2] = []
	for uid in uids:
		var cu: Unit = _unit_by_uid(int(uid))
		if cu != null:
			ps.append(cu.position)
	return formation_centroid(ps)


## Points for a unit's not-yet-applied waypoint appends, in queue order.
## While the sim is paused _physics_process doesn't drain _pending_orders, so an
## appended leg isn't queued on the unit's orders until the player unpauses; the order
## overlay calls this to preview those queued legs without mutating state. Each
## point is derived exactly as _apply_order_cmd will (same formation centroid),
## and positions are frozen while paused, so the preview matches the eventual leg.
func pending_append_points_for(u: Unit) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for cmd in _pending_orders:
		if int(cmd["target"]) != ORDER_APPEND_WAYPOINT:
			continue
		if not _uids_contain(cmd["units"], u.uid):
			continue
		var dest := Vector2(float(cmd["x"]), float(cmd["y"]))
		points.append(dest + (u.position - _centroid_of_uids(cmd["units"])))
	return points


func _unit_by_uid(uid: int) -> UnitRef:
	var u = _by_uid.get(uid)
	return u if (u != null and is_instance_valid(u)) else null


## The current simulation tick. Used by the demo-pointer overlay to look up the recorded
## cursor/selection state for the frame being drawn.
func current_tick() -> int:
	return _tick


## Public uid -> unit lookup (alive units only, else null). The demo-pointer overlay
## resolves the recorded selection's uids to the units to highlight.
func unit_by_uid(uid: int) -> UnitRef:
	return _unit_by_uid(uid)


## Evaluate the per-formation simulation-tier triggers and perform any transitions
## (docs/large-scale-simulation-design.md, phase 3). Each fightable unit's distance to the
## nearest enemy formation feeds the phase-1 hysteresis predicates: a far-tier unit whose
## nearest enemy closes inside PROMOTE_RANGE reconstructs its per-soldier state
## (TierTransition.promote, seeded off uid/tick/battle seed); a close-tier unit whose
## nearest enemy recedes past DEMOTE_RANGE — and that holds no in-flight per-soldier
## context (TierTransition.can_demote) — collapses to its aggregate fields. Routers are
## ignored on both sides of the check: a routing unit is not a fight-relevant contact,
## and it keeps its own tier until it rallies back into "units". Runs every tick over the
## live units in tree order — a pure function of already-serialized positions, so both
## runs of a replay transition the same units on the same ticks.
func _tick_tier_transitions() -> void:
	var all_units: Array = get_tree().get_nodes_in_group("units")
	for node in all_units:
		var u = node as UnitRef
		if u == null or u.state == UnitRef.State.DEAD:
			continue
		var nearest_pos := Vector2.ZERO
		var nearest_dist: float = INF
		for other in all_units:
			var e = other as UnitRef
			if e == null or e.team == u.team or e.state == UnitRef.State.DEAD:
				continue
			var d: float = u.position.distance_to(e.position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_pos = e.position
		if nearest_dist == INF:
			continue   # no enemy in play: hold the current tier (the victory check ends the battle)
		if u.tier == FormationTier.FAR:
			if FormationTier.should_promote(u.position, nearest_pos):
				TierTransition.promote(u, _tick, Replay.seed_value)
		elif TierTransition.can_demote(u) and FormationTier.should_demote(u.position, nearest_pos):
			TierTransition.demote(u)


## Battle AI phases 1-2 (docs/battle-ai-design.md): every AI-controlled (team 1) unit gets
## a unit leader (UnitLeader.decide) that reads the current sim state -- the omniscient
## placeholder perception phase 1 uses -- and returns at most one order-command Dictionary,
## which is applied through _apply_order_cmd, the SAME single apply site a player order
## goes through. No unit state is written directly here, in UnitLeader, or in Subcommander --
## closing the backdoor the old direct `u.target_enemy = nearest` write left open (see the
## design doc's "Today's AI is a backdoor" section). Phase 2 adds one subcommander per team,
## computed once per AI tick over the whole team-1 group (docs/battle-ai-design.md phase 2's
## "start static" group assignment -- see Subcommander's own class doc); its directives are
## handed to each unit leader alongside the same perception, never applied on their own.
## Deterministic: a pure function of already-serialized unit state, decided in uid order, so
## live play and replay reach identical decisions.
func _run_enemy_ai() -> void:
	var all_units: Array = get_tree().get_nodes_in_group("units")
	var team1: Array = _team_units(1)
	var directives: Dictionary = Subcommander.decide_group(team1, all_units)
	for u in team1:
		var directive: Dictionary = directives.get(u.uid, {})
		var cmd: Dictionary = UnitLeader.decide(u, all_units, directive)
		if not cmd.is_empty():
			_apply_order_cmd(cmd)


func _team_units(team: int) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u = node as UnitRef
		if u != null and u.team == team:
			out.append(u)
	return out


## Whether a team still has any body on the field that could yet fight — a fightable
## unit OR a routing one. A routing unit has left the "units" group for "routers", but
## it is still on the field and may rally back into the fight, so it keeps its team in
## play. Only once a team's last body has truly gone (died, shattered, or left the field)
## does it fall out of play. Used by _check_victory so a team isn't declared defeated
## while its final unit is merely routing and might still recover.
func _team_in_play(team: int) -> bool:
	for group in ["units", "routers"]:
		for node in get_tree().get_nodes_in_group(group):
			var u = node as UnitRef
			if u != null and u.team == team:
				return true
	return false


## How many bodies a team still has on the field: fightable units AND still-routing
## ones, the counting twin of _team_in_play. A router at battle end is a fugitive,
## not a casualty — most of a broken army escapes the field unless pursued — so the
## campaign result counts it as a survivor instead of letting it vanish from the
## army record. Keeps the survivor report agreeing with the victory check about
## which units exist.
func _team_survivors(team: int) -> int:
	var count := 0
	for group in ["units", "routers"]:
		for node in get_tree().get_nodes_in_group(group):
			var u = node as UnitRef
			if u != null and u.team == team:
				count += 1
	return count


func _check_victory() -> void:
	# Drill mode has no opponent, so "no enemies" is never a win — the rehearsal runs on.
	if drill_mode:
		return
	# A team is still contesting the battle while it has any body on the field — a
	# fightable unit or a routing one that might rally. Waiting on routers is bounded:
	# each rout resolves (rally or shatter) within ROUT_TIME, so a both-sides-only-routers
	# state can't stall the outcome — it just defers the call until the routers settle.
	var p_alive: bool = _team_in_play(0)
	var e_alive: bool = _team_in_play(1)
	if not p_alive and not e_alive:
		_end("Mutual Destruction")
	elif not e_alive:
		_end("Victory!")
	elif not p_alive:
		_end("Defeat")


func _end(text: String) -> void:
	_ended = true
	# Persist the just-played battle so it can be replayed. Playback doesn't
	# re-save (the file already exists).
	if Replay.mode == Replay.Mode.RECORD:
		Replay.save(text, _tick)
	# Report the outcome back to the campaign if this clash was launched from the map,
	# before the HUD's "Return to Campaign" button can act on it.
	if CampaignBattle.active:
		_report_campaign_result(text)
	# Fanfare on a win; the somber sting otherwise. A mutual-destruction draw
	# isn't a win either, so it shares the defeat sound.
	Sfx.play(&"victory" if text == "Victory!" else &"defeat")
	_hud.show_end(text)


## Translate the battle's end state into a campaign result: the winning side's
## surviving units scale back to campaign army strength. Survivors count
## still-routing units (see _team_survivors) so a battle ending mid-rout doesn't
## drop the fugitive from the campaign. Replay playback doesn't overwrite a
## result the live battle already reported.
func _report_campaign_result(text: String) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var pending: Dictionary = CampaignBattle.pending
	if text == "Victory!":
		CampaignBattle.result = {
			"attacker_won": true,
			"survivors": CampaignBattle.survivors_strength(
					int(pending.get("attacker_strength", 1)), _camp_atk_spawned, _team_survivors(0)),
		}
	elif text == "Defeat":
		CampaignBattle.result = {
			"attacker_won": false,
			"survivors": CampaignBattle.survivors_strength(
					int(pending.get("defender_strength", 1)), _camp_dfn_spawned, _team_survivors(1)),
		}
	else:
		# Mutual destruction: the assault fails and the province holds with a token
		# garrison (mirrors auto-resolve's guaranteed >= 1 survivor).
		CampaignBattle.result = {"attacker_won": false, "survivors": 1}
