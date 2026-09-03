extends GutTest
## Tests for ReplayCodec: constants, encode serialization (including float timestamp),
## and full round-trip with ReplayDecoder.

const ReplayCodecScript = preload("res://scripts/ReplayCodec.gd")
const ReplayDecoderScript = preload("res://scripts/ReplayDecoder.gd")


func test_constants() -> void:
	assert_eq(ReplayCodecScript.FORMAT_VERSION, 1, "format version constant is 1")
	assert_eq(ReplayCodecScript.PHYSICS_TPS, 60, "physics tps constant is 60")


func test_encode_created_timestamp_float_preserved() -> void:
	var float_time := 1788429165.525
	var encoded := ReplayCodecScript.encode({"created": float_time})
	assert_eq(encoded["created"], float_time, "created timestamp float value is preserved")


func test_encode_and_decode_round_trip_with_all_tracks() -> void:
	var order_pos := Vector2(120.0, 340.0)
	var cam_pos := Vector2(15.0, 25.0)
	var ptr_pos := Vector2(40.0, 60.0)
	var drag_start_pos := Vector2(30.0, 50.0)
	var input_state := {
		"seed": 987654321,
		"result": "Defeat",
		"duration_ticks": 300,
		"commit_sha": "abc1234",
		"map": {"type": "plains", "width": 800},
		"spawn_fingerprint": "fp_hash_1",
		"git_dirty_status": "dirty",
		"orders": [
			{
				"tick": 10,
				"units": [1, 2],
				"x": order_pos.x,
				"y": order_pos.y,
				"target": -1,
				"mode": 0,
				"formation": 2,
				"frontage": 4,
				"anchor_offset": 12.5,
				"face": 1.57,
				"group_attack": 1,
				"form_up_group": 3,
				"walk_advance_toggle": 1,
				"reform_toggle": 1,
				"file_major_reform_mode_toggle": 0,
				"line": 1,
			}
		],
		"camera": [
			{"tick": 0, "x": cam_pos.x, "y": cam_pos.y, "zoom": 1.5}
		],
		"pointer": [
			{
				"tick": 5, "x": ptr_pos.x, "y": ptr_pos.y, "drag": true,
				"sx": drag_start_pos.x, "sy": drag_start_pos.y,
				"sel": [1], "mode": 2,
			}
		],
		"keys": [
			{"tick": 12, "labels": ["F5", "Space"]}
		],
		"time_scale": [
			{"tick": 20, "value": 0.5}
		],
	}

	var encoded := ReplayCodecScript.encode(input_state)
	assert_eq(encoded["version"], 1, "encoded version is 1")
	assert_eq(encoded["seed"], "987654321", "encoded seed is stringified")
	assert_eq(encoded["physics_tps"], 60, "encoded physics tps is 60")
	assert_eq(encoded["commit_sha"], "abc1234", "encoded commit sha matches")
	assert_eq(encoded["orders"].size(), 1, "encoded orders present")
	assert_eq(encoded["camera"].size(), 1, "encoded camera present")
	assert_eq(encoded["pointer"].size(), 1, "encoded pointer present")
	assert_eq(encoded["keys"].size(), 1, "encoded keys present")
	assert_eq(encoded["time_scale"].size(), 1, "encoded time_scale present")

	var decoded := ReplayDecoderScript.decode(encoded)
	assert_eq(decoded["version"], 1, "decoded version is 1")
	assert_eq(decoded["physics_tps"], 60, "decoded physics tps is 60")
	assert_eq(decoded["seed"], 987654321, "decoded seed is integer")
	assert_eq(decoded["commit_sha"], "abc1234", "decoded commit sha matches")
	assert_eq(decoded["spawn_fingerprint"], "fp_hash_1", "decoded spawn fingerprint matches")
	assert_eq(decoded["map"]["width"], 800, "decoded map payload matches")

	var order_entry: Dictionary = decoded["orders"][0]
	assert_eq(order_entry["tick"], 10, "order tick matches")
	assert_eq(order_entry["units"], [1, 2], "order units match")
	var decoded_order_pos := Vector2(float(order_entry["x"]), float(order_entry["y"]))
	assert_eq(decoded_order_pos.x, 120.0, "order x matches")
	assert_eq(decoded_order_pos.y, 340.0, "order y matches")
	assert_eq(order_entry["formation"], 2, "order formation matches")
	assert_eq(order_entry["frontage"], 4, "order frontage matches")
	assert_eq(order_entry["anchor_offset"], 12.5, "order anchor_offset matches")
	assert_eq(order_entry["face"], 1.57, "order face matches")
	assert_eq(order_entry["group_attack"], 1, "order group_attack matches")
	assert_eq(order_entry["form_up_group"], 3, "order form_up_group matches")
	assert_eq(order_entry["walk_advance_toggle"], 1, "order walk_advance_toggle matches")
	assert_eq(order_entry["reform_toggle"], 1, "order reform_toggle matches")
	assert_eq(order_entry["file_major_reform_mode_toggle"], 0, "order file_major_reform_mode_toggle matches")
	assert_eq(order_entry["line"], 1, "order line matches")

	var cam_entry: Dictionary = decoded["camera"][0]
	assert_eq(cam_entry["tick"], 0, "camera tick matches")
	var decoded_cam_pos := Vector2(float(cam_entry["x"]), float(cam_entry["y"]))
	assert_eq(decoded_cam_pos.x, 15.0, "camera x matches")
	assert_eq(decoded_cam_pos.y, 25.0, "camera y matches")
	assert_eq(cam_entry["zoom"], 1.5, "camera zoom matches")

	var ptr_entry: Dictionary = decoded["pointer"][0]
	assert_eq(ptr_entry["tick"], 5, "pointer tick matches")
	var decoded_ptr_pos := Vector2(float(ptr_entry["x"]), float(ptr_entry["y"]))
	assert_eq(decoded_ptr_pos.x, 40.0, "pointer x matches")
	assert_eq(decoded_ptr_pos.y, 60.0, "pointer y matches")
	var decoded_drag_pos := Vector2(float(ptr_entry["sx"]), float(ptr_entry["sy"]))
	assert_eq(decoded_drag_pos.x, 30.0, "pointer drag start x matches")
	assert_eq(decoded_drag_pos.y, 50.0, "pointer drag start y matches")
	assert_true(ptr_entry["drag"], "pointer drag matches")
	assert_eq(ptr_entry["sel"], [1], "pointer sel matches")
	assert_eq(ptr_entry["mode"], 2, "pointer mode matches")

	var key_entry: Dictionary = decoded["keys"][0]
	assert_eq(key_entry["tick"], 12, "key tick matches")
	assert_eq(key_entry["labels"], ["F5", "Space"], "key labels match")

	var ts_entry: Dictionary = decoded["time_scale"][0]
	assert_eq(ts_entry["tick"], 20, "time scale tick matches")
	assert_eq(ts_entry["value"], 0.5, "time scale value matches")

