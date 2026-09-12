extends RefCounted
## Order-mode keybinding defaults and query/rebind helpers.

const DEFAULT_ORDER_BINDINGS := {
	"hold": KEY_H,
	"attack_flank": KEY_F,
	"attack_rear": KEY_R,
	"skirmish": KEY_K,
	"support": KEY_G,
	"cycle_charge": KEY_J,
	# KEY_W collides with the fixed WASD camera-pan keys (CameraController.gd) --
	# every other unused letter key is already claimed by a fixed formation/UI
	# hotkey (see SelectionManager.gd/HUD.gd), so this and roll_the_line's
	# binding fall back to the punctuation row instead.
	"sweep_routers": KEY_COMMA,
	"roll_the_line": KEY_SEMICOLON,
	"pin_down": KEY_PERIOD,
	# all_out_attack's original default (KEY_PERIOD) now collides with pin_down
	# above (added independently by another PR), so it falls back to the next
	# free punctuation key. KEY_SLASH is claimed for the shortcuts dialog
	# (Shift+/, see HUD._is_shortcuts_keypress); KEY_BRACKETLEFT and
	# KEY_BRACKETRIGHT are claimed for frontage resize (SelectionManager.gd),
	# so apostrophe is the next unclaimed punctuation key.
	"all_out_attack": KEY_APOSTROPHE,
	# Same letter-key exhaustion as above; comma/semicolon/period/apostrophe are
	# already taken, so chase takes the next punctuation-row key over.
	"chase": KEY_BACKSLASH,
	# Comma/semicolon/period/apostrophe/backslash are all taken; minus is the next
	# unclaimed punctuation-row key.
	"wedge_charge": KEY_MINUS,
	# Comma/semicolon/period/apostrophe/backslash/minus are all taken; equals is the next
	# unclaimed punctuation-row key. Shift+this key arms/issues the "indefinite" push
	# variant instead of the default "just clear the line" push (SelectionManager.gd).
	"knockback_focus": KEY_EQUAL,
	# Every letter key and the whole punctuation row to the right of the home keys
	# (comma/semicolon/period/apostrophe/backslash/minus/equals) is already claimed by
	# an earlier order mode above. Backtick (unshifted grave accent left of "1")
	# is the next unclaimed key on the keyboard.
	"give_ground": KEY_QUOTELEFT,
	# KEY_P collides with HUD._is_pause_keypress()'s pause toggle; KEY_SLASH is the next unclaimed key.
	"push": KEY_SLASH,
	# Every letter key, digit (control groups), and punctuation-row key is now claimed by an
	# earlier order mode, a fixed camera/UI hotkey, or a maneuver drill.
	# See SelectionManager.gd and HUD.gd's own key maps; there is no free key left on
	# the main keyboard rows. Function keys are otherwise unused in this project.
	# F1 and F5 are the two exceptions -- HUD._is_tray_toggle_keypress and
	# HUD._is_slowmo_keypress -- see their own comments on why F-keys are the
	# fallback once every other key is spoken for. F2 is both free and, like F1
	# and F5, immune to Godot's built-in UI action bindings.
	"multiple_engage": KEY_F2,
	# F1/F2 are already claimed (tray toggle, multiple_engage above); F3 is the next free
	# function key.
	"march_to_contact": KEY_F3,
	# F1/F2/F3 are already claimed (tray toggle, multiple_engage, march_to_contact above);
	# F4 is the next free function key.
	"brace": KEY_F4,
	# F1..F5 are claimed (F5 is slowmo); F6 is the next free function key.
	"flanking_maneuver": KEY_F6,
}


static func get_binding(bindings: Dictionary, slug: String) -> int:
	return int(bindings.get(slug, DEFAULT_ORDER_BINDINGS.get(slug, KEY_NONE)))


static func slug_for_keycode(bindings: Dictionary, keycode: int) -> String:
	for slug in bindings:
		if int(bindings[slug]) == keycode:
			return slug
	return ""


static func set_binding(bindings: Dictionary, slug: String, keycode: int) -> bool:
	if not DEFAULT_ORDER_BINDINGS.has(slug) or int(bindings.get(slug, -1)) == keycode:
		return false
	bindings[slug] = keycode
	return true


static func reset_bindings() -> Dictionary:
	return DEFAULT_ORDER_BINDINGS.duplicate()


## Fixed keys that cannot be rebound to order modes in the Keybindings dialog because
## they own dedicated actions or fixed modifier chords (ShortcutsOverlay).
const RESERVED_KEYS := {
	KEY_M: "Merge",
	KEY_I: "Rank relief",
	KEY_X: "Group attack mode",
	KEY_T: "Formation",
	KEY_O: "Anti-cavalry square",
	KEY_L: "Shield wall",
	KEY_U: "Testudo",
	KEY_BRACKETLEFT: "Line width",
	KEY_BRACKETRIGHT: "Line width",
	KEY_B: "Explicatio",
	KEY_N: "Duplicatio",
	KEY_Y: "Form-up split mode",
	KEY_LEFT: "Nudge left",
	KEY_RIGHT: "Nudge right",
	KEY_UP: "Nudge forward",
	KEY_DOWN: "Nudge / Disengage",
	KEY_V: "About-face / Countermarch",
	KEY_Q: "Quarter-turn left",
	KEY_E: "Quarter-turn right",
	KEY_Z: "Wheel left",
	KEY_C: "Wheel right",
	KEY_0: "Control group 0",
	KEY_1: "Control group 1",
	KEY_2: "Control group 2",
	KEY_3: "Control group 3",
	KEY_4: "Control group 4",
	KEY_5: "Control group 5",
	KEY_6: "Control group 6",
	KEY_7: "Control group 7",
	KEY_8: "Control group 8",
	KEY_9: "Control group 9",
	KEY_W: "Camera pan",
	KEY_A: "Camera pan",
	KEY_S: "Camera pan",
	KEY_D: "Camera pan",
	KEY_SPACE: "Formation preview",
	KEY_P: "Pause",
	KEY_F1: "Unit card tray",
	KEY_F5: "Slow motion",
	KEY_F7: "Fog of war",
}


static func is_reserved_key(keycode: int) -> bool:
	return RESERVED_KEYS.has(keycode)


static func reserved_label(keycode: int) -> String:
	return str(RESERVED_KEYS.get(keycode, ""))

