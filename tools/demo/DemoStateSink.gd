class_name DemoStateSink
extends Node
## Env-gated JSON state dumping for runs that don't keep a recorder node alive — the replay
## path (DemoRunner hands the tree over to the battle scene and is freed, so it can't dump
## per tick the way DemoInputRecorder does). Armed from SPARTA_DEMO_STATE exactly like the
## scripted-input recorder's dump: a comma-separated tick list, snapshots written to
## SPARTA_DEMO_STATE_DIR/state_<tick>.json (default: a temp dir), SPARTA_DEMO_STATE_FULL=1
## for the raw per-soldier arrays. Snapshot content comes from the same shared
## DemoState.build_snapshot the recorder uses, so both paths' transcripts are identical in
## shape.
##
## Lives directly under the tree root (it must survive the bootstrap scene being replaced by
## the battle), reads the current scene each physics frame, and dumps once per armed tick.
## In a state-only run it quits the tree once every armed snapshot is written; the timeout
## below bounds a run whose armed ticks lie past the battle's end. Like the recorder's dump,
## arming is env-gated — a normal movie recording leaves SPARTA_DEMO_STATE unset, so this
## node is never even created there.

## Wall-clock budget for the run (mirrors DemoInputRecorder.CAPTURE_TIMEOUT_SEC): generous
## enough for any catalog clip, tight enough that a tick past the battle's end can't hang a
## headless run.
const TIMEOUT_SEC := 240.0

var _ticks: Array = []
var _dir: String = ""
var _full: bool = false
var _dumped: Dictionary = {}   # tick -> true, so each snapshot is written at most once
var _hash_stream: FileAccess = null   # per-tick state-hash stream (armed with the dump)
var _hash_last_tick: int = -1         # last tick hashed, so a frozen tick writes one line only
var _bit_ticks: Array = []            # ticks to dump raw bits for (SPARTA_DEMO_BITDUMP)
var _bit_dump: FileAccess = null      # raw-bit position dump, opened only when armed
var _bit_dumped: Dictionary = {}      # tick -> true, mirroring _dumped for the bit dump


## Build an armed sink from the environment, or null when SPARTA_DEMO_STATE is unset/empty —
## the caller adds the result under the tree root only when dumping is actually requested.
## `tag` prefixes the log lines so a transcript reads which path produced it.
static func arm_from_env(tag: String) -> DemoStateSink:
	if not OS.has_environment("SPARTA_DEMO_STATE"):
		return null
	var ticks: Array = DemoFrames.merge_ticks(OS.get_environment("SPARTA_DEMO_STATE"), [])
	if ticks.is_empty():
		return null
	var sink := DemoStateSink.new()
	sink._ticks = ticks
	sink._full = OS.get_environment("SPARTA_DEMO_STATE_FULL") == "1"
	sink._dir = OS.get_environment("SPARTA_DEMO_STATE_DIR")
	# Raw-bit dumping is armed separately and is off by default: it rides on the state
	# dump (same run, same directory) but answers a different question, and its lines are
	# far larger than a hash line. The hash stream is what names the tick worth dumping,
	# so the normal order is to read a stream comparison first and arm this second.
	if OS.has_environment("SPARTA_DEMO_BITDUMP"):
		sink._bit_ticks = DemoFrames.merge_ticks(OS.get_environment("SPARTA_DEMO_BITDUMP"), [])
	if sink._dir == "":
		sink._dir = OS.get_temp_dir().path_join("sparta_demo_state")
	sink.name = "DemoStateSink_%s" % tag
	return sink


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	# An armed dump run also streams the per-tick two-tier state hash (DemoStateHash) into
	# the same directory, exactly like the recorder's dump path.
	_hash_stream = DemoHashStream.open_stream(_dir)
	if _hash_stream == null:
		push_warning("[demo-state] could not open hash_stream.jsonl in %s (err %d)"
				% [_dir, FileAccess.get_open_error()])
	if not _bit_ticks.is_empty():
		_bit_dump = DemoBitDump.open_dump(_dir)
		if _bit_dump == null:
			push_warning("[demo-state] could not open bit_dump.jsonl in %s (err %d)"
					% [_dir, FileAccess.get_open_error()])
		else:
			print("[demo-state] raw-bit dump armed at ticks %s" % str(_bit_ticks))
	print("[demo-state] state dump armed at ticks %s -> %s%s" % [
		str(_ticks), _dir, " (full per-soldier arrays)" if _full else ""])
	# Safety net: quit unconditionally when the budget expires, warning only when snapshots
	# are still missing (an armed tick past the battle's end). Unconditional on purpose — a
	# "quit only if not done" guard can strand a run that finished its work but has nothing
	# else driving a quit.
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(_on_timeout)


func _physics_process(_delta: float) -> void:
	# The battle only exists once the bootstrap scene swapped it in; duck-type on
	# current_tick() so the sink is inert during startup (and in any non-battle scene).
	var battle: Node = get_tree().current_scene
	if battle == null or not battle.has_method("current_tick"):
		return
	var tick: int = battle.current_tick()
	# Stream the per-tick state hash. The tick guard makes a frozen tick -- the sim stops
	# advancing once the battle ends -- write one line, not one per remaining physics frame.
	if _hash_stream != null and tick != _hash_last_tick:
		_hash_last_tick = tick
		DemoStateHash.write_tick(_hash_stream, battle.get_tree(), tick, Replay.rng.state)
		# Deliberately inside the hash guard, so the dump samples the SAME instant the
		# hash did. Sampled anywhere else it could disagree with the stream that sent
		# anyone looking at this tick, which would make it worse than no dump at all.
		if _bit_dump != null and _bit_ticks.has(tick) and not _bit_dumped.has(tick):
			_bit_dumped[tick] = true
			DemoStateHash.dump_tick(_bit_dump, battle.get_tree(), tick)
	if _ticks.has(tick) and not _dumped.has(tick):
		_dumped[tick] = true
		_dump(battle, tick)
	# Both sets gate the quit. Keying it on the state snapshots alone let a run that
	# finished those quit before reaching a LATER bit-dump tick, leaving an empty
	# bit_dump.jsonl behind a "all snapshots written" line -- a clean-looking success
	# trail for a diagnostic that produced nothing.
	if _dumped.size() == _ticks.size() and _bit_dumped.size() == _bit_ticks.size():
		print("[demo-state] all %d state snapshot(s)%s written; quitting." % [
				_ticks.size(),
				" and %d raw-bit dump(s)" % _bit_ticks.size() if not _bit_ticks.is_empty() else ""])
		get_tree().quit()


func _dump(battle: Node, tick: int) -> void:
	# The battle's own tree, not this node's: identical in a real run (both live in the
	# one tree), but it keeps _dump drivable from a test without adding the sink -- and
	# its quit-on-done contract -- to the test run's tree.
	var snapshot: Dictionary = DemoState.build_snapshot(
			battle.get_tree(), tick, battle.ORDER_MODE_NAMES, battle.SPEED_SCALE, _full)
	var path: String = "%s/state_%05d.json" % [_dir.trim_suffix("/"), tick]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[demo-state] state %d: could not open %s (err %d)"
				% [tick, path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(snapshot, "  "))
	f.close()
	print("[demo-state] dumped state at tick %d -> %s (%d units)"
			% [tick, path, snapshot["units"].size()])


func _on_timeout() -> void:
	if _dumped.size() < _ticks.size():
		push_warning("[demo-state] run timed out: %d/%d state snapshots (a tick may be past the battle's end)."
				% [_dumped.size(), _ticks.size()])
	# Reported separately rather than folded in: a bit dump that never reached its
	# tick is silent otherwise, and an empty dump file is the one outcome an
	# investigation must not mistake for "the two platforms agreed".
	if _bit_dumped.size() < _bit_ticks.size():
		push_warning("[demo-state] run timed out: %d/%d raw-bit dumps (a tick may be past the battle's end)."
				% [_bit_dumped.size(), _bit_ticks.size()])
	get_tree().quit()
