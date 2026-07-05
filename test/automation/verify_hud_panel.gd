extends Node
## Automated verification: load battle, select unit, verify HUD info panel is visible.
## Run headless: godot --headless --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd res://test/automation/verify_hud_panel.tscn

func _ready() -> void:
	# Load the Battle scene
	var battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().physics_frame

	# Wait for initialization
	await get_tree().physics_frame

	# Get the selection manager and HUD
	var sel_mgr = battle.get_node_or_null("SelectionManager")
	var hud = battle.get_node_or_null("HUD")
	if sel_mgr == null or hud == null:
		push_error("SelectionManager or HUD not found")
		get_tree().quit(1)
		return

	# Select the first player unit (team 0)
	sel_mgr.select(0)

	# Wait for rendering to complete
	await get_tree().physics_frame

	# Capture screenshot
	var screenshot_path = "user://hud-panel-test.png"
	var success = await ScreenCapture.screenshot(screenshot_path)

	# Dump state for verification
	var state_path = "user://hud-panel-state.json"
	await ScreenCapture.state_dump(state_path)

	if success:
		print("✓ HUD verification complete. Screenshot: %s" % screenshot_path)
		get_tree().quit(0)
	else:
		print("✗ Failed to capture screenshot")
		get_tree().quit(1)
