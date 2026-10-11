extends Node
func _ready() -> void:
	var driver: Node=load("res://tools/verify_chapter_fresh_driver.gd").new()
	get_tree().root.add_child.call_deferred(driver)
