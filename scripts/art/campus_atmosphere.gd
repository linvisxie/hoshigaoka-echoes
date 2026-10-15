## Campus-only presentation. No progression, rewards, input capture or global timers.
class_name CampusAtmosphere
extends Control

const DESIGN := Vector2(1672,941)
const GOLD := Color("e8c990")
const BLUE := Color("8edcff")
const LIGHTS := {
	"观测会活动室":Vector2(350,537),"教学楼":Vector2(658,399),
	"弓道场":Vector2(1101,563),"保健室":Vector2(1394,574)}
const SIGNS := {
	"观测会活动室":Rect2(368,337,198,81),"教学楼":Rect2(577,274,151,49),
	"弓道场":Rect2(995,412,145,50),"保健室":Rect2(1285,427,147,43),
	"校园漫游":Rect2(756,364,169,71),"调查公告板":Rect2(75,571,144,47),
	"继续调查":Rect2(1454,401,205,73),"调查卡：继续调查":Rect2(1384,817,201,38)}

var clock := 0.0
var breeze := 0.0
var gaze := Vector2.ZERO
var hover_key := ""
var blocked := false
var attention := 0.0
var hover_strength := 0.0
var unread: Array[String] = []
var new_record := false
var pending := false
var _last_foley := -10.0
var _click_age := 1.0
var _click_rect := Rect2()
var _blink_at := 3.8
var _blink_age := 1.0
var _foliage: ShaderMaterial
var _mio: ShaderMaterial
var _lights: Control

class Feedback extends Control:
	var atmosphere: Control
	func _draw() -> void:
		if is_instance_valid(atmosphere): atmosphere.paint_feedback(self)

class LightPools extends Control:
	var atmosphere: Control
	func _draw() -> void:
		if is_instance_valid(atmosphere): atmosphere.paint_lights(self)

func create_feedback() -> Control:
	var layer := Feedback.new()
	layer.atmosphere = self
	layer.size = DESIGN
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return layer

func configure(original: Texture2D, world: Texture2D) -> void:
	size = DESIGN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var foliage := TextureRect.new()
	foliage.texture = world
	foliage.size = DESIGN
	foliage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foliage = ShaderMaterial.new()
	_foliage.shader = preload("res://scripts/art/campus_foliage.gdshader")
	foliage.material = _foliage
	add_child(foliage)
	# Soft local blending uses the original picture on both sides of every edge.
	# No silhouette cutout or differently graded clean-plate border remains.
	var girl := TextureRect.new()
	girl.texture = original
	girl.size = DESIGN
	girl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mio = ShaderMaterial.new()
	_mio.shader = preload("res://scripts/art/campus_mio.gdshader")
	_mio.set_shader_parameter("blink_frame",preload("res://assets/art/hub/motion/mio_blink_v1.png"))
	_mio.set_shader_parameter("blink_base",preload("res://assets/art/hub/campus_clean.png"))
	girl.material = _mio
	add_child(girl)
	_lights = LightPools.new()
	_lights.atmosphere = self
	_lights.size = DESIGN
	_lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = additive
	add_child(_lights)

func tick(delta: float, pointer: Vector2, modal: bool, active_window: bool) -> void:
	blocked = modal or not active_window
	var strength := GameSkin.motion_factor()
	visible = strength>0
	if strength<=0: return
	if blocked:
		hover_key = ""
		_lights.queue_redraw()
		queue_redraw()
		return
	clock += minf(delta,0.05)*strength
	breeze = sin(clock*0.45)*0.62+sin(clock*0.91)*0.22
	var target := (pointer/DESIGN-Vector2(.5,.5)).clamp(-Vector2.ONE*.5,Vector2.ONE*.5)
	gaze = gaze.lerp(target,1.0-exp(-delta*3.0))
	hover_strength = move_toward(hover_strength,0.0 if hover_key.is_empty() else 1.0,delta*5.0)
	var idle := pow(maxf(0.0,sin(clock*.18)),24.0)*.45
	attention = move_toward(attention,1.0 if hover_key=="与雨宫澪交谈" else idle,delta*3.0)
	_click_age += delta
	if clock>=_blink_at:
		_blink_age = 0.0
		_blink_at = clock+4.1+sin(clock*0.31)*0.8
	_blink_age += delta
	var blink := sin(clampf(_blink_age/.16,0.0,1.0)*PI) if _blink_age<.16 else 0.0
	_foliage.set_shader_parameter("clock",clock)
	_foliage.set_shader_parameter("breeze",breeze)
	_foliage.set_shader_parameter("gaze",gaze)
	_foliage.set_shader_parameter("strength",strength)
	_mio.set_shader_parameter("strength",strength)
	_mio.set_shader_parameter("clock",clock)
	_mio.set_shader_parameter("breeze",breeze)
	_mio.set_shader_parameter("attention",attention)
	_mio.set_shader_parameter("blink",blink)
	_lights.queue_redraw()
	queue_redraw()

func set_hover(key: String) -> void:
	if blocked or pending or hover_key==key: return
	hover_key = key
	hover_strength = 0.0
	if clock-_last_foley<3.0: return
	var cue := "campus_bow" if key=="弓道场" else "campus_paper" if key in ["调查公告板","查看放课后观测记录"] else ""
	if cue.is_empty(): return
	_last_foley = clock
	AudioService.play_sfx(cue,-14.0)

func clear_hover(key: String) -> void:
	if hover_key==key: hover_key = ""

func feedback(key: String, rect: Rect2) -> void:
	_click_rect = rect
	_click_age = 0.0
	if key=="与雨宫澪交谈":
		_click_age = 1.0
		_blink_age = 0.0
	AudioService.play_sfx("campus_paper",-20.0)

func paint_feedback(surface: Control) -> void:
	if blocked: return
	if SIGNS.has(hover_key):
		var rect: Rect2 = SIGNS[hover_key]
		# Atlas slices include uneven outer padding; accent the visible frame.
		if hover_key == "保健室": rect = Rect2(1285,434,147,39)
		elif hover_key == "调查卡：继续调查": rect = Rect2(1384,818,201,32)
		var accent := GOLD if hover_key in ["观测会活动室","调查公告板","继续调查"] else BLUE
		accent.a = .65*hover_strength
		surface.draw_line(rect.position+Vector2(16,1),rect.position+Vector2(rect.size.x-16,1),accent,1.5,true)
		surface.draw_line(rect.end-Vector2(rect.size.x-16,1),rect.end-Vector2(16,1),accent,1.5,true)
	for key: String in unread:
		if not SIGNS.has(key): continue
		var rect: Rect2 = SIGNS[key]
		var center := Vector2(1413,436) if key=="保健室" else rect.position+Vector2(rect.size.x-8,5)
		var pulse := 0.0 if GameSkin.motion_level==0 else pow(maxf(0.0,sin(clock*1.4+key.length())),3.0)
		surface.draw_circle(center,5.0+pulse*4.0,Color(1.0,.84,.43,.08+pulse*.22))
		surface.draw_circle(center,2.3,Color(1.0,.88,.57,.45+pulse*.45))
	if new_record and GameSkin.motion_level>0:
		var lift := pow(maxf(0.0,sin(clock*.85)),4.0)*5.0
		if lift>.25:
			for corner: Vector2 in [Vector2(73,525),Vector2(146,475)]:
				surface.draw_colored_polygon(PackedVector2Array([corner,corner-Vector2(lift,0),corner-Vector2(0,lift)]),Color(.97,.85,.68,lift*.09))
	if GameSkin.motion_level==0 or _click_age>=.24: return
	var progress := _click_age/.24
	var edge := _click_rect.grow(1.5+progress*2.0)
	surface.draw_line(edge.position+Vector2(12,0),edge.position+Vector2(edge.size.x-12,0),Color(.91,.83,.64,(1-progress)*.65),1.2,true)
	surface.draw_line(edge.end-Vector2(edge.size.x-12,0),edge.end-Vector2(12,0),Color(.91,.83,.64,(1-progress)*.65),1.2,true)

func paint_lights(surface: Control) -> void:
	if blocked: return
	for key: String in LIGHTS:
		if hover_key!=key: continue
		var strength := .46*hover_strength*GameSkin.motion_factor()
		var center: Vector2 = LIGHTS[key]
		for ring: int in range(10):
			var radius := 20.0+float(ring)*7.5
			surface.draw_circle(center,radius,Color(1.0,.72,.36,strength*(1.0-float(ring)/10.0)/10.0))

func _draw() -> void:
	if blocked: return
	# Sparse resonance traces remain in the existing purple sky.
	for i: int in range(3):
		var points := PackedVector2Array()
		for j: int in range(37):
			var a := float(j)/36.0*PI*1.35+clock*.025+float(i)*.2
			points.append(Vector2(1205+cos(a)*(80+i*12),76+sin(a)*(15+i*4)))
		draw_polyline(points,Color(.72,.50,1.0,.10+sin(clock*.5+i)*.025),1.0,true)
		var trail := PackedVector2Array()
		for j: int in range(12):
			var a := clock*.19+float(i)*TAU/3.0-float(j)*.018
			trail.append(Vector2(1205+cos(a)*(80+i*12),76+sin(a)*(15+i*4)))
		for j: int in range(11):
			draw_line(trail[j],trail[j+1],Color(.83,.64,1.0,.44*(1.0-float(j)/12.0)),1.4,true)
		draw_circle(trail[0],4.0,Color(.78,.58,1.0,.10))
		draw_circle(trail[0],1.7,Color(.96,.85,1.0,.72))
	for i: int in range(8):
		var star := Vector2(1055+fmod(i*71.0,330.0),25+fmod(i*37.0,120.0))
		if Rect2(1337,27,254,42).has_point(star): continue
		var intensity := pow(maxf(0.0,sin(clock*.65+i*1.7)),4.0)*.55
		draw_circle(star,1.5,Color(.86,.76,1.0,intensity))
		draw_line(star-Vector2(0,4),star+Vector2(0,4),Color(.83,.71,1.0,intensity*.65),1.0,true)
		draw_line(star-Vector2(3,0),star+Vector2(3,0),Color(.83,.71,1.0,intensity*.55),1.0,true)
