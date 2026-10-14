class_name CampusPetals
extends Control

var ambient_time := 0.0
var breeze := 0.0
var suspended := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if suspended: return
	ambient_time += minf(delta,.05)
	queue_redraw()

func _draw() -> void:
	# Three fixed depth bands share the same breeze as the foliage and hair.
	var factor := size / Vector2(1920,1080)
	for i: int in range(34):
		var seed := float(i)
		var depth := .55 if i<16 else 1.0 if i<29 else 1.45
		var x := fposmod(seed*137.7+ambient_time*(18+fmod(seed,4)*5)*depth,2000)-40
		var y := fposmod(seed*73.3+ambient_time*(10+fmod(seed,3)*3)*depth,1160)-40
		var center := Vector2(x+breeze*14*depth,y+sin(ambient_time*.8+seed)*20*depth)*factor
		var radius := (3+fmod(seed,4))*depth*minf(factor.x,factor.y)
		var angle := ambient_time*.45+seed
		var axis := Vector2(cos(angle),sin(angle))*radius
		var side := axis.orthogonal()*.38
		draw_colored_polygon(PackedVector2Array([center-axis,center+side,center+axis,center-side]),Color(.96,.64,.78,(.20+fmod(seed,3)*.09)*minf(depth,1.0)))
