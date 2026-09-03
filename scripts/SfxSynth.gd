extends RefCounted
## Procedural sfx synthesiser (see scripts/Sfx.gd for how it is used as a fallback).
## Split out so the coverage instrumenter can reach it: Sfx.gd is an autoload,
## and autoloads are excluded from instrumentation (see test/pre_run_hook.gd).
## Deterministic given a seed, so the placeholder set sounds the same every run.

const MIX_RATE := 22050

var _rng := RandomNumberGenerator.new()


func _init(rng_seed: int = 1) -> void:
	_rng.seed = rng_seed


## Build a placeholder sound for an event from one or more decaying "blips".
func synth(name: StringName) -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	match name:
		&"hit":   # melee thud: low body + a noise transient
			buf = blip(buf, 0.0, 0.12, 180.0, 90.0, "sine", 0.7)
			buf = blip(buf, 0.0, 0.04, 0.0, 0.0, "noise", 0.25)
		&"shoot":   # arrow: bright down-sweep + airy noise
			buf = blip(buf, 0.0, 0.10, 1300.0, 420.0, "saw", 0.4)
			buf = blip(buf, 0.0, 0.04, 0.0, 0.0, "noise", 0.3)
		&"rout":   # falling whistle
			buf = blip(buf, 0.0, 0.30, 520.0, 160.0, "square", 0.35)
		&"death":   # low descending knell
			buf = blip(buf, 0.0, 0.28, 220.0, 70.0, "sine", 0.6)
		&"select":   # short crisp click
			buf = blip(buf, 0.0, 0.05, 900.0, 900.0, "square", 0.3)
		&"order":   # short up-blip (acknowledge)
			buf = blip(buf, 0.0, 0.06, 600.0, 760.0, "square", 0.3)
		&"victory":   # rising C-E-G arpeggio
			buf = blip(buf, 0.00, 0.16, 523.0, 523.0, "square", 0.4)
			buf = blip(buf, 0.12, 0.16, 659.0, 659.0, "square", 0.4)
			buf = blip(buf, 0.24, 0.30, 784.0, 784.0, "square", 0.4)
		&"defeat":   # falling G-Eb-Bb arpeggio
			buf = blip(buf, 0.00, 0.20, 392.0, 392.0, "saw", 0.4)
			buf = blip(buf, 0.18, 0.20, 311.0, 311.0, "saw", 0.4)
			buf = blip(buf, 0.36, 0.40, 233.0, 233.0, "saw", 0.4)
		&"whistle":   # rising piercing tone with a brief sustain
			buf = blip(buf, 0.00, 0.14, 2400.0, 2900.0, "sine", 0.50)
			buf = blip(buf, 0.10, 0.08, 2900.0, 2700.0, "sine", 0.30)
		_:
			# Unknown event: return null so callers' null guards skip it at runtime.
			push_warning("SfxSynth.synth: no waveform defined for event '%s'" % name)
			return null
	return make_wav(buf)


## Add one decaying tone/noise burst into buf (grown as needed) and return it.
## Callers reassign (buf = blip(buf, ...)) so the result is correct regardless of
## GDScript's packed-array copy-on-write. Frequency sweeps linearly f0 -> f1.
func blip(buf: PackedFloat32Array, start_s: float, dur: float,
		f0: float, f1: float, kind: String, amp: float) -> PackedFloat32Array:
	var n: int = int(dur * MIX_RATE)
	var start_i: int = int(start_s * MIX_RATE)
	if buf.size() < start_i + n:
		buf.resize(start_i + n)
	var phase: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var freq: float = lerpf(f0, f1, t)
		phase += TAU * freq / float(MIX_RATE)
		var w: float
		match kind:
			"sine": w = sin(phase)
			"square": w = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw": w = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			"noise": w = _rng.randf_range(-1.0, 1.0)
			_:
				push_warning("SfxSynth.blip: unknown waveform kind '%s'; using sine" % kind)
				w = sin(phase)
		buf[start_i + i] += w * pow(1.0 - t, 2.0) * amp   # squared decay envelope
	return buf


## Pack mono float samples (-1..1) into a 16-bit PCM AudioStreamWAV.
func make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav
