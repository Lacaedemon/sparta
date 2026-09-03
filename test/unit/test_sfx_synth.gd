extends GutTest
## SfxSynth: the procedural sfx synthesiser split out of the Sfx autoload so the
## coverage instrumenter (which skips autoloads) can reach it. Pins the WAV
## shape, determinism, seed sensitivity, unknown-name/kind fallbacks, and the
## blip/make_wav building blocks directly.

const SfxSynthScript = preload("res://scripts/SfxSynth.gd")
const SfxScript = preload("res://scripts/Sfx.gd")


func test_every_name_produces_a_valid_wav() -> void:
	var synth := SfxSynthScript.new()
	for event_name in SfxScript.NAMES:
		var wav: AudioStreamWAV = synth.synth(event_name)
		assert_not_null(wav, "%s synthesises a stream" % event_name)
		assert_eq(wav.format, AudioStreamWAV.FORMAT_16_BITS, "%s is 16-bit" % event_name)
		assert_eq(wav.mix_rate, 22050, "%s uses the synth mix rate" % event_name)
		assert_false(wav.stereo, "%s is mono" % event_name)
		assert_true(wav.data.size() > 0, "%s has samples" % event_name)
		assert_eq(wav.data.size() % 2, 0, "%s is a whole number of 16-bit samples" % event_name)


func test_select_sample_count_matches_its_blip_duration() -> void:
	# select's only blip is (start_s=0.0, dur=0.05, ...); blip's sample count is
	# int(dur * MIX_RATE), and each sample is 2 bytes (16-bit mono).
	var expected_bytes: int = int(0.05 * 22050) * 2
	var synth := SfxSynthScript.new()
	var wav: AudioStreamWAV = synth.synth(&"select")
	assert_eq(wav.data.size(), expected_bytes, "select's byte count matches its blip duration")


func test_same_seed_is_deterministic_and_different_seed_differs() -> void:
	# "hit" mixes in a noise blip, so it is the event most sensitive to the seed.
	var a := SfxSynthScript.new(7)
	var b := SfxSynthScript.new(7)
	var c := SfxSynthScript.new(8)
	var wav_a: AudioStreamWAV = a.synth(&"hit")
	var wav_b: AudioStreamWAV = b.synth(&"hit")
	var wav_c: AudioStreamWAV = c.synth(&"hit")
	assert_eq(wav_a.data, wav_b.data, "the same seed reproduces byte-identical data")
	assert_ne(wav_a.data, wav_c.data, "a different seed produces different data")


func test_unknown_name_returns_null() -> void:
	var synth := SfxSynthScript.new()
	assert_null(synth.synth(&"not_a_real_event"), "an unknown event name has no waveform")


func test_blip_grows_buffer_and_mixes_additively() -> void:
	var synth := SfxSynthScript.new()
	var buf := PackedFloat32Array()
	buf = synth.blip(buf, 0.0, 0.01, 440.0, 440.0, "sine", 0.5)
	var first_n: int = int(0.01 * 22050)
	assert_eq(buf.size(), first_n, "the first blip grows the buffer to start+n")
	var first_sample: float = buf[0]

	buf = synth.blip(buf, 0.02, 0.01, 220.0, 220.0, "sine", 0.5)
	var second_start: int = int(0.02 * 22050)
	var second_n: int = int(0.01 * 22050)
	assert_eq(buf.size(), second_start + second_n, "a later blip grows the buffer further")
	assert_eq(buf[0], first_sample, "the earlier blip's first sample is unchanged (additive mixing)")


func test_make_wav_clamps_out_of_range_samples() -> void:
	var synth := SfxSynthScript.new()
	var samples := PackedFloat32Array([2.0, -2.0])
	var wav: AudioStreamWAV = synth.make_wav(samples)
	assert_eq(wav.data.decode_s16(0), 32767, "an over-range positive sample clamps to the s16 max")
	# clampf(-2.0, -1.0, 1.0) * 32767.0 is -32767.0, so the floor is -32767, not the
	# s16 minimum of -32768.
	assert_eq(wav.data.decode_s16(2), -32767, "an under-range negative sample clamps to -1.0 * 32767")


func test_unknown_waveform_kind_falls_back_to_sine() -> void:
	var synth := SfxSynthScript.new()
	var sine_buf: PackedFloat32Array = synth.blip(PackedFloat32Array(), 0.0, 0.01, 440.0, 440.0, "sine", 0.5)
	var bogus_buf: PackedFloat32Array = synth.blip(PackedFloat32Array(), 0.0, 0.01, 440.0, 440.0, "triangle", 0.5)
	assert_eq(bogus_buf, sine_buf, "an unrecognised waveform kind renders as sine")
