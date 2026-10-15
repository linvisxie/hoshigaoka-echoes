class_name CampusPetals
extends Control

var ambient_time := 0.0
var breeze := 0.0
var suspended := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	visible = GameSkin.motion_level>0
	if suspended or not visible: return
	ambient_time += minf(delta,.05)
	queue_redraw()

func _draw() -> void:
	draw_field(self,ambient_time,breeze,size/Vector2(1920,1080))

static func draw_field(surface: Control,elapsed: float,wind: float,factor: Vector2) -> void:
	if GameSkin.motion_level==0: return
	# Three fixed depth bands share the same breeze as the foliage and hair.
	for i: int in range(24 if GameSkin.motion_level==1 else 42):
		var seed := float(i)
		var depth := .65 if i<18 else 1.0 if i<35 else 1.35
		var x := fposmod(seed*137.7+elapsed*GameSkin.motion_factor()*(18+fmod(seed,4)*5)*depth,2000)-40
		var y := fposmod(seed*73.3+elapsed*GameSkin.motion_factor()*(10+fmod(seed,3)*3)*depth,1160)-40
		var center := Vector2(x+wind*14*depth*GameSkin.motion_factor(),y+sin(elapsed*.8+seed)*20*depth)*factor
		var radius := (3+fmod(seed,4))*depth*minf(factor.x,factor.y)
		var angle := elapsed*.45+seed
		var axis := Vector2(cos(angle),sin(angle))*radius
		var side := axis.orthogonal()*.38
		surface.draw_colored_polygon(PackedVector2Array([center-axis,center+side,center+axis,center-side]),Color(.98,.69,.82,(.30+fmod(seed,3)*.10)*minf(depth,1.0)))
