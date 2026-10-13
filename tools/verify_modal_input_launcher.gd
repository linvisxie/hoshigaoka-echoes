extends Node
func _ready() -> void:
	get_tree().root.add_child.call_deferred(load("res://tools/verify_modal_input.gd").new())
