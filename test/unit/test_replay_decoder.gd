extends GutTest
## Tests for ReplayDecoder: deserialization of replay states, default fallback
## for missing optional tracks, and complete order field extraction.

const ReplayDecoderScript = preload("res://scripts/ReplayDecoder.gd")


func test_decode_payload_lacking_optional_tracks_yields_empty_arrays() -> void:
	var minimal_payload := {
		"version": 1,
		"physics_tps": 60,
		"seed": "4242",
	}
	var decoded := ReplayDecoderScript.decode(minimal_payload)
	assert_eq(decoded["version"], 1, "version matches")
	assert_eq(decoded["physics_tps"], 60, "physics_tps matches")
	assert_eq(decoded["seed"], 4242, "seed parsed as int")
	assert_eq(decoded["orders"].size(), 0, "orders empty")
	assert_eq(decoded["camera"].size(), 0, "camera empty")
	assert_eq(decoded["pointer"].size(), 0, "pointer empty")
	assert_eq(decoded["keys"].size(), 0, "keys empty")
	assert_eq(decoded["time_scale"].size(), 0, "time_scale empty")
	assert_eq(decoded["map"].size(), 0, "map empty")
	assert_eq(decoded["spawn_fingerprint"], "", "spawn_fingerprint empty")
	assert_eq(decoded["commit_sha"], "", "commit_sha empty")


func test_decode_orders_full_fields() -> void:
	var payload := {
		"version": 1,
		"orders": [
			{
				"tick": 42,
				"units": [10, 20],
				"x": 100.5,
				"y": 200.5,
				"target": 5,
				"mode": 1,
				"formation": 2,
				"frontage": 6,
				"anchor_offset": 8.0,
				"face": 3.14,
				"group_attack": 1,
				"form_up_group": 2,
				"walk_advance_toggle": 1,
				"reform_toggle": 1,
				"file_major_reform_mode_toggle": 1,
				"line": 3,
			}
		]
	}
	var decoded := ReplayDecoderScript.decode(payload)
	var o: Dictionary = decoded["orders"][0]
	assert_eq(o["tick"], 42)
	assert_eq(o["units"], [10, 20])
	assert_eq(o["x"], 100.5)
	assert_eq(o["y"], 200.5)
	assert_eq(o["target"], 5)
	assert_eq(o["mode"], 1)
	assert_eq(o["formation"], 2)
	assert_eq(o["frontage"], 6)
	assert_eq(o["anchor_offset"], 8.0)
	assert_eq(o["face"], 3.14)
	assert_eq(o["group_attack"], 1)
	assert_eq(o["form_up_group"], 2)
	assert_eq(o["walk_advance_toggle"], 1)
	assert_eq(o["reform_toggle"], 1)
	assert_eq(o["file_major_reform_mode_toggle"], 1)
	assert_eq(o["line"], 3)


func test_decode_pointer_drag_and_non_drag() -> void:
	var payload := {
		"pointer": [
			{
				"tick": 1,
				"x": 10.0,
				"y": 20.0,
				"drag": false,
				"sel": [1],
				"mode": 0,
			},
			{
				"tick": 2,
				"x": 30.0,
				"y": 40.0,
				"drag": true,
				"sx": 15.0,
				"sy": 25.0,
				"sel": [2],
				"mode": 1,
			}
		]
	}
	var decoded := ReplayDecoderScript.decode(payload)
	var p0: Dictionary = decoded["pointer"][0]
	assert_false(p0["drag"])
	assert_false(p0.has("sx"))
	var p1: Dictionary = decoded["pointer"][1]
	assert_true(p1["drag"])
	assert_eq(p1["sx"], 15.0)
	assert_eq(p1["sy"], 25.0)
