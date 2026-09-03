extends GutTest
## Unit tests for SettingsKeybindings helper: defaults, query, rebind, and reset.

const SettingsKeybindings = preload("res://scripts/SettingsKeybindings.gd")


func test_defaults_lookup() -> void:
	var defaults: Dictionary = SettingsKeybindings.DEFAULT_ORDER_BINDINGS
	assert_eq(SettingsKeybindings.get_binding(defaults, "hold"), KEY_H, "hold defaults to H")
	assert_eq(SettingsKeybindings.get_binding(defaults, "attack_flank"), KEY_F, "attack_flank defaults to F")
	assert_eq(SettingsKeybindings.get_binding({}, "hold"), KEY_H, "empty dictionary falls back to default")


func test_unknown_slug_lookup() -> void:
	var defaults: Dictionary = SettingsKeybindings.DEFAULT_ORDER_BINDINGS
	assert_eq(SettingsKeybindings.get_binding(defaults, "not_a_slug"), KEY_NONE, "unknown slug returns KEY_NONE")


func test_reverse_lookup() -> void:
	var defaults: Dictionary = SettingsKeybindings.DEFAULT_ORDER_BINDINGS
	assert_eq(SettingsKeybindings.slug_for_keycode(defaults, KEY_H), "hold", "KEY_H resolves back to hold")
	assert_eq(SettingsKeybindings.slug_for_keycode(defaults, KEY_Z), "", "unbound keycode resolves to empty string")


func test_set_binding_returns_true_on_change_and_false_on_noop() -> void:
	var bindings: Dictionary = SettingsKeybindings.reset_bindings()
	var changed: bool = SettingsKeybindings.set_binding(bindings, "hold", KEY_Z)
	assert_true(changed, "rebind returns true when keycode changes")
	assert_eq(bindings["hold"], KEY_Z, "rebind updates the dictionary")

	var noop: bool = SettingsKeybindings.set_binding(bindings, "hold", KEY_Z)
	assert_false(noop, "rebind returns false on unchanged keycode")

	var unknown: bool = SettingsKeybindings.set_binding(bindings, "not_a_slug", KEY_Z)
	assert_false(unknown, "rebind returns false on unknown slug")


func test_reset_produces_fresh_dictionary_equal_to_defaults() -> void:
	var copy: Dictionary = SettingsKeybindings.reset_bindings()
	assert_eq(copy, SettingsKeybindings.DEFAULT_ORDER_BINDINGS, "reset returns defaults content")
	copy["hold"] = KEY_Z
	assert_eq(SettingsKeybindings.DEFAULT_ORDER_BINDINGS["hold"], KEY_H, "mutating copy does not alter defaults")
