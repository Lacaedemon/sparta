extends RefCounted
## Persistence helper for game settings (ConfigFile load/save).

const SettingsKeybindingsRef = preload("res://scripts/SettingsKeybindings.gd")

const SECTIONS := {
	"edge_scroll": "camera",
	"sfx_enabled": "audio",
	"form_up_dist_default": "gameplay",
	"form_up_dist_cycle": "gameplay",
	"show_distance_legend": "camera",
	"show_order_distance": "camera",
	"show_unit_speed": "camera",
	"show_soldier_ids": "camera",
	"show_engaged_highlight": "camera",
	"show_position_anchor": "camera",
	"show_fps": "camera",
	"show_performance_graph": "camera",
	"show_unit_card_tray": "camera",
	"tray_row_order_placement": "gameplay",
	"fps_corner": "camera",
}


static func load_from_path(path: String, defaults: Dictionary, form_up_dist_max: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var out: Dictionary = defaults.duplicate(true)
	for key in SECTIONS:
		var section: String = SECTIONS[key]
		var default_val: Variant = defaults.get(key)
		var val: Variant = cfg.get_value(section, key, default_val)
		match typeof(default_val):
			TYPE_BOOL:
				out[key] = bool(val)
			TYPE_INT:
				out[key] = int(val)
			_:
				out[key] = val
	var raw_cycle: Variant = out.get("form_up_dist_cycle", [])
	if raw_cycle is Array:
		out["form_up_dist_cycle"] = (raw_cycle as Array).filter(
			func(v: Variant) -> bool: return v is int and v >= 0 and v <= form_up_dist_max
		)
	else:
		var default_cycle: Variant = defaults.get("form_up_dist_cycle", [])
		if default_cycle is Array:
			out["form_up_dist_cycle"] = (default_cycle as Array).duplicate()
		else:
			out["form_up_dist_cycle"] = []
	var base_bindings: Dictionary = defaults.get("order_bindings", SettingsKeybindingsRef.DEFAULT_ORDER_BINDINGS)
	var bindings: Dictionary = {}
	for slug in SettingsKeybindingsRef.DEFAULT_ORDER_BINDINGS:
		var default_val: int = int(base_bindings.get(slug, SettingsKeybindingsRef.DEFAULT_ORDER_BINDINGS[slug]))
		var val: int = int(cfg.get_value("keybindings", slug, default_val))
		if slug == "push" and val == KEY_P:
			val = KEY_SLASH
		bindings[slug] = val
	out["order_bindings"] = bindings
	return out


static func save_to_path(path: String, values: Dictionary) -> Error:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for key in SECTIONS:
		cfg.set_value(SECTIONS[key], key, values[key])
	var bindings: Dictionary = values.get("order_bindings", {})
	for slug in bindings:
		cfg.set_value("keybindings", slug, int(bindings[slug]))
	return cfg.save(path)
