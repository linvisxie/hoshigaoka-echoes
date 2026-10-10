extends Node

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	var driver := Node.new()
	driver.set_script(load("res://tools/verify_campaign_driver.gd"))
	get_tree().root.add_child(driver)
