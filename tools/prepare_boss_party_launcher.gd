extends Node
func _ready() -> void:
	var driver: Node=load("res://tools/prepare_boss_party.gd").new()
	get_tree().root.add_child.call_deferred(driver)
