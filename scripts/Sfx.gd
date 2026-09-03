extends Node
## Sound-effects player (autoload singleton: "Sfx").
##
## Presentation-only: playing a sound never touches the deterministic simulation
## or the seeded Replay RNG, so Sfx.play() is safe to call from sim code
## (Unit/Battle) without affecting replay determinism. Repeats of the same event
## are throttled by wall-clock time so dozens of simultaneous combat hits don't
## stack into a roar.
##
## Sounds load from curated open-access (CC0) audio under res://assets/sfx/ (see
## assets/sfx/CREDITS.md). A file at res://assets/sfx/<name>.{wav,ogg} is used
## INSTEAD of the synth; scripts/SfxSynth.gd's procedural synthesiser stays as
## an automatic fallback for any event whose file is missing, so the game is
## never silent (split into its own RefCounted script so the coverage
## instrumenter, which skips autoloads, can still reach it). See
## assets/sfx/README.md to add or swap clips.

const SfxSynthRef = preload("res://scripts/SfxSynth.gd")
const ASSET_DIR := "res://assets/sfx"
const VOICES := 8            # concurrent AudioStreamPlayers (overlapping sounds)

# Every event Sfx knows how to play.
const NAMES: Array[StringName] = [
	&"hit", &"shoot", &"rout", &"death", &"select", &"order", &"victory", &"defeat",
	&"whistle",
]

# Per-event minimum gap (seconds) between plays, so rapid repeats (e.g. a melee
# line trading blows every tick) don't pile up. 0 = never throttled.
const THROTTLE := {
	&"hit": 0.06,
	&"shoot": 0.08,
	&"rout": 0.20,
	&"death": 0.12,
	&"select": 0.0,
	&"order": 0.0,
	&"victory": 0.0,
	&"defeat": 0.0,
	&"whistle": 0.4,
}

var _streams: Dictionary = {}        # StringName -> AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_played: Dictionary = {}    # StringName -> msec
# Presentation-only RNG for playback pitch jitter. Deliberately NOT Replay.rng —
# touching the seeded sim stream here would desync replays.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # sounds keep firing while paused
	for _i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_build_sounds()
	_rng.randomize()


## Play the named sound (one of NAMES). No-op if SFX are disabled, the name is
## unknown, or the same event played within its throttle window. pitch_jitter
## randomises pitch ±fraction so repeats don't sound mechanically identical.
func play(name: StringName, pitch_jitter: float = 0.06) -> void:
	if not Settings.sfx_enabled:
		return
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var now: int = Time.get_ticks_msec()
	var gap_ms: float = float(THROTTLE.get(name, 0.0)) * 1000.0
	if gap_ms > 0.0 and now - int(_last_played.get(name, -1000000)) < gap_ms:
		return
	_last_played[name] = now
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


# --- sound construction ----------------------------------------------------

func _build_sounds() -> void:
	# Deterministic synthesis: SfxSynthRef seeds its own RNG (default 1), so the
	# placeholder set sounds the same every run (playback pitch jitter below is
	# randomised separately, via this node's own _rng).
	var synthesiser := SfxSynthRef.new(1)
	for event_name in NAMES:
		var asset := _load_asset(event_name)
		_streams[event_name] = asset if asset != null else synthesiser.synth(event_name)


## Prefer a real audio file under assets/sfx/ if present (the drop-in upgrade
## path), falling back to the synthesised placeholder otherwise.
func _load_asset(name: StringName) -> AudioStream:
	for ext in ["wav", "ogg"]:
		var path: String = "%s/%s.%s" % [ASSET_DIR, name, ext]
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is AudioStream:
				return res
	return null
