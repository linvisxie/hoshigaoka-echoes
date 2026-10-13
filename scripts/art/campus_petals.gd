class_name CampusPetals
extends Control

var ambient_time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	ambient_time += delta
	queue_redraw()

func _draw() -> void:
	# Same restrained drift, count, shape and opacity as the title screen.
	var factor := size / Vector2(1920,1080)
	for i: int in range(22):
		var seed := float(i)
		var x := fposmod(seed*137.7+ambient_time*(18+fmod(seed,4)*5),2000)-40
		var y := fposmod(seed*73.3+ambient_time*(10+fmod(seed,3)*3),1160)-40
		var center := Vector2(x,y+sin(ambient_time*.8+seed)*20)*factor
		var radius := (3+fmod(seed,4))*minf(factor.x,factor.y)
		var angle := ambient_time*.45+seed
		var axis := Vector2(cos(angle),sin(angle))*radius
		var side := axis.orthogonal()*.38
		draw_colored_polygon(PackedVector2Array([center-axis,center+side,center+axis,center-side]),Color(.96,.64,.78,.24+fmod(seed,3)*.10))
