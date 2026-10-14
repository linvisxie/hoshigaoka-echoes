## Keep logical focus for navigation, show its outline only for keyboard/gamepad.
## Node-owned signal connections disappear with each button; no global button cache.
extends Node

var outline: StyleBox
var empty := StyleBoxEmpty.new()
var input_mode: Node

func _ready() -> void:
	input_mode = get_node("/root/App")
	input_mode.connect("ui_input_mode_changed",_apply)
	refresh()

func refresh() -> void:
	outline = (get_parent() as Button).get_theme_stylebox("focus")
	_apply(bool(input_mode.get("keyboard_navigation")) if input_mode!=null else false)

func _apply(keyboard: bool) -> void:
	(get_parent() as Button).add_theme_stylebox_override("focus",outline if keyboard else empty)
