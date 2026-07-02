class_name RunWatchdog
extends Node
## Unconditional wall-clock safety net for headless tool runs (demo recorders).
##
## A tool run that never reaches its own quit condition -- a forgotten
## --quit-after, a stalled replay, an await that never resumes -- survives its
## calling shell on Windows and lingers as an orphaned Godot process, starving
## every later run on the machine. This node force-quits the run from the
## inside once a wall-clock budget expires, complementing the coreutils
## `timeout` wrappers in the repo's shell scripts (which cover a fully hung
## process this node cannot see).
##
## Attach with `get_tree().root.add_child.call_deferred(RunWatchdog.create(...))`
## so it survives scene changes. The check reads Time.get_ticks_msec() -- real
## OS time, unaffected by Movie Maker's fixed-fps simulated clock or
## Engine.time_scale -- every process frame, so it fires even when the physics
## tick has frozen (e.g. a battle ended and nothing advances). SceneTreeTimer
## would NOT work here: it counts the simulated clock, which stalls exactly
## when this net is needed.
##
## This is tooling: nothing in the live game references it.

## Generous default -- the longest legitimate recording (a several-hundred-frame
## Movie Maker clip on a slow CI runner) finishes well inside this.
const DEFAULT_TIMEOUT_SEC := 900.0
const ENV_VAR := "SPARTA_RUN_TIMEOUT_SEC"

var timeout_sec: float = DEFAULT_TIMEOUT_SEC
var run_label: String = "tool run"
var _start_ms: int = 0


## Build a configured watchdog: budget from SPARTA_RUN_TIMEOUT_SEC when set to a
## positive number, DEFAULT_TIMEOUT_SEC otherwise. `label` names the run in the
## timeout warning so a killed run's log says what gave up.
static func create(label: String) -> RunWatchdog:
	var dog := RunWatchdog.new()
	dog.name = "RunWatchdog"
	dog.run_label = label
	dog.timeout_sec = timeout_from_env(OS.get_environment(ENV_VAR), DEFAULT_TIMEOUT_SEC)
	return dog


## Parse a timeout override: a positive float string wins, anything else (unset,
## garbage, zero, negative) falls back to the default. Pure and unit-tested.
static func timeout_from_env(env_value: String, default_sec: float) -> float:
	if env_value.is_valid_float() and float(env_value) > 0.0:
		return float(env_value)
	return default_sec


## True once `budget_sec` of wall clock has elapsed between the two timestamps.
## Pure and unit-tested; the node's _process is a thin shell around it (the quit
## path can't run under GUT -- it would kill the test process).
static func expired(start_ms: int, now_ms: int, budget_sec: float) -> bool:
	return now_ms - start_ms >= int(budget_sec * 1000.0)


func _ready() -> void:
	# Keep ticking through a paused tree -- a pause with no unpause coming is
	# exactly the kind of stall this net exists to break.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_ms = Time.get_ticks_msec()
	print("[watchdog] %s: wall-clock budget %ds (override via %s)."
		% [run_label, int(timeout_sec), ENV_VAR])


func _process(_delta: float) -> void:
	if not expired(_start_ms, Time.get_ticks_msec(), timeout_sec):
		return
	push_warning("[watchdog] %s exceeded its %ds wall-clock budget; force-quitting so it can't linger as an orphaned process."
		% [run_label, int(timeout_sec)])
	# quit(1), not push_error: a push_error alone leaves the exit code 0 (see
	# CLAUDE.md), and a timed-out run must read as a failure to its caller.
	get_tree().quit(1)
