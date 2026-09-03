extends RefCounted
## On-disk storage helper for replay files.

const DIR := "user://replays"


static func replays_dir() -> String:
	ensure_dir()
	return DIR


static func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(DIR) == OK


static func timestamped_path(counter: int) -> String:
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	return "%s/battle_%s_%02d.json" % [DIR, stamp, counter]


static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write replay to %s" % path)
		return false
	f.store_string(text)
	f.close()
	return true
