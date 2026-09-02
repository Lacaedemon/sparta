extends Node
## Headless **scripted-input** demo recorder (see demos/README.md). Set as the main scene
## under Godot's Movie Maker mode (`--write-movie`). It reads an input script named in the
## SPARTA_DEMO_INPUT environment variable — a deterministic list of mouse clicks/drags and
## keystrokes stamped with the physics tick they fire on — and drives a LIVE Battle by
## injecting those as real InputEvents through the SelectionManager's normal input path,
## while Movie Maker records what's drawn. So the clip is produced from the same code a
## player's mouse/keyboard would drive (a demo doubles as an input smoke test).
##
## This is tooling: nothing in the live game references it, and it changes no simulation
## code. It is the counterpart to DemoRunner.gd, which only plays back a saved replay.

const BATTLE_SCENE := "res://scenes/Battle.tscn"
# Ticks a press->release drag is spread over, so the live form-up / box-select preview
# visibly animates rather than snapping in a single frame.
const DRAG_TICKS := 16
# Wall-clock cap for a frame-capture run, so it can't hang if a frame is armed past a battle's
# end (the sim freezes its tick then). Generous — a normal capture finishes in a few seconds.
const CAPTURE_TIMEOUT_SEC := 60.0

var _sel: Node = null
var _battle: Node = null
var _hud: Node = null   # forward a scripted "key" step here too -- see _fire()'s "key" case
var _cam: Camera2D = null
var _camera_track: Array = []          # keyframes [{tick,x,y,zoom}], interpolated per tick; empty = default camera
var _by_tick: Dictionary = {}          # tick -> Array of expanded input events
var _drill: bool = false               # solo/no-opponent rehearsal (input script "drill" field)
var _scenario: Array = []              # custom unit matchup (input script "scenario" field)
# Debug/testing mode: the player commands every team, and team 1's AI never runs.
# From the input script's optional "all_teams_control" field. Independent of `_drill` --
# both armies still spawn; see Battle.all_teams_control's own doc comment.
var _all_teams_control: bool = false
# Battle AI phase 3 (docs/battle-ai-design.md): which doctrine profile team 1's General uses,
# from the input script's optional "doctrine" field (a DoctrineRegistry id). Empty string ==
# "don't override" -- Battle keeps its own default (see Battle.ai_doctrine's own doc comment).
var _doctrine: String = ""
# Which Faction.Type each team fights under, from the input script's optional "factions"
# field (per-team names, e.g. ["Sparta", "Rome"]) -- display identity only, so the historical
# formation/form-up/doctrine names reach the HUD in a recording the same way a prebattle
# choice delivers them in a real battle. Empty == leave Battle.team_factions at its own
# no-faction default, so every existing script records byte-for-byte as before.
var _team_factions: Array[int] = []
# Simulation-tier trigger distances (world units) from the input script's optional
# "tier_ranges": {"promote": <wu>, "demote": <wu>} block. -1.0 == "don't override", so
# Battle keeps FormationTier's tuned defaults. A demo about live FAR-tier behaviour needs
# these: the defaults sit far outside every combat reach, so a formation always promotes
# back to the close tier before anything can strike it -- see Battle.promote_range.
var _promote_range: float = -1.0
var _demote_range: float = -1.0
# Parsed per-demo map overrides (BattleMap.parse's shape) from the input script's
# optional "map" field. Empty == run on the default map.
var _map: Dictionary = {}
# Live SelectionManager override for the multi-unit form-up distribution mode (a
# SelectionManager.FormUpDist value), from the input script's optional "form_up_dist"
# field. -1 (default) means "don't override" -- SelectionManager keeps reading
# Settings.form_up_dist_default as normal. Set directly on the live SelectionManager
# instance (not via a Settings session setter) since this is a live-battle behavior
# override, not a HUD/render toggle -- see _start_battle.
var _form_up_dist: int = -1
# Optional tray-grid seed from the input script's "tray_grid" field (rows of unit uids
# or nulls) plus the session-only tray_row_order_placement / show_unit_card_tray
# toggles. Applied after Battle._ready so HUD's tray exists; empty = leave the tray
# at its default row-major fill.
var _tray_grid: Array = []
var _tray_row_order_placement: bool = false
var _show_unit_card_tray: bool = false
# Optional spawn-layout stamp (SpawnFingerprint) from the input script's "spawn_fingerprint"
# field. "" (default) = unstamped, so the load check is skipped -- the additive-field,
# opt-in convention every other script field follows. A stamped script that no longer matches
# this build's spawn layout fails the recording LOUDLY (the silent spawn-drift failure mode:
# a re-spaced spawn line leaves the script's fixed clicks landing on empty ground).
var _spawn_fingerprint: String = ""
var _initial_time_scale: float = 1.0   # starting time_scale override (1.0 = normal)
var _frame_ticks: Array = []           # ticks to save a viewport PNG at (frame capture; empty = off)
var _frame_dir: String = ""            # output dir for captured frames
var _captured: Dictionary = {}         # tick -> true, so each frame is saved at most once
var _state_ticks: Array = []           # ticks to dump a JSON game-state snapshot at (empty = off)
var _state_dir: String = ""            # output dir for state snapshots
var _state_full: bool = false          # also dump the raw per-soldier arrays (deep debugging)
var _state_dumped: Dictionary = {}     # tick -> true, so each snapshot is written at most once
var _hash_stream: FileAccess = null    # per-tick state-hash stream (armed with the state dump)
var _hash_last_tick: int = -1          # last tick hashed, so a frozen tick writes one line only


## Parse an input script's "tier_ranges" block into {"promote": float, "demote": float}, or
## {"error": String} describing the first problem. Shaped like BattleMap.parse so the caller
## reports and quits the same way for both, and pure so it is unit-testable without a tree.
##
## Finiteness is checked BEFORE the ordering rule, because every comparison against NaN is
## false: a NaN promote would pass `promote <= 0.0` and `demote <= promote` alike and reach
## Battle as a trigger distance no formation can ever satisfy -- a silently tier-frozen
## recording rather than a loud failure. INF slips through the ordering rule just as quietly.
static func parse_tier_band(band) -> Dictionary:
	if typeof(band) != TYPE_DICTIONARY or not band.has("promote") or not band.has("demote"):
		return {"error": "tier_ranges must be {\"promote\": <wu>, \"demote\": <wu>}."}
	var promote: float = float(band["promote"])
	var demote: float = float(band["demote"])
	if not is_finite(promote) or not is_finite(demote):
		return {"error": "tier_ranges promote/demote must be finite numbers."}
	if promote <= 0.0 or demote <= promote:
		return {"error": "tier_ranges needs 0 < promote < demote (the hysteresis gap)."}
	return {"promote": promote, "demote": demote}


func _ready() -> void:
	# Unconditional wall-clock safety net (same as DemoRunner): whatever mode this
	# run is in -- movie recording, frame capture, state dump -- it quits itself
	# once the budget expires instead of lingering as an orphaned headless process.
	# The tighter CAPTURE_TIMEOUT_SEC net below still fires first in capture/dump
	# mode; this one also covers a movie recording that misses its --quit-after.
	# Only when this scene is the run's root (a real tool run): a GUT test that
	# instantiates the recorder as a child must not install a process-wide kill
	# timer in the test run.
	if get_parent() == get_tree().root:
		get_tree().root.add_child.call_deferred(RunWatchdog.create("scripted-input recording"))
	# A recording carries the game's sound (SFX default off); session-only, like DemoRunner.
	Settings.set_sfx_enabled_session(true)
	var script: Dictionary = _load_script(OS.get_environment("SPARTA_DEMO_INPUT"))
	# Optional per-demo HUD toggle: a script that wants the unit-speed label visible in its
	# recording (Settings.show_unit_speed is off by default -- extra clutter most players
	# don't want) requests it here, session-only like the SFX toggle above -- never persisted.
	if script.get("show_unit_speed", false):
		Settings.set_show_unit_speed_session(true)
	# Same session-only pattern: a demo wanting the engaged-soldier highlight visible
	# requests it here rather than needing a scripted menu click.
	if script.get("show_engaged_highlight", false):
		Settings.set_show_engaged_highlight_session(true)
	# Same session-only pattern, but opt-OUT by default: the soldier-ID overlay is a
	# useful debugging/verification signal for reviewers (and for the SPARTA_DEMO_STATE
	# cross-check in demos/README.md), so it's on unless a script explicitly sets
	# "show_soldier_ids": false. Note this alone isn't enough to render -- the overlay
	# also requires the unit to be `selected` and the camera at detailed LOD (Unit._draw's
	# `if selected and Settings.show_soldier_ids and _detailed_lod` gate), so a scenario
	# that doesn't already select a unit and zoom in past LOD_ZOOM_IN won't show IDs
	# regardless of this default.
	if script.get("show_soldier_ids", true):
		Settings.set_show_soldier_ids_session(true)
	# Same session-only pattern: a demo wanting the position-anchor marker (a unit's
	# `position`, the regiment's own kinematic point) visible requests it here.
	if script.get("show_position_anchor", false):
		Settings.set_show_position_anchor_session(true)
	# Deterministic seed so the recorded battle is reproducible run to run.
	Replay.forced_seed = int(str(script.get("seed", "12345")))
	# camera/frames/state go through script_array so a non-array typo degrades that one
	# feature (with a warning) instead of crashing on a typed assignment/argument: a default
	# camera, an unarmed capture, and default transcript ticks all still show the same battle.
	# steps and scenario stay strict — degrading those changes WHAT the demo simulates (no
	# inputs / the wrong matchup), and a plausible-looking wrong clip is worse than a red job.
	_camera_track = DemoFrames.script_array(script, "camera")
	if not CameraKeyframes.is_sorted(_camera_track):
		push_warning("[demo-input] camera keyframes are not sorted by tick; interpolation will be wrong.")
	_schedule(script.get("steps", []))
	_drill = bool(script.get("drill", false))
	_scenario = script.get("scenario", [])
	_doctrine = str(script.get("doctrine", ""))
	_all_teams_control = bool(script.get("all_teams_control", false))
	_team_factions = _parse_factions(script.get("factions", []))
	# Tier band, strict like scenario/map: it decides WHICH SIMULATION TIER the demo's
	# formations run at, so a malformed block must fail loudly rather than silently record a
	# close-tier fight in a clip captioned as a far-tier one.
	if script.has("tier_ranges"):
		var band: Dictionary = parse_tier_band(script["tier_ranges"])
		if band.has("error"):
			push_error("[demo-input] %s" % band["error"])
			get_tree().quit(2)
			return
		_promote_range = band["promote"]
		_demote_range = band["demote"]
	# The optional per-demo map block (field size, terrain patches, spawn lines).
	# Strict like steps/scenario: map geometry decides WHAT battlefield the demo
	# simulates, so a malformed block must fail the recording loudly rather than
	# silently record the wrong battle on the default map.
	if script.has("map"):
		_map = BattleMap.parse(script["map"])
		if _map.has("error"):
			push_error("[demo-input] bad map block: %s" % _map["error"])
			get_tree().quit(2)
			return
	_form_up_dist = int(script.get("form_up_dist", -1))
	_tray_row_order_placement = bool(script.get("tray_row_order_placement", false))
	_show_unit_card_tray = bool(script.get("show_unit_card_tray", false))
	var raw_tray_grid = script.get("tray_grid", [])
	_tray_grid = raw_tray_grid if raw_tray_grid is Array else []
	_spawn_fingerprint = str(script.get("spawn_fingerprint", ""))
	# Optional slow-motion / time_scale setting: a script (or SPARTA_DEMO_TIME_SCALE env)
	# that wants to record at a custom speed. Top-level slow_motion / time_scale can be a scalar
	# or an array of keyframes [{tick, value}], and steps can also carry {"slow_motion": ...}
	# or {"time_scale": ...}.
	if OS.has_environment("SPARTA_DEMO_TIME_SCALE"):
		_initial_time_scale = float(OS.get_environment("SPARTA_DEMO_TIME_SCALE"))
	elif script.has("time_scale"):
		var raw_ts = script["time_scale"]
		if raw_ts is Array:
			for entry in raw_ts:
				if entry is Dictionary and entry.has("tick") and entry.has("value"):
					_at(int(entry["tick"]), {"kind": "time_scale", "scale": float(entry["value"])})
		else:
			_initial_time_scale = float(raw_ts)
	elif script.has("slow_motion"):
		var raw_sm = script["slow_motion"]
		if raw_sm is bool:
			_initial_time_scale = 0.5 if raw_sm else 1.0
		elif raw_sm is Array:
			for entry in raw_sm:
				if entry is Dictionary and entry.has("tick") and entry.has("value"):
					_at(int(entry["tick"]), {"kind": "time_scale", "scale": float(entry["value"])})
		else:
			_initial_time_scale = float(raw_sm)
	_arm_frame_capture(DemoFrames.script_array(script, "frames"))
	# Declared expectations (the `expect` list) are checked offline against dumped
	# snapshots, so every expect tick joins the state-dump defaults -- declaring an
	# expectation is enough to make the data it checks exist on a dump run. A
	# malformed (non-array) `expect` is ignored here rather than crashing the
	# recorder; the analyzer's own --script validation is where authoring errors
	# get their loud failure.
	var raw_expect = script.get("expect", [])
	var state_defaults: Array = DemoFrames.script_array(script, "state")
	for t in DemoDefects.expect_ticks(raw_expect if raw_expect is Array else []):
		if not state_defaults.has(t):
			state_defaults.append(t)
	_arm_state_dump(state_defaults)
	print("[demo-input] %d scripted input events over %d ticks%s%s%s" % [
		_count_events(), _max_tick(), " (drill mode)" if _drill else "",
		" (scenario: %d units)" % _scenario.size() if not _scenario.is_empty() else "",
		" (all-teams control)" if _all_teams_control else ""])
	# Defer so this bootstrap finishes _ready before the battle is added; Movie Maker keeps
	# recording across the change. The recorder stays the scene root (Battle is a child) so
	# it persists to inject events every tick.
	_start_battle.call_deferred()


func _start_battle() -> void:
	_battle = load(BATTLE_SCENE).instantiate()
	_battle.drill_mode = _drill   # set before add_child so Battle._ready reads it (no team-1 spawn)
	_battle.scenario = _scenario  # likewise: a custom matchup replaces the default line spawn
	_battle.all_teams_control = _all_teams_control   # likewise: relaxes team checks, no team-1 AI
	# Map overrides, likewise before add_child: every map consumer runs in _ready.
	if _map.has("field"):
		_battle.field = _map["field"]
	if _map.has("terrain"):
		_battle.terrain = _map["terrain"]
	if _map.has("spawn_lines"):
		_battle.spawn_line_ys = _map["spawn_lines"]
	if _doctrine != "":
		_battle.ai_doctrine = _doctrine   # likewise: overrides Battle's own default doctrine
	if not _team_factions.is_empty():
		_battle.team_factions = _team_factions   # likewise: Battle._ready hands these to the HUD
	if _promote_range > 0.0:
		# Likewise before add_child: Battle's first tier pass runs on the first tick.
		_battle.promote_range = _promote_range
		_battle.demote_range = _demote_range
	add_child(_battle)
	# Battle._ready spawns synchronously during add_child, so every unit is on the field now.
	# Print the layout's fingerprint (so a new script can be stamped by copying it) and, when the
	# script declared one, fail LOUDLY on a mismatch rather than recording a clip whose scripted
	# clicks land on empty ground where a unit used to be (the silent spawn-drift failure mode).
	var live_fingerprint: String = SpawnFingerprint.of_tree(get_tree())
	print("[demo-input] spawn fingerprint: %s" % live_fingerprint)
	if _spawn_fingerprint != "" and _spawn_fingerprint != live_fingerprint:
		push_error(("[demo-input] spawn-layout mismatch: script declares spawn_fingerprint %s " +
				"but this build spawns %s. The spawn table changed since this script was authored, " +
				"so its scripted clicks may no longer land on the intended units. Re-verify the " +
				"coordinates and update (or drop) the spawn_fingerprint field.") %
				[_spawn_fingerprint, live_fingerprint])
		get_tree().quit(4)
		return
	_sel = _battle.get_node("SelectionManager")
	_hud = _battle.get_node("HUD")
	if _form_up_dist >= 0:
		_sel._form_up_dist = _form_up_dist
	_apply_demo_tray()
	if _initial_time_scale != 1.0 and _initial_time_scale > 0.0:
		_set_time_scale(_initial_time_scale, 0)
	_cam = _battle.get_node("Camera2D")
	_apply_camera(0)
	get_tree().physics_frame.connect(_on_physics_frame)


## Session-only tray toggles plus optional uid-grid seed. HUD has already built the tray
## during Battle._ready (even while hidden); seeding here overwrites the default row-major
## fill so a form-up drag can place the scripted 2D layout. Does not persist Settings.
func _apply_demo_tray() -> void:
	if _tray_row_order_placement:
		Settings.set_tray_row_order_placement_session(true)
	if _show_unit_card_tray:
		Settings.set_show_unit_card_tray_session(true)
		if _hud != null and _hud.has_method("_sync_unit_card_tray_visibility"):
			_hud._sync_unit_card_tray_visibility()
	if _tray_grid.is_empty() or _hud == null or not _hud.has_method("get_unit_card_tray"):
		return
	var tray = _hud.get_unit_card_tray()
	if tray == null or not tray.has_method("apply_uid_grid"):
		return
	tray.apply_uid_grid(_tray_grid, _battle._by_uid)


## Each physics frame, hold the camera framing and fire any input events due this tick.
func _on_physics_frame() -> void:
	if _sel == null or not is_instance_valid(_sel) \
			or _battle == null or not is_instance_valid(_battle):
		return
	var tick: int = _battle.current_tick()
	_apply_camera(tick)
	for ev in _by_tick.get(tick, []):
		_fire(ev)
	# Stream the per-tick state hash (armed with the state dump). The tick guard makes a
	# frozen tick -- the sim stops advancing once the battle ends -- write one line, not one
	# per remaining physics frame.
	if _hash_stream != null and tick != _hash_last_tick:
		_hash_last_tick = tick
		DemoStateHash.write_tick(_hash_stream, get_tree(), tick, Replay.rng.state)
	if _state_ticks.has(tick) and not _state_dumped.has(tick):
		_state_dumped[tick] = true
		_dump_state(tick)
	# A decided battle freezes the sim's tick (Battle._ended), so every armed state tick past
	# the end would never fire and the run would sit until the wall-clock timeout with a
	# partial dump -- indistinguishable, from the files alone, from a run the timeout cut off
	# mid-battle. Write one terminal snapshot at the frozen tick instead, carrying an explicit
	# battle_over marker, and mark the remaining armed ticks done so the normal
	# _all_artifacts_done() quit path fires promptly. Consumers read the marker to tell a
	# decided battle from a truncated one exactly, rather than inferring it from which teams
	# remain -- a victory can land between two armed ticks, or end with both teams still on
	# the field (a general killed or routed).
	if _battle._ended and not _state_ticks.is_empty() \
			and _state_dumped.size() < _state_ticks.size():
		# Unconditional, so a battle ending exactly ON an armed tick still gets the marker:
		# the plain dump just written above is overwritten with the marked one, same
		# content plus the flag. Only ARMED ticks go into _state_dumped -- the frozen tick
		# is usually not armed, and inserting it would push the dict's size past
		# _state_ticks' and break _all_artifacts_done()'s equality, hanging the run to
		# the wall-clock timeout this branch exists to avoid.
		_dump_state(tick, true)
		for t in _state_ticks:
			if not _state_dumped.has(t):
				_state_dumped[t] = true
	if _frame_ticks.has(tick) and not _captured.has(tick):
		_captured[tick] = true
		_capture_frame(tick)
	# In capture / dump mode (not a movie recording), quit once every armed frame AND state
	# snapshot is done so the tool returns promptly, without a fragile --quit-after frame count.
	# _all_artifacts_done() guards on at least one list being armed, so a movie recording (neither
	# armed) never quits here — it runs to Movie Maker's own --quit-after.
	if _all_artifacts_done():
		_quit_after_captures()


## Set the camera to the track's framing for `tick`, interpolating between keyframes. The
## CameraController only moves on real pan/zoom input (the recorder injects none), so a
## directly-set position/zoom holds; we re-apply each tick to animate along the track.
func _apply_camera(tick: int) -> void:
	if _cam == null:
		return
	var kf: Dictionary = CameraKeyframes.sample(_camera_track, tick)
	if kf.is_empty():
		return
	_cam.position = Vector2(kf["x"], kf["y"])
	var z: float = kf["zoom"]   # sample() already returns floats
	_cam.zoom = Vector2(z, z)


# --- frame capture ---------------------------------------------------------

## Arm PNG frame capture from SPARTA_DEMO_FRAMES (a comma-separated tick list) merged with the
## input script's optional `frames` array. When the resulting set is empty (both unset — the
## normal case), capture is off and the recorder behaves exactly as before. Otherwise each
## listed tick saves the drawn viewport to SPARTA_DEMO_FRAME_DIR (default: a temp dir), so a
## demo can be rendered to a handful of PNGs and eyeballed to confirm the behaviour is on-screen.
func _arm_frame_capture(script_frames: Array) -> void:
	# Capture is env-gated: it arms only when SPARTA_DEMO_FRAMES is set. A movie recording (CI)
	# leaves it unset, so a demo's own `frames` array never truncates the recording — that array
	# just supplies default ticks for a capture run. Set SPARTA_DEMO_FRAMES to a tick list to
	# override those defaults, or to any value (even empty, via the wrapper) to arm with them.
	if not OS.has_environment("SPARTA_DEMO_FRAMES"):
		return
	_frame_ticks = DemoFrames.merge_ticks(OS.get_environment("SPARTA_DEMO_FRAMES"), script_frames)
	if _frame_ticks.is_empty():
		return
	_frame_dir = OS.get_environment("SPARTA_DEMO_FRAME_DIR")
	if _frame_dir == "":
		_frame_dir = OS.get_temp_dir().path_join("sparta_demo_frames")
	# Create the output dir (recursively) so save_png doesn't silently fail on a missing path.
	DirAccess.make_dir_recursive_absolute(_frame_dir)
	print("[demo-input] frame capture armed at ticks %s -> %s" % [str(_frame_ticks), _frame_dir])
	# Safety net: the sim freezes its tick when a battle ends (Battle._ended), so a frame armed
	# past the battle's end would never fire and the run would hang. Quit after a generous wall
	# time regardless, saving whatever was captured. Timer runs on real time (not process time),
	# so it fires even if physics is throttled while the window is unfocused.
	get_tree().create_timer(CAPTURE_TIMEOUT_SEC).timeout.connect(_on_capture_timeout)


## Save the drawn viewport to a PNG for `tick`. The viewport texture is only valid after the
## frame is drawn, so wait for RenderingServer.frame_post_draw before reading it — reading in
## the physics frame (before the draw) yields a stale or blank image. A real renderer is
## required: --headless uses the dummy renderer and produces a null/blank texture, so this
## must run with e.g. --rendering-driver opengl3 (see demos/README.md).
func _capture_frame(tick: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_warning("[demo-input] frame %d: null viewport image (dummy renderer? run with a real --rendering-driver)." % tick)
		return
	var path: String = DemoFrames.frame_path(_frame_dir, tick)
	var err: int = img.save_png(path)
	if err != OK:
		push_warning("[demo-input] frame %d: save_png failed (%d) at %s" % [tick, err, path])
	else:
		print("[demo-input] captured frame at tick %d -> %s (%dx%d)" % [tick, path, img.get_width(), img.get_height()])


## True once every armed frame is captured and every armed state snapshot is written — the
## signal to quit a capture/dump run. The leading `> 0` guard is load-bearing: without it, a
## normal movie recording (neither list armed, both sizes 0) would satisfy `0 == 0 and 0 == 0`
## and quit after the first physics tick. The guard keeps this false unless at least one
## artifact type is armed, so an unarmed recording runs to Movie Maker's own --quit-after.
func _all_artifacts_done() -> bool:
	return (_frame_ticks.size() + _state_ticks.size()) > 0 \
		and _captured.size() == _frame_ticks.size() \
		and _state_dumped.size() == _state_ticks.size()


## Quit the tree once every armed frame is captured, after the pending save_png awaits finish.
## Only reached in frame-capture / state-dump mode; a normal movie recording never arms either
## and runs to Movie Maker's own --quit-after, so this never fires there.
##
## The frame_post_draw await lets any in-flight _capture_frame() save_png finish before we quit.
## It is ONLY needed when frames were captured: under --headless (the state-dump path) the dummy
## renderer may never emit frame_post_draw, so awaiting it there hangs the run until the caller's
## wall-clock timeout. A state-only dump reads sim state, never the drawn frame, so it quits
## straight away.
func _quit_after_captures() -> void:
	Engine.time_scale = 1.0
	if not _frame_ticks.is_empty():
		await RenderingServer.frame_post_draw
	print("[demo-input] all artifacts done (%d frames, %d state snapshots); quitting."
		% [_frame_ticks.size(), _state_ticks.size()])
	get_tree().quit()


## Fired if a capture/dump run runs long. Quit anyway so the tool never hangs; whatever was
## captured/dumped is already on disk. Two cases reach here: a tick armed past the battle's end
## never fired (the sim freezes its tick then), so artifacts are incomplete; or every artifact
## landed but the quit-after path stalled. Either way we are done waiting — quit unconditionally,
## warning only when something is actually missing.
func _on_capture_timeout() -> void:
	Engine.time_scale = 1.0
	if not _all_artifacts_done():
		push_warning("[demo-input] run timed out: %d/%d frames, %d/%d state snapshots (a tick may be past the battle's end)."
			% [_captured.size(), _frame_ticks.size(), _state_dumped.size(), _state_ticks.size()])
	get_tree().quit()


# --- state dump ------------------------------------------------------------

## Arm JSON game-state dumping from SPARTA_DEMO_STATE (a comma-separated tick list) merged with
## the input script's optional `state` array. When the resulting set is empty (both unset — the
## normal case), dumping is off and the recorder behaves exactly as before. Otherwise each listed
## tick writes a readable snapshot of the authoritative unit state to
## SPARTA_DEMO_STATE_DIR/state_<tick>.json (default: a temp dir), so a demo can be verified by
## reading exact values rather than interpreting a rendered frame. SPARTA_DEMO_STATE_FULL=1 also
## dumps the raw per-soldier arrays for deep debugging.
func _arm_state_dump(script_state: Array) -> void:
	# Env-gated, exactly like frame capture: arms only when SPARTA_DEMO_STATE is set. A movie
	# recording (CI) leaves it unset, so a demo's own `state` array never affects the recording —
	# that array just supplies default ticks for a dump run. Reuses DemoFrames' tick parse/merge.
	if not OS.has_environment("SPARTA_DEMO_STATE"):
		return
	_state_ticks = DemoFrames.merge_ticks(OS.get_environment("SPARTA_DEMO_STATE"), script_state)
	if _state_ticks.is_empty():
		return
	_state_full = OS.get_environment("SPARTA_DEMO_STATE_FULL") == "1"
	_state_dir = OS.get_environment("SPARTA_DEMO_STATE_DIR")
	if _state_dir == "":
		_state_dir = OS.get_temp_dir().path_join("sparta_demo_state")
	DirAccess.make_dir_recursive_absolute(_state_dir)
	# An armed dump run also streams the per-tick two-tier state hash (DemoStateHash) into
	# the same directory -- every tick, not just the snapshot ticks, so two runs of the same
	# clip can be compared to the exact tick they first diverge.
	_hash_stream = DemoHashStream.open_stream(_state_dir)
	if _hash_stream == null:
		push_warning("[demo-input] could not open hash_stream.jsonl in %s (err %d)"
				% [_state_dir, FileAccess.get_open_error()])
	print("[demo-input] state dump armed at ticks %s -> %s%s" % [
		str(_state_ticks), _state_dir, " (full per-soldier arrays)" if _state_full else ""])
	# Same safety net as capture: quit after a generous wall time so a tick past the battle's
	# end can't hang the run. Guarded so two arms don't stack two timers unnecessarily is not
	# needed — a duplicate timer just fires a redundant already-done check.
	get_tree().create_timer(CAPTURE_TIMEOUT_SEC).timeout.connect(_on_capture_timeout)


## Write a readable JSON snapshot of the authoritative game state at `tick`. The snapshot
## content comes from DemoState.build_snapshot — shared with the replay path's DemoStateSink,
## so both dump paths' transcripts are identical in shape. No await / renderer needed — this
## reads sim state, not the drawn frame, so it works even under --headless.
func _dump_state(tick: int, battle_over: bool = false) -> void:
	var snapshot: Dictionary = _build_snapshot(tick)
	if battle_over:
		# Terminal snapshot of a decided battle (see _on_physics_frame's ended branch).
		# The explicit marker is what lets a consumer tell "the battle ended here" from
		# "the dump was cut off here" without inferring it from the units on the field.
		snapshot["battle_over"] = true
	var path: String = "%s/state_%05d.json" % [_state_dir.trim_suffix("/"), tick]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[demo-input] state %d: could not open %s (err %d)" % [tick, path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(snapshot, "  "))
	f.close()
	print("[demo-input] dumped state at tick %d -> %s (%d units)" % [tick, path, snapshot["units"].size()])


## Build the snapshot Dictionary for `tick`. Thin wrapper over the shared
## DemoState.build_snapshot (see there for the walk/sort semantics), feeding it this
## battle's own name tables and the recorder's full-arrays flag. Kept as its own method so
## it stays directly inspectable from tests, as before the extraction.
func _build_snapshot(tick: int) -> Dictionary:
	return DemoState.build_snapshot(get_tree(), tick, _battle.ORDER_MODE_NAMES,
			_battle.SPEED_SCALE, _state_full)


## One unit's readable record: the shared DemoState.unit_record, fed this battle's own
## name tables and the recorder's full-arrays flag. Kept as a method so tests can build a
## single unit's record directly, as before the extraction.
func _unit_record(u: Node) -> Dictionary:
	return DemoState.unit_record(u, _battle.ORDER_MODE_NAMES, _battle.SPEED_SCALE, _state_full)


# --- input injection -------------------------------------------------------

## Drive one expanded event into the SelectionManager (and, for a "key" event, the HUD too --
## some hotkeys, like slow-motion's F5, are handled directly in HUD._unhandled_input rather
## than routed through SelectionManager, matching how P/F1/Shift+/ are also HUD-only global
## toggles). Position comes via the cursor override (all selection/order logic reads
## _cursor_world()), so the synthesized events' own position fields don't need to be accurate
## -- only the button/key and pressed state matter.
func _fire(ev: Dictionary) -> void:
	match ev["kind"]:
		"mb":
			_sel.set_cursor_override(ev["pos"])
			var mb := InputEventMouseButton.new()
			mb.button_index = int(ev["button"])
			mb.pressed = bool(ev["pressed"])
			mb.position = ev["pos"]
			mb.shift_pressed = bool(ev.get("shift", false))
			_sel._unhandled_input(mb)
		"motion":
			_sel.set_cursor_override(ev["pos"])
			var mm := InputEventMouseMotion.new()
			mm.position = ev["pos"]
			_sel._unhandled_input(mm)
		"key":
			var k := InputEventKey.new()
			k.keycode = int(ev["keycode"])
			k.physical_keycode = int(ev["keycode"])
			k.pressed = true
			k.ctrl_pressed = bool(ev.get("ctrl", false))
			k.shift_pressed = bool(ev.get("shift", false))
			_sel._unhandled_input(k)
			if _hud != null and is_instance_valid(_hud):
				_hud._unhandled_input(k)
		"hold_space":
			# Update hardware key state so Input.is_key_pressed(KEY_SPACE) returns true
			# for the rest of the recording — enabling the orders overlay draw path.
			var k := InputEventKey.new()
			k.keycode = KEY_SPACE
			k.physical_keycode = KEY_SPACE
			k.pressed = true
			Input.parse_input_event(k)
		"time_scale":
			var scale: float = float(ev.get("scale", 1.0))
			_set_time_scale(scale, _battle.current_tick() if _battle != null and is_instance_valid(_battle) else 0)


## Set Engine.time_scale and update Replay and HUD state.
func _set_time_scale(scale: float, tick: int) -> void:
	Engine.time_scale = scale
	if _battle != null and is_instance_valid(_battle):
		Replay.record_time_scale_change(tick, scale)
	if _hud != null and is_instance_valid(_hud):
		var presets = _hud.get("SLOWMO_PRESETS")
		if presets == null:
			presets = preload("res://scripts/HUD.gd").SLOWMO_PRESETS
		var idx: int = presets.find(scale)
		if idx != -1:
			_hud._slowmo_index = idx
		if _hud.has_method("_update_slowmo_label"):
			_hud._update_slowmo_label()
		if _hud.has_method("flash_message"):
			_hud.flash_message("Speed: %d%%" % roundi(scale * 100.0))


# --- script -> per-tick event schedule -------------------------------------

func _schedule(steps: Array) -> void:
	for step in steps:
		var tick: int = int(step.get("tick", 0))
		if step.has("click"):
			_click(tick, _vec(step["click"]), MOUSE_BUTTON_LEFT, false)
		elif step.has("shift_click"):
			_click(tick, _vec(step["shift_click"]), MOUSE_BUTTON_LEFT, true)
		elif step.has("rmb_click"):
			_click(tick, _vec(step["rmb_click"]), MOUSE_BUTTON_RIGHT, false)
		elif step.has("box"):
			_drag(tick, _vec(step["box"]["from"]), _vec(step["box"]["to"]), MOUSE_BUTTON_LEFT, false)
		elif step.has("rmb_drag"):
			var shift: bool = bool(step["rmb_drag"].get("shift", false))
			_drag(tick, _vec(step["rmb_drag"]["from"]), _vec(step["rmb_drag"]["to"]), MOUSE_BUTTON_RIGHT, shift)
		elif step.has("key"):
			_at(tick, {"kind": "key", "keycode": OS.find_keycode_from_string(str(step["key"])),
					"ctrl": bool(step.get("ctrl", false)), "shift": bool(step.get("shift", false))})
		elif step.has("hold_space"):
			# Hold Space for the rest of the recording so the orders overlay is visible.
			# Uses Input.parse_input_event (not _unhandled_input) so Input.is_key_pressed()
			# reflects the held state — that's what _draw_orders() checks.
			_at(tick, {"kind": "hold_space"})
		elif step.has("time_scale"):
			_at(tick, {"kind": "time_scale", "scale": float(step["time_scale"])})
		elif step.has("slow_motion"):
			var raw_sm = step["slow_motion"]
			var scale: float = (0.5 if raw_sm else 1.0) if raw_sm is bool else float(raw_sm)
			_at(tick, {"kind": "time_scale", "scale": scale})
		else:
			# A step matching none of the recognized action keys above is a no-op:
			# it schedules nothing and the recording silently proceeds without it.
			# Fail loudly instead — an unrecognized shape is almost always an
			# authoring mistake (e.g. {"type": "click", "pos": [...]} instead of
			# {"click": [...]}), and a silent no-op reads as "it worked" until
			# someone dumps state and finds the scripted action never happened.
			push_error("DemoInputRecorder: step at tick %d matches no recognized action key (%s) -- ignored" % [tick, str(step.keys())])


## A click = button press then release at one point, on the same tick.
func _click(tick: int, pos: Vector2, button: int, shift: bool) -> void:
	_at(tick, {"kind": "mb", "pos": pos, "button": button, "pressed": true, "shift": shift})
	_at(tick, {"kind": "mb", "pos": pos, "button": button, "pressed": false, "shift": shift})


## A drag = press at `from`, motions interpolating to `to` over DRAG_TICKS (so the preview
## animates and the drag passes the click threshold), then release at `to`.
func _drag(tick: int, from: Vector2, to: Vector2, button: int, shift: bool) -> void:
	_at(tick, {"kind": "mb", "pos": from, "button": button, "pressed": true, "shift": shift})
	for i in range(1, DRAG_TICKS):
		var pos: Vector2 = from.lerp(to, float(i) / float(DRAG_TICKS))
		_at(tick + i, {"kind": "motion", "pos": pos})
	_at(tick + DRAG_TICKS, {"kind": "mb", "pos": to, "button": button, "pressed": false, "shift": shift})


func _at(tick: int, ev: Dictionary) -> void:
	if not _by_tick.has(tick):
		_by_tick[tick] = []
	_by_tick[tick].append(ev)


# --- helpers ---------------------------------------------------------------

## Resolve an input script's "factions" list (per-team faction names, e.g. ["Sparta", "Rome"])
## into Battle.team_factions' Faction.Type ids. Strict, like `steps`/`scenario` and unlike
## `camera`/`frames`: a name no faction claims would silently record a clip whose captions
## show the plain names while the script claims a faction, and a plausible-looking wrong clip
## is worse than a red job. A missing/empty list is not an error -- it just means "no faction",
## which is what every script written before this field says.
func _parse_factions(raw) -> Array[int]:
	var out: Array[int] = []
	if not (raw is Array):
		push_error("[demo-input] 'factions' must be an array of faction names, got %s." % typeof(raw))
		get_tree().quit(2)
		return out
	for entry in raw:
		var f_id: int = Faction.type_from_name(str(entry))
		if f_id == Faction.NONE:
			push_error("[demo-input] unknown faction '%s'; expected one of %s." %
					[entry, Faction.ALL_TYPES.map(func(f): return Faction.get_faction_name(f))])
			get_tree().quit(2)
			return out
		out.append(f_id)
	return out


func _vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _load_script(path: String) -> Dictionary:
	if path == "":
		push_warning("[demo-input] SPARTA_DEMO_INPUT unset; recording a default battle.")
		return {}
	if not FileAccess.file_exists(path):
		push_warning("[demo-input] script not found: %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[demo-input] script is not a JSON object: %s" % path)
		return {}
	return data


func _max_tick() -> int:
	var m: int = 0
	for t in _by_tick:
		m = maxi(m, int(t))
	return m


func _count_events() -> int:
	var n: int = 0
	for t in _by_tick:
		n += (_by_tick[t] as Array).size()
	return n
