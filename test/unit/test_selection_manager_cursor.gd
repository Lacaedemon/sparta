extends GutTest
## Tests for SelectionManager in-scene cursor: sprite visibility and texture
## as order mode changes. Verifies the path that replaces Input.set_custom_mouse_cursor
## so the macOS imgrep null-conversion crash cannot be triggered by order-mode arming.

const BattleRef = preload("res://scripts/Battle.gd")


func _sm() -> SelectionManager:
	var sm: SelectionManager = SelectionManager.new()
	add_child_autofree(sm)
	return sm


func test_cursor_sprite_hidden_at_start() -> void:
	var sm := _sm()
	assert_false(sm._cursor_sprite.visible,
		"cursor sprite is hidden in NORMAL mode after _ready()")


func test_cursor_sprite_visible_when_armed() -> void:
	var sm := _sm()
	sm._set_armed_mode(BattleRef.OrderMode.HOLD)
	assert_true(sm._cursor_sprite.visible,
		"cursor sprite is shown when an order mode is armed")


func test_cursor_sprite_has_texture_when_armed() -> void:
	var sm := _sm()
	sm._set_armed_mode(BattleRef.OrderMode.ATTACK_FLANK)
	assert_not_null(sm._cursor_sprite.texture,
		"cursor sprite receives a texture when armed")


func test_cursor_sprite_hidden_when_disarmed() -> void:
	var sm := _sm()
	sm._set_armed_mode(BattleRef.OrderMode.HOLD)
	sm._set_armed_mode(BattleRef.OrderMode.NORMAL)
	assert_false(sm._cursor_sprite.visible,
		"cursor sprite is hidden again when returning to NORMAL mode")


func test_every_order_mode_has_a_distinct_order_cursor_color() -> void:
	# Guards against a new OrderMode falling through _order_mode_color's match
	# to the Color.WHITE default, where it would be visually indistinguishable
	# from the unmapped-mode fallback (and, if two modes collide, from each other).
	var sm := _sm()
	var seen: Dictionary = {}
	for mode in BattleRef.OrderMode.values():
		if mode == BattleRef.OrderMode.NORMAL:
			continue
		var mode_color: Color = sm._order_mode_color(mode)
		assert_ne(mode_color, Color.WHITE,
			"OrderMode %d has its own order-cursor color, not the unmapped-mode fallback" % mode)
		assert_false(seen.has(mode_color),
			"OrderMode %d's color collides with OrderMode %s's" % [mode, seen.get(mode_color)])
		seen[mode_color] = mode
