extends GutTest
## Unit stats panel order-tree display (docs/atomic-order-decomposition-design.md, "HUD: the
## tree renders naturally"): _order_tree_rows flattens current_order's tree into display rows
## depth-first, honoring a per-path expanded/collapsed map. Pure and Order-only, so it's
## tested directly against plain Order trees with no HUD scene/_ready dependency.

const HUDScript = preload("res://scripts/HUD.gd")
const OrderScript = preload("res://scripts/Order.gd")


func _hud() -> HUDScript:
	var h := HUDScript.new()
	autofree(h)
	return h


func test_leaf_order_is_a_single_row() -> void:
	var h := _hud()
	var order: OrderScript = OrderScript.new_move(Vector2(10, 10))
	var rows: Array = h._order_tree_rows(order, {})
	assert_eq(rows.size(), 1, "no children -- exactly one row")
	assert_eq(rows[0]["order"], order)
	assert_eq(rows[0]["depth"], 0)
	assert_eq(rows[0]["path"], "0")
	assert_false(rows[0]["has_children"], "a leaf order reports no children")


func test_null_order_produces_no_rows() -> void:
	var h := _hud()
	assert_eq(h._order_tree_rows(null, {}), [], "no current_order at all -- nothing to show")


func _rear_move_composite() -> OrderScript:
	# Mirrors Unit.begin_pivot's shape: a MOVE parent whose children are the opening turn
	# and the march leaf.
	var parent: OrderScript = OrderScript.new_move(Vector2(500, 250))
	var turn: OrderScript = OrderScript.new_about_face()
	var march: OrderScript = OrderScript.new_move(Vector2(500, 250))
	turn.parent = parent
	march.parent = parent
	parent.children = [turn, march]
	return parent


func test_composite_expands_children_by_default() -> void:
	var h := _hud()
	var parent := _rear_move_composite()
	var rows: Array = h._order_tree_rows(parent, {})
	assert_eq(rows.size(), 3, "parent + 2 children, expanded with no entry in the map")
	assert_eq(rows[0]["path"], "0")
	assert_true(rows[0]["has_children"])
	assert_eq(rows[1]["order"], parent.children[0])
	assert_eq(rows[1]["depth"], 1)
	assert_eq(rows[1]["path"], "0.0")
	assert_false(rows[1]["has_children"])
	assert_eq(rows[2]["order"], parent.children[1])
	assert_eq(rows[2]["path"], "0.1")


func test_collapsed_composite_hides_its_children() -> void:
	var h := _hud()
	var parent := _rear_move_composite()
	var rows: Array = h._order_tree_rows(parent, {"0": false})
	assert_eq(rows.size(), 1, "collapsed -- only the composite's own row")
	assert_eq(rows[0]["order"], parent)


func test_nested_composite_paths_are_dot_joined() -> void:
	var h := _hud()
	var grandparent: OrderScript = OrderScript.new_move(Vector2(0, 0))
	var parent := _rear_move_composite()
	parent.parent = grandparent
	grandparent.children = [parent]
	var rows: Array = h._order_tree_rows(grandparent, {})
	assert_eq(rows.size(), 4, "grandparent + parent + parent's 2 children")
	assert_eq(rows[0]["path"], "0")
	assert_eq(rows[1]["path"], "0.0")
	assert_eq(rows[2]["path"], "0.0.0")
	assert_eq(rows[3]["path"], "0.0.1")


func test_custom_root_path_is_honored() -> void:
	# _rebuild_order_tree seeds the walk with "<unit id>:0" so two selected units never share
	# collapsed state for the same tree shape; confirm an arbitrary root threads through.
	var h := _hud()
	var order: OrderScript = OrderScript.new_move(Vector2(1, 1))
	var rows: Array = h._order_tree_rows(order, {}, 0, "42:0")
	assert_eq(rows[0]["path"], "42:0")
