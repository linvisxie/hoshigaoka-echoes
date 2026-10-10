extends SceneTree
func _init() -> void:
	var image := Image.new()
	var svg := FileAccess.get_file_as_string("res://assets/art/ui/school_crest_six.svg")
	image.load_svg_from_string(svg,2.0)
	image.save_png("res://tools/source_art/school_crest_six_reference.png")
	quit()
