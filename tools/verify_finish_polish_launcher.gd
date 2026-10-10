extends Node

func _ready() -> void:
	var driver: Node = load("res://tools/verify_finish_polish.gd").new()
	get_tree().root.add_child.call_deferred(driver)
