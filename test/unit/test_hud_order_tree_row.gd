extends GutTest
## Unit stats panel order-tree display, the Control-building half (see test_hud_order_tree.gd
## for the pure _order_tree_rows flattening logic): _rebuild_order_tree turns a live Unit's
## current_order into rows under _order_tree_box, _build_order_tree_row lays out one row's
## indent/toggle/label, and _on_order_tree_toggle flips a path's collapsed state. Needs a real
## HUD (_ready() builds _order_tree_box) and a real Unit (current_order/active_leaf()), unlike
## the pure-Order tests next door.

const HUDScript = preload("res://scripts/HUD.gd")


func _hud() -> HUDScript:
	var h := HUDScript.new()
	add_child_autofree(h)   # runs _ready(): builds _order_tree_box among the rest of the panel
	return h


func _make_unit(uid: int = 1) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 10
	add_child_autofree(u)
	u.uid = uid
	return u


func _rear_move_composite() -> Order:
	# Mirrors Unit.begin_pivot's shape: a MOVE parent whose children are the opening turn and
	# the march leaf; _active_child defaults to 0, so the turn is the active leaf.
	var parent: Order = Order.new_move(Vector2(500, 250))
	var turn: Order = Order.new_about_face()
	var march: Order = Order.new_move(Vector2(500, 250))
	turn.parent = parent
	march.parent = parent
	parent.children = [turn, march]
	return parent


func test_null_unit_hides_the_tree_box() -> void:
	var hud := _hud()
	hud._rebuild_order_tree(null)
	assert_false(hud._order_tree_box.visible)
	assert_eq(hud._order_tree_box.get_children().size(), 0)


func test_unit_with_no_current_order_hides_the_tree_box() -> void:
	var hud := _hud()
	var u := _make_unit()
	hud._rebuild_order_tree(u)
	assert_false(hud._order_tree_box.visible)


func test_freed_unit_hides_the_tree_box() -> void:
	var hud := _hud()
	var u := Unit.new()
	u.max_soldiers = 10
	add_child(u)
	u.set_current_order(Order.new_move(Vector2(1, 1)))
	u.queue_free()
	await get_tree().process_frame
	hud._rebuild_order_tree(u)
	assert_false(hud._order_tree_box.visible, "a freed unit reference must not be dereferenced")


func test_leaf_order_renders_a_single_highlighted_row() -> void:
	var hud := _hud()
	var u := _make_unit()
	var order := Order.new_move(Vector2(10, 10))
	u.set_current_order(order)
	hud._rebuild_order_tree(u)
	assert_true(hud._order_tree_box.visible)
	var rows := hud._order_tree_box.get_children()
	assert_eq(rows.size(), 1, "a leaf order is exactly one row")
	var row: HBoxContainer = rows[0]
	assert_eq(row.get_child_count(), 2, "no indent at depth 0, plus a toggle-gap and the label")
	var lbl: Label = row.get_child(1)
	assert_string_starts_with(lbl.text, "▶ ", "the only order is also the active leaf")
	assert_true(lbl.has_theme_color_override("font_color"), "the active leaf gets the amber override")


func test_composite_order_renders_indented_children_with_a_toggle() -> void:
	var hud := _hud()
	var u := _make_unit()
	var parent := _rear_move_composite()
	u.set_current_order(parent)
	hud._rebuild_order_tree(u)
	var rows := hud._order_tree_box.get_children()
	assert_eq(rows.size(), 3, "parent + 2 children, expanded by default")

	var root_row: HBoxContainer = rows[0]
	assert_eq(root_row.get_child_count(), 2, "depth 0 composite: toggle + label, no indent")
	var toggle: Button = root_row.get_child(0)
	assert_eq(toggle.text, "▾", "expanded toggle points down")
	var root_lbl: Label = root_row.get_child(1)
	assert_false(root_lbl.has_theme_color_override("font_color"),
			"the composite root isn't the active leaf itself")

	var turn_row: HBoxContainer = rows[1]
	assert_eq(turn_row.get_child_count(), 3, "depth 1 leaf: indent + toggle-gap + label")
	var indent: Control = turn_row.get_child(0)
	assert_eq(indent.custom_minimum_size, Vector2(hud._ORDER_TREE_INDENT, 0))
	var turn_lbl: Label = turn_row.get_child(2)
	assert_string_starts_with(turn_lbl.text, "▶ ", "the turn child is the active leaf (child 0)")

	var march_row: HBoxContainer = rows[2]
	var march_lbl: Label = march_row.get_child(2)
	assert_false(march_lbl.text.begins_with("▶"), "the march child isn't active yet")


func test_collapsing_a_composite_then_rebuilding_hides_its_children() -> void:
	var hud := _hud()
	var u := _make_unit()
	u.set_current_order(_rear_move_composite())
	hud._rebuild_order_tree(u)
	var root_path: String = "%d:0" % u.get_instance_id()
	hud._on_order_tree_toggle(root_path)
	hud._rebuild_order_tree(u)
	await get_tree().process_frame   # let the collapsed rebuild's queue_free() of the old rows settle
	var rows := hud._order_tree_box.get_children()
	assert_eq(rows.size(), 1, "collapsed -- only the composite's own row survives the rebuild")
	var toggle: Button = rows[0].get_child(0)
	assert_eq(toggle.text, "▸", "collapsed toggle points right")


func test_on_order_tree_toggle_flips_the_expanded_state() -> void:
	var hud := _hud()
	hud._on_order_tree_toggle("0")
	assert_false(hud._order_tree_expanded["0"], "first toggle collapses the default-expanded root")
	hud._on_order_tree_toggle("0")
	assert_true(hud._order_tree_expanded["0"], "second toggle re-expands it")


func test_unchanged_rebuild_reuses_the_same_toggle_button_instance() -> void:
	# SelectionManager._process() calls _refresh_hud() -> show_unit() -> _rebuild_order_tree()
	# every single frame while a unit is selected, whether or not anything about its order tree
	# actually changed. _rebuild_order_tree() used to queue_free() and recreate every row
	# Control -- including the toggle Buttons -- on every one of those calls. That's the
	# structural invariant a real mouse click depends on: Godot's BaseButton only emits
	# `pressed` when the mouse-down and mouse-up land on the SAME Button instance, and a real
	# click's down/up pair spans multiple frames, so a rebuild between them would silently
	# swap out the button the down click landed on. Two back-to-back rebuilds against the same
	# unchanged order tree must therefore leave the existing row Controls (and their toggle
	# Buttons) alone.
	var hud := _hud()
	var u := _make_unit()
	u.set_current_order(_rear_move_composite())
	hud._rebuild_order_tree(u)
	var root_row: HBoxContainer = hud._order_tree_box.get_children()[0]
	var toggle: Button = root_row.get_child(0)

	hud._rebuild_order_tree(u)   # nothing about u.current_order changed since the call above

	var root_row_again: HBoxContainer = hud._order_tree_box.get_children()[0]
	assert_eq(root_row_again, root_row,
			"an unchanged tree must not tear down and recreate the row Controls")
	var toggle_again: Button = root_row_again.get_child(0)
	assert_eq(toggle_again, toggle,
			"an unchanged tree must not replace the toggle Button a mid-click frame could land on")


# A full end-to-end version driving Viewport.push_input() was tried and reverted: it hung
# headless (no window/renderer to drive input processing to completion in this test
# environment), and Control._gui_input is an engine-internal virtual Viewport input routing
# dispatches to -- not a public method a native Button exposes for a GDScript test to call
# directly. test_unchanged_rebuild_reuses_the_same_toggle_button_instance above already proves
# the structural invariant a real click depends on (the same Button instance survives an
# unchanged rebuild), which is what actually matters: if the instance is stable, whatever
# engine-internal state correlates a down click with its matching up click is too.
